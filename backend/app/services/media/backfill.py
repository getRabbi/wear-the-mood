"""Verified, reversible backfill of legacy images → R2 (INFRA_UPGRADE 1C).

Operates on the media_assets ledger. A legacy row (storage_provider='legacy') is
downloaded from the old store, re-uploaded to the correct R2 bucket (public or
private per the row's visibility), VERIFIED (the object persisted at the right
size + a thumbnail exists), and ONLY THEN flipped to storage_provider='r2'.

Safety properties:
  * legacy_url is never touched → rollback is lossless and reads never break
    mid-migration (per-record resolution serves legacy until a row flips).
  * Idempotent + resumable: an already-r2 row is skipped.
  * A row that fails download/verify is left untouched (stays legacy).
  * NEVER deletes old objects (a separate guarded cleanup comes later).

The runnable CLI is scripts/backfill_media.py; the logic lives here so it is
unit-testable. Run dry-run first, then against the -staging buckets, then prod.
"""

from __future__ import annotations

import logging

import asyncpg

from app.services.media import get_storage_provider, resolve_view_url
from app.services.media.r2 import R2StorageProvider
from app.services.storage import download_image

log = logging.getLogger("fashionos.backfill")

_CTYPE = {
    ".png": "image/png",
    ".webp": "image/webp",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}


def _content_type(url: str) -> str:
    path = url.split("?")[0].lower()
    for ext, ct in _CTYPE.items():
        if path.endswith(ext):
            return ct
    return "image/jpeg"


async def dry_run_counts(
    conn: asyncpg.Connection, sector: str | None = None
) -> list[asyncpg.Record]:
    """Count legacy images that WOULD migrate, grouped by sector + visibility."""
    return await conn.fetch(
        """
        select owner_kind, role, visibility, count(*) as n
          from public.media_assets
         where storage_provider = 'legacy' and deleted_at is null
           and ($1::text is null or owner_kind = $1)
         group by owner_kind, role, visibility
         order by owner_kind, role, visibility
        """,
        sector,
    )


async def migrate_row(
    conn: asyncpg.Connection, provider: R2StorageProvider, row: object
) -> str:
    """Copy → verify → flip ONE asset. Returns 'migrated' | 'skipped' | 'failed'."""
    if row["storage_provider"] == "r2":
        return "skipped"  # resumable: already migrated

    fetch_url = await resolve_view_url(
        storage_provider="legacy",
        visibility=row["visibility"],
        owner_kind=row["owner_kind"],
        role=row["role"],
        legacy_url=row["legacy_url"],
    )
    if not fetch_url:
        log.warning("asset %s: no fetchable legacy url", row["id"])
        return "failed"
    try:
        data = await download_image(fetch_url)
    except Exception as exc:
        log.warning("asset %s: download failed: %s", row["id"], exc)
        return "failed"

    prefix = f"{row['user_id'] or 'shared'}/{row['owner_kind']}"
    stored = await provider.put(
        data,
        visibility=row["visibility"],
        prefix=prefix,
        content_type=_content_type(fetch_url),
        make_thumbnail=row["role"] != "thumbnail",  # a 'thumbnail' role IS the thumb
    )

    # VERIFY before flipping the row — a failed verify leaves it legacy.
    try:
        size = await provider.head(
            object_key=stored.object_key, visibility=row["visibility"]
        )
        if size != len(data):
            log.warning(
                "asset %s: size mismatch r2=%s src=%s", row["id"], size, len(data)
            )
            return "failed"
        if stored.thumbnail_key:
            tsize = await provider.head(
                object_key=stored.thumbnail_key, visibility=row["visibility"]
            )
            if tsize <= 0:
                log.warning("asset %s: thumbnail missing after upload", row["id"])
                return "failed"
    except Exception as exc:
        log.warning("asset %s: verify failed: %s", row["id"], exc)
        return "failed"

    await conn.execute(
        """
        update public.media_assets set
          storage_provider = 'r2',
          object_key       = $2,
          thumbnail_key    = $3,
          public_url       = $4,
          content_hash     = $5,
          migrated_at      = now()
        where id = $1 and storage_provider = 'legacy'
        """,
        row["id"],
        stored.object_key,
        stored.thumbnail_key,
        stored.public_url,
        stored.content_hash,
    )
    return "migrated"


async def migrate(
    conn: asyncpg.Connection, sector: str | None = None, limit: int = 100_000
) -> dict[str, int]:
    """Migrate up to `limit` legacy assets. Reports migrated/skipped/failed."""
    provider = get_storage_provider()
    if not isinstance(provider, R2StorageProvider):
        raise RuntimeError("R2 is not configured — cannot migrate.")
    rows = await conn.fetch(
        """
        select id, owner_kind, role, visibility, storage_provider, legacy_url, user_id
          from public.media_assets
         where storage_provider = 'legacy' and deleted_at is null
           and ($1::text is null or owner_kind = $1)
         order by created_at
         limit $2
        """,
        sector,
        limit,
    )
    counts = {"migrated": 0, "skipped": 0, "failed": 0}
    for row in rows:
        counts[await migrate_row(conn, provider, row)] += 1
    return counts


async def rollback(conn: asyncpg.Connection, sector: str | None = None) -> int:
    """Flip migrated rows back to legacy (legacy_url intact → no data loss). The
    R2 objects are left in place; reads resolve from legacy_url again."""
    result = await conn.execute(
        """
        update public.media_assets set storage_provider = 'legacy', migrated_at = null
         where storage_provider = 'r2'
           and ($1::text is null or owner_kind = $1)
        """,
        sector,
    )
    try:
        return int(result.split()[-1])
    except (ValueError, IndexError):
        return 0
