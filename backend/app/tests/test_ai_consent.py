"""AI data-sharing consent — the gate that stops a personal photo reaching a
third-party AI provider without explicit permission (§10, Apple 5.1.1(i)).

The money-path assertions are the point of this file: a request blocked for
missing consent must cost nothing, create nothing, and transmit nothing.
"""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

import app.routers.v1.privacy as privacy_mod
import app.routers.v1.tryon as tryon_mod
from app.core.config import get_settings
from app.core.errors import ApiError
from app.main import app
from app.services.privacy import (
    AI_PERSONAL_IMAGE_CONSENT,
    CURRENT_AI_CONSENT_VERSION,
    PROVIDER_SCOPE,
    ConsentState,
    grant_ai_consent,
    read_ai_consent,
    require_ai_personal_image_consent,
    revoke_ai_consent,
)
from app.tests.test_giveaway_chat import _Conn, _Pool, _user

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": "user-123",
            "aud": "authenticated",
            "email": "a@b.com",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


# ── the state machine ────────────────────────────────────────────────────────


def test_no_row_is_not_consent() -> None:
    """A user who has never been asked has not agreed. The default must be the
    restrictive one — an absent row that read as permission would share the
    photo of every existing user without asking any of them."""
    conn = _Conn([])  # fetchrow → None
    state = asyncio.run(read_ai_consent(conn, "u1"))
    assert not state.granted
    assert not state.is_current
    assert state.version is None


def test_current_grant_satisfies_the_gate() -> None:
    conn = _Conn(
        [
            (
                "fetchrow",
                "from public.user_privacy_consents",
                {
                    "consent_version": CURRENT_AI_CONSENT_VERSION,
                    "provider_scope": PROVIDER_SCOPE,
                    "revoked_at": None,
                },
            )
        ]
    )
    state = asyncio.run(read_ai_consent(conn, "u1"))
    assert state.granted and state.is_current
    assert asyncio.run(require_ai_personal_image_consent(conn, "u1")) == (
        CURRENT_AI_CONSENT_VERSION
    )


def test_revoked_grant_does_not_satisfy_the_gate() -> None:
    """Withdrawal takes effect on the next NEW request, immediately."""
    conn = _Conn(
        [
            (
                "fetchrow",
                "from public.user_privacy_consents",
                {
                    "consent_version": CURRENT_AI_CONSENT_VERSION,
                    "provider_scope": PROVIDER_SCOPE,
                    "revoked_at": "2026-08-12T00:00:00Z",
                },
            )
        ]
    )
    state = asyncio.run(read_ai_consent(conn, "u1"))
    assert not state.granted and not state.is_current
    with pytest.raises(ApiError) as exc:
        asyncio.run(require_ai_personal_image_consent(conn, "u1"))
    assert exc.value.code == "AI_DATA_SHARING_CONSENT_REQUIRED"


def test_stale_version_requires_consent_again() -> None:
    """A version bump means the promise changed, so the old agreement no longer
    covers it and the user is asked exactly once more."""
    conn = _Conn(
        [
            (
                "fetchrow",
                "from public.user_privacy_consents",
                {
                    "consent_version": CURRENT_AI_CONSENT_VERSION - 1,
                    "provider_scope": "something_older",
                    "revoked_at": None,
                },
            )
        ]
    )
    state = asyncio.run(read_ai_consent(conn, "u1"))
    assert state.granted  # they did agree to something
    assert not state.is_current  # but not to this
    with pytest.raises(ApiError):
        asyncio.run(require_ai_personal_image_consent(conn, "u1"))


def test_newer_version_than_required_still_passes() -> None:
    """A rolling deploy can leave an older process enforcing an older version. A
    user holding a NEWER grant agreed to more, not less, and must not be
    re-prompted by the lagging process."""
    state = ConsentState(
        granted=True,
        version=CURRENT_AI_CONSENT_VERSION + 1,
        provider_scope=PROVIDER_SCOPE,
    )
    assert state.is_current


def test_grant_clears_a_previous_revocation() -> None:
    """Re-allowing after withdrawing is a fresh decision, so revoked_at is
    cleared and granted_at re-stamped — the date we would have to defend is the
    one actually in force."""
    conn = _Conn([])
    asyncio.run(grant_ai_consent(conn, "u1"))
    sql = next(s for m, s, _ in conn.calls if m == "execute")
    assert "insert into public.user_privacy_consents" in sql
    assert "on conflict (user_id, consent_type) do update" in sql
    assert "revoked_at      = null" in sql or "revoked_at = null" in sql


def test_revoke_is_idempotent() -> None:
    """Pressing Withdraw twice is safe: the second call finds nothing to update
    and still reports "not granted" rather than erroring."""
    conn = _Conn([])  # the UPDATE ... returning matches nothing
    state = asyncio.run(revoke_ai_consent(conn, "u1"))
    assert not state.granted


def test_consent_type_is_the_stable_semantic_key() -> None:
    """The key names the DATA FLOW, not a screen — so a new feature that ships a
    personal image out is covered by the consent already given."""
    assert AI_PERSONAL_IMAGE_CONSENT == "ai_personal_image_third_party_processing"


def test_provider_scope_names_every_recipient() -> None:
    """Both providers genuinely receive the photo: OpenAI for the mandatory
    safety check, FASHN for the render. Recording only FASHN would make the
    stored consent narrower than the actual sharing."""
    assert "fashn" in PROVIDER_SCOPE
    assert "openai" in PROVIDER_SCOPE


