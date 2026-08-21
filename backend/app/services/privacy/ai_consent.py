"""Consent to send a user's OWN photo to a third-party AI provider.

This is the durable source of truth. The app keeps a cache so the sheet does not
flash on every render, but the cache is an optimisation: nothing may be shared on
the strength of it alone, which is why [require_ai_personal_image_consent] runs
server-side before any personal image is transmitted (CLAUDE.md §11).

SCOPE — what this consent actually covers, verified against the code paths:

  * FASHN.ai (FASHN LTD) — the render itself. The person image is inlined as
    base64 into the /v1/run payload (`tryon_worker._inline_person_image`), so
    FASHN receives the bytes directly over TLS and never fetches a URL of ours.
  * OpenAI — the MANDATORY safety check on the same photo before any render is
    created (`services.moderation.openai_moderator`, §19). OpenAI is handed a
    short-lived signed URL which its servers fetch.

Both happen inside one user action and neither is optional for a personal-photo
render, so they are one consent decision rather than two prompts. Naming only
FASHN would have been the more convenient copy and the less true one — and
Apple's Guideline 2.1 question is specifically "with whom is it shared".

NOT covered here, because no personal image leaves the app:
  * the free 2D preview — entirely on-device;
  * a curated studio-model render — the body is our own catalog image;
  * background removal — on-device ML Kit, or our own BiRefNet worker on our own
    infrastructure, which is first-party processing, not third-party sharing.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import asyncpg

from app.core.errors import ApiError
from app.models.common import ErrorCode

log = logging.getLogger("fashionos.privacy.consent")

#: The semantic key. Deliberately describes the DATA FLOW rather than a screen,
#: so a new feature that ships a personal image out is covered by the consent the
#: user already gave instead of inventing a second, near-identical prompt.
AI_PERSONAL_IMAGE_CONSENT = "ai_personal_image_third_party_processing"

#: Bump ONLY when the provider set, the purpose, or the material scope of the
#: sharing changes. Every bump costs each existing user one more interruption, so
#: it is not a version for copy edits — it is a version for the promise.
#:
#: v2 — a DELIBERATE EXCEPTION to the rule above, and the reason is recorded
#: here so nobody later reads it as a mistake. The provider set did not change;
#: v2 exists because v1 was granted by accounts that never saw the disclosure in
#: its shipped form, including store-review accounts, and the only way to make
#: "this user has seen and accepted the current disclosure" true for EVERY
#: existing account is to require a version none of them can already hold.
#:
#: It is a one-time correction, not a precedent. The next bump should again be
#: about the promise.
CURRENT_AI_CONSENT_VERSION = 2

#: Recorded on the row so a future provider change is visible in the data. Kept
#: in the order the user's photo actually reaches them.
PROVIDER_SCOPE = "openai_moderation,fashn"

_CONSENT_REQUIRED_MESSAGE = (
    "To create this AI result we need your permission to send your photo for "
    "AI processing. You can allow it when you tap Generate, or in "
    "Settings → Privacy → AI Photo Processing."
)


@dataclass(frozen=True)
class ConsentState:
    """What we currently hold for one user + consent type."""

    granted: bool
    version: int | None
    provider_scope: str | None
    required_version: int = CURRENT_AI_CONSENT_VERSION

    @property
    def is_current(self) -> bool:
        """Granted AND at (or beyond) the version we now require.

        `>=` rather than `==` on purpose: a user who somehow holds a NEWER grant
        than this deploy requires — a rolling deploy, an older worker — has
        agreed to more, not less, and must not be re-prompted by an old process.
        """
        return self.granted and self.version is not None and self.version >= self.required_version


async def read_ai_consent(conn: asyncpg.Connection, user_id: str) -> ConsentState:
    """The user's current AI data-sharing consent state."""
    row = await conn.fetchrow(
        """
        select consent_version, provider_scope, revoked_at
          from public.user_privacy_consents
         where user_id = $1::uuid and consent_type = $2
        """,
        str(user_id),
        AI_PERSONAL_IMAGE_CONSENT,
    )
    if row is None:
        return ConsentState(granted=False, version=None, provider_scope=None)
    return ConsentState(
        granted=row["revoked_at"] is None,
        version=row["consent_version"],
        provider_scope=row["provider_scope"],
    )


