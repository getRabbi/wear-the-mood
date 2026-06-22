"""Media deletion service (Phase 4A — deletion alignment, §10).

Two entry points, both **best-effort + idempotent + logged** — a failed object
delete NEVER blocks the DB delete (orphans can be swept later):

  * ``delete_user_media(conn, user_id)`` — account ERASURE. Prefix-deletes
    ``<uid>/`` in BOTH R2 buckets and ALL Supabase buckets (catches ledgered AND
    non-ledgered objects), then drops the user's media_assets rows.
  * ``delete_owner_media(conn, owner_kind, owner_id)`` — individual content.
    Deletes the object(s) tracked by media_assets for that owner row and
    soft-deletes the ledger rows.

NOT wired to any endpoint here — account/content deletion wiring is A2 / A3.
"""

from __future__ import annotations

import logging
import re

import asyncpg

from app.services import storage
from app.services.media import get_storage_provider
from app.services.media.legacy import LEGACY_PRIVATE_BUCKET
from app.services.media.r2 import R2StorageProvider

log = logging.getLogger("fashionos.media.deletion")

# Every Supabase bucket that holds user objects under a <uid>/ prefix.
_SUPABASE_BUCKETS = (
    "wardrobe",
    "avatars",
    "profile-pictures",
    "post-images",
    "tryon-results",
)

# Pull bucket + path out of a Supabase public object URL.
_PUBLIC_OBJECT_RE = re.compile(r"/storage/v1/object/public/([^/]+)/(.+)$")


async def delete_user_media(conn: asyncpg.Connection, user_id: str) -> dict[str, int]:
    """Erase ALL of a user's stored images (account deletion). Best-effort: a
    bucket that errors records -1 and the rest still run. Returns per-store counts."""
    counts: dict[str, int] = {}
    provider = get_storage_provider()

    # R2 — every key for a user is under <uid>/ (both buckets).
    if isinstance(provider, R2StorageProvider):
        for vis in ("public", "private"):
            try:
                counts[f"r2:{vis}"] = await provider.delete_prefix(
                    prefix=f"{user_id}/", visibility=vis
                )
            except Exception as exc:
                log.warning("R2 %s prefix delete failed for user %s: %s", vis, user_id, exc)
                counts[f"r2:{vis}"] = -1

    # Legacy Supabase buckets (catches non-ledgered objects too).
    for bucket in _SUPABASE_BUCKETS:
        try:
            counts[f"sb:{bucket}"] = await storage.delete_prefix(bucket, user_id)
        except Exception as exc:
            log.warning("Supabase %s prefix delete failed for user %s: %s", bucket, user_id, exc)
            counts[f"sb:{bucket}"] = -1

    # Drop the ledger rows — the account/profile is gone, no orphan ledger.
    try:
        await conn.execute(
            "delete from public.media_assets where user_id = $1::uuid", user_id
        )
    except Exception as exc:
        log.warning("media_assets row delete failed for user %s: %s", user_id, exc)

    log.info("deleted media for user %s: %s", user_id, counts)
    return counts


def _legacy_target(
    owner_kind: str, role: str, legacy_url: str | None
) -> tuple[str, str] | None:
    """(bucket, path) for a legacy Supabase object, or None if undeterminable."""
    if not legacy_url:
        return None
    m = _PUBLIC_OBJECT_RE.search(legacy_url)
    if m:
        return m.group(1), m.group(2).split("?")[0]
    if legacy_url.startswith("http"):
        return None  # unknown URL shape — don't guess
    bucket = LEGACY_PRIVATE_BUCKET.get((owner_kind, role))
    return (bucket, legacy_url) if bucket else None


async def delete_owner_media(
    conn: asyncpg.Connection, owner_kind: str, owner_id: str
) -> int:
    """Delete the media object(s) tracked for one owner row (individual content)
    and soft-delete its ledger rows. Best-effort. Returns objects acted on."""
    rows = await conn.fetch(
        "select id, role, visibility, storage_provider, object_key, thumbnail_key, "
        "legacy_url from public.media_assets "
        "where owner_kind = $1 and owner_id = $2::uuid and deleted_at is null",
        owner_kind,
        owner_id,
    )
    provider = get_storage_provider()
    acted = 0
    for r in rows:
        try:
            if (
                r["storage_provider"] == "r2"
                and isinstance(provider, R2StorageProvider)
                and r["object_key"]
            ):
                await provider.delete(
                    object_key=r["object_key"],
                    visibility=r["visibility"],
                    thumbnail_key=r["thumbnail_key"],
                )
                acted += 1
            else:
                target = _legacy_target(owner_kind, r["role"], r["legacy_url"])
                if target:
                    await storage.delete_object(target[0], target[1])
                    acted += 1
        except Exception as exc:
            log.warning("object delete failed for asset %s: %s", r["id"], exc)

    # Soft-delete the ledger rows (audit trail; caller removes the owner row).
    await conn.execute(
        "update public.media_assets set deleted_at = now() "
        "where owner_kind = $1 and owner_id = $2::uuid and deleted_at is null",
        owner_kind,
        owner_id,
    )
    return acted