# ── the submit path: nothing spent, nothing sent ─────────────────────────────


#: Enough DB answers to walk the submit path as far as the consent gate: a
#: solvent free-plan user with no idempotency replay. Everything past the gate is
#: asserted on separately, so nothing here needs to succeed.
_SOLVENT_USER = [
    (
        "fetchrow",
        "from public.credits where user_id",
        {"balance": 50, "daily_free_used": 0, "topup_balance": 0},
    ),
]


def _tryon_body(model_source: str = "own_photo") -> dict:
    body = {
        "person_image_url": "https://example.test/me.jpg",
        "garment_image_url": "https://example.test/shirt.jpg",
        "model_source": model_source,
    }
    if model_source == "studio_model":
        body["preset_model_id"] = str(uuid.uuid4())
    return body


def test_missing_consent_blocks_before_moderation_and_before_spend(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The whole point. A personal-photo render with no consent must be refused
    BEFORE the image reaches OpenAI's moderation endpoint (the first egress),
    before FASHN, and before a single credit is reserved."""
    moderated: list[str] = []

    async def _never(*args: object, **kwargs: object) -> None:
        moderated.append("called")

    spent: list[str] = []

    async def _spend(*args: object, **kwargs: object) -> None:
        spent.append("charged")

    monkeypatch.setattr(tryon_mod, "_moderate_one", _never)
    monkeypatch.setattr(tryon_mod, "spend_credit", _spend)

    async def _no_consent(conn: object, user_id: str) -> int:
        raise ApiError("AI_DATA_SHARING_CONSENT_REQUIRED", "Permission needed.", 403)

    monkeypatch.setattr(tryon_mod, "require_ai_personal_image_consent", _no_consent)

    conn = _Conn(list(_SOLVENT_USER))
    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))

    resp = client.post(
        "/v1/tryon",
        json=_tryon_body(),
        headers={**_auth(), "Idempotency-Key": str(uuid.uuid4())},
    )

    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "AI_DATA_SHARING_CONSENT_REQUIRED"
    assert moderated == [], "the photo must not reach the moderation provider"
    assert spent == [], "a blocked request must never reserve credits"
    # And no job row was written.
    assert not any("insert into public.tryon_jobs" in s for _, s, _ in conn.calls), (
        "a blocked request must not create a job"
    )


def test_studio_model_render_is_not_gated(monkeypatch: pytest.MonkeyPatch) -> None:
    """A curated studio model is OUR photograph. Asking permission to share it
    would be friction that teaches people to dismiss the prompt that matters."""
    asked: list[str] = []

    async def _record(conn: object, user_id: str) -> int:
        asked.append(user_id)
        return CURRENT_AI_CONSENT_VERSION

    monkeypatch.setattr(tryon_mod, "require_ai_personal_image_consent", _record)

    # Fail the request right after the gate would have run, so the test asserts
    # on the gate alone without standing up the whole submit path.
    async def _boom(*args: object, **kwargs: object) -> str:
        raise ApiError("NOT_FOUND", "stop here", 404)

    monkeypatch.setattr(tryon_mod, "_resolve_person_image", _boom)

    conn = _Conn(list(_SOLVENT_USER))
    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))

    client.post(
        "/v1/tryon",
        json=_tryon_body("studio_model"),
        headers={**_auth(), "Idempotency-Key": str(uuid.uuid4())},
    )
    assert asked == [], "a studio-model render must not ask for personal-photo consent"


# ── the API surface ──────────────────────────────────────────────────────────


def test_consent_endpoints_require_auth() -> None:
    assert client.get("/v1/privacy/ai-consent").status_code == 401
    assert client.post("/v1/privacy/ai-consent", json={"consent_version": 1}).status_code == 401
    assert client.delete("/v1/privacy/ai-consent").status_code == 401


def test_cannot_record_consent_to_an_unshown_future_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A client may not agree on the user's behalf to terms it never displayed."""
    conn = _Conn([])
    monkeypatch.setattr(privacy_mod, "get_pool", lambda: _Pool(conn))
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            privacy_mod.post_ai_consent(
                privacy_mod.AiConsentGrantRequest(consent_version=CURRENT_AI_CONSENT_VERSION + 5),
                _user(),
            )
        )
    assert exc.value.code == "VALIDATION_ERROR"


def test_get_reports_the_required_version(monkeypatch: pytest.MonkeyPatch) -> None:
    """The client never hardcodes the enforced version — it is told, so an old
    build cannot believe a stale grant is still good."""
    conn = _Conn([])
    monkeypatch.setattr(privacy_mod, "get_pool", lambda: _Pool(conn))
    out = asyncio.run(privacy_mod.get_ai_consent(_user()))
    assert out.required_version == CURRENT_AI_CONSENT_VERSION
    assert out.is_current is False
    assert out.consent_type == AI_PERSONAL_IMAGE_CONSENT


# ── log safety ───────────────────────────────────────────────────────────────


def test_consent_denial_logs_no_image_or_url(caplog: pytest.LogCaptureFixture) -> None:
    """A denial line may name the user and the versions; it may never carry the
    photo, its URL, or a signed token (§14)."""
    conn = _Conn([])
    with caplog.at_level("INFO"):
        with pytest.raises(ApiError):
            asyncio.run(require_ai_personal_image_consent(conn, "user-123"))
    text = caplog.text.lower()
    assert "http" not in text
    assert "base64" not in text
    assert "x-amz" not in text
    assert "token" not in text