async def _record_event(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    action: str,
    version: int,
    provider_scope: str | None,
) -> None:
    """Append the decision to the audit log (0077).

    Best-effort by design. `user_privacy_consents` is the state the gate reads;
    this table is evidence beside it. A logging failure must never turn a
    consent the user actually gave into a refusal, so it is caught — and loud in
    the logs, because silently losing consent evidence is its own problem.
    """
    try:
        await conn.execute(
            """
            insert into public.user_privacy_consent_events
              (user_id, consent_type, action, consent_version, provider_scope, source)
            values ($1::uuid, $2, $3, $4, $5, 'app')
            """,
            str(user_id),
            AI_PERSONAL_IMAGE_CONSENT,
            action,
            version,
            provider_scope,
        )
    except Exception as exc:  # noqa: BLE001 - evidence must not block the decision
        log.error("consent audit row not written for user %s (%s): %s", user_id, action, exc)


async def grant_ai_consent(
    conn: asyncpg.Connection, user_id: str, *, version: int = CURRENT_AI_CONSENT_VERSION
) -> ConsentState:
    """Record an explicit grant (idempotent).

    Re-granting clears `revoked_at` and re-stamps `granted_at`: a user who
    withdrew and then allowed again has consented afresh, and the date we could
    have to defend is the date of the decision that is actually in force. The
    OVERWRITTEN decision is not lost — it is in `user_privacy_consent_events`,
    which is exactly why that table exists (0077).
    """
    await conn.execute(
        """
        insert into public.user_privacy_consents
          (user_id, consent_type, consent_version, provider_scope, granted_at, revoked_at)
        values ($1::uuid, $2, $3, $4, now(), null)
        on conflict (user_id, consent_type) do update
           set consent_version = excluded.consent_version,
               provider_scope  = excluded.provider_scope,
               granted_at      = now(),
               revoked_at      = null
        """,
        str(user_id),
        AI_PERSONAL_IMAGE_CONSENT,
        version,
        PROVIDER_SCOPE,
    )
    await _record_event(
        conn, user_id, action="granted", version=version, provider_scope=PROVIDER_SCOPE
    )
    return ConsentState(granted=True, version=version, provider_scope=PROVIDER_SCOPE)


async def revoke_ai_consent(conn: asyncpg.Connection, user_id: str) -> ConsentState:
    """Withdraw consent. Governs NEW sharing only — a render already accepted
    keeps the authorisation it was submitted under (see `tryon_jobs.consent_version`).

    Revoking something never granted is a no-op that still reports "not granted",
    so the settings toggle is safe to press twice.
    """
    row = await conn.fetchrow(
        """
        update public.user_privacy_consents
           set revoked_at = now()
         where user_id = $1::uuid and consent_type = $2 and revoked_at is null
        returning consent_version, provider_scope
        """,
        str(user_id),
        AI_PERSONAL_IMAGE_CONSENT,
    )
    if row is None:
        # Nothing was in force, so nothing was withdrawn — no event to record.
        state = await read_ai_consent(conn, user_id)
        return ConsentState(
            granted=False, version=state.version, provider_scope=state.provider_scope
        )
    await _record_event(
        conn,
        user_id,
        action="revoked",
        version=row["consent_version"],
        provider_scope=row["provider_scope"],
    )
    return ConsentState(
        granted=False, version=row["consent_version"], provider_scope=row["provider_scope"]
    )


async def require_ai_personal_image_consent(conn: asyncpg.Connection, user_id: str) -> int:
    """Assert current consent before ANY personal image is transmitted, and
    return the version it was authorised under so the job can record it.

    MUST be called before the first egress of the user's photo. In the try-on
    submit path that means before OpenAI moderation — not merely before FASHN —
    because moderation is itself a third-party transmission of the same image.

    Raises `AI_DATA_SHARING_CONSENT_REQUIRED` (403) with no credit spent and no
    job created; the app maps the code back to the disclosure sheet (§13).
    """
    state = await read_ai_consent(conn, user_id)
    if state.is_current:
        return CURRENT_AI_CONSENT_VERSION
    # Category only — never the user's image, URL, or any content (§14).
    log.info(
        "personal-image AI request blocked: consent missing/stale for user %s (have=%s, need=%s)",
        user_id,
        state.version,
        CURRENT_AI_CONSENT_VERSION,
    )
    raise ApiError(
        ErrorCode.AI_DATA_SHARING_CONSENT_REQUIRED,
        _CONSENT_REQUIRED_MESSAGE,
        403,
    )
