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
from app.services.media.repo import insert_asset
from app.services.storage import download_image

log = logging.getLogger("fashionos.backfill")

# Roles that must NOT get a thumbnail.
#
#  * `thumbnail` IS the thumbnail.
#  * `cutout_mask` is an alpha mask the free Erase/Restore editor re-reads at
#    full resolution — it is never drawn as a card, so a downscaled copy would
#    be storage spent on something nothing can use, and a lossy one at that.
_NO_THUMBNAIL_ROLES = ("thumbnail", "cutout_mask")

#: The exclusion as a SQL fragment. Built from the tuple above rather than typed
#: out twice, and safe to interpolate: these are static identifiers defined in
#: this module, never user input.
_ROLE_EXCLUSION = "role not in (" + ", ".join(f"'{r}'" for r in _NO_THUMBNAIL_ROLES) + ")"

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


async def migrate_row(conn: asyncpg.Connection, provider: R2StorageProvider, row: object) -> str:
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
        size = await provider.head(object_key=stored.object_key, visibility=row["visibility"])
        if size != len(data):
            log.warning("asset %s: size mismatch r2=%s src=%s", row["id"], size, len(data))
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


#: Where an AI-enhanced cover sits on the ledger once it is enrolled. Matches
#: exactly what `ai_jobs_worker._record_generated` writes for a NEW cover, so an
#: enrolled row and a natively-written one are the same shape.
COVER_OWNER_KIND = "generated_image"

#: Same idea for a try-on render, matching `tryon_worker`'s own `insert_asset`.
RESULT_OWNER_KIND = "tryon_result"
RESULT_ROLE = "result"


async def unledgered_tryon_result_counts(conn: asyncpg.Connection) -> dict[str, int]:
    """Try-on renders that have no media_assets row at all.

    Same cause as the covers: the worker only records a ledger row on the R2
    branch, so anything stored while that was off is a bare Supabase path with
    nothing pointing at it. `list_tryon_results` falls back to `_display_url`
    for these, which serves the full render and has no thumbnail to offer.

    An `http` ref is excluded: that is a provider URL we never took ownership
    of, so there is no object of ours to enrol.
    """
    row = await conn.fetchrow(
        """
        select
          count(*) as results,
          count(*) filter (where m.id is not null) as on_ledger,
          count(*) filter (
            where m.id is null and t.result_image_url is not null
              and t.result_image_url not like 'http%'
          ) as enrollable,
          count(*) filter (
            where m.id is null and (t.result_image_url is null
              or t.result_image_url like 'http%')
          ) as unresolvable
        from public.tryon_results t
        left join public.media_assets m
          on m.owner_kind = 'tryon_result' and m.owner_id = t.id and m.deleted_at is null
        """
    )
    return dict(row) if row else {}


async def enrol_unledgered_tryon_results(conn: asyncpg.Connection) -> dict[str, int]:
    """Put pre-R2 try-on renders ON the ledger. Same contract as
    [enrol_unledgered_covers]: adds a row, never an object, and skips anything
    already recorded so a rerun resumes.

    Unlike a cover, the read path finds these by `owner_id` rather than by path,
    so once migrated they need no resolver change to serve their thumbnail.
    """
    rows = await conn.fetch(
        """
        select t.id, t.user_id, t.result_image_url as path
          from public.tryon_results t
          left join public.media_assets m
            on m.owner_kind = 'tryon_result' and m.owner_id = t.id and m.deleted_at is null
         where m.id is null
           and t.result_image_url is not null
           and t.result_image_url not like 'http%'
         order by t.created_at
        """
    )
    counts = {"enrolled": 0, "skipped": 0, "unresolvable": 0}
    for row in rows:
        existing = await conn.fetchval(
            "select 1 from public.media_assets "
            "where owner_kind = $1 and owner_id = $2::uuid and deleted_at is null limit 1",
            RESULT_OWNER_KIND,
            str(row["id"]),
        )
        if existing:
            counts["skipped"] += 1
            continue
        await insert_asset(
            conn,
            owner_kind=RESULT_OWNER_KIND,
            owner_id=row["id"],
            role=RESULT_ROLE,
            user_id=row["user_id"],
            visibility="private",
            storage_provider="legacy",
            legacy_url=row["path"],
        )
        counts["enrolled"] += 1
    return counts


async def unledgered_cover_counts(conn: asyncpg.Connection) -> dict[str, int]:
    """How many AI covers exist, and how many are invisible to the ledger.

    A cover written before `r2_writes_enabled` never got a media_assets row at
    all — `_record_generated` only inserts one when the R2 branch ran. So it is
    not a 'legacy' row that `migrate` can pick up; it is not a row. `migrate`
    would report zero and be telling the truth about the wrong question.
    """
    row = await conn.fetchrow(
        """
        select
          count(*) as covers,
          count(*) filter (where m.id is not null) as on_ledger,
          count(*) filter (where m.id is null and g.id is not null) as enrollable,
          count(*) filter (where m.id is null and g.id is null) as unresolvable
        from public.wardrobe_items w
        left join public.generated_images g on g.output_url = w.cover_image_url
        left join public.media_assets m
          on (m.object_key = w.cover_image_url or m.legacy_url = w.cover_image_url)
         and m.deleted_at is null
        where w.cover_image_url is not null
        """
    )
    return dict(row) if row else {}


async def enrol_unledgered_covers(conn: asyncpg.Connection) -> dict[str, int]:
    """Put pre-R2 AI covers ON the ledger so the existing migrate flow can move
    them. Returns enrolled/skipped/unresolvable counts.

    This adds a ROW, never an object: `legacy_url` is the Supabase path the
    cover already lives at and `storage_provider='legacy'`, which is precisely
    the state `migrate_row` is built to consume. Nothing is copied, rewritten or
    deleted here, and until `migrate` runs the read path resolves exactly as it
    did before.

    Ownership mirrors `_record_generated`: `generated_image` / the
    `generated_images` row / its own `type`. A cover with no matching
    `generated_images` row is left alone rather than filed under an invented
    owner — there is no id to be honest about.

    Idempotent: a cover whose path is already on the ledger is skipped, so a
    rerun after a partial failure resumes rather than duplicating.
    """
    rows = await conn.fetch(
        """
        select w.cover_image_url as path, w.user_id, g.id as gen_id, g.type as gen_type
          from public.wardrobe_items w
          left join public.generated_images g on g.output_url = w.cover_image_url
          left join public.media_assets m
            on (m.object_key = w.cover_image_url or m.legacy_url = w.cover_image_url)
           and m.deleted_at is null
         where w.cover_image_url is not null
           and m.id is null
         order by w.created_at
        """
    )
    counts = {"enrolled": 0, "skipped": 0, "unresolvable": 0}
    for row in rows:
        if not row["gen_id"]:
            log.warning("cover %s: no generated_images row; left alone", row["path"])
            counts["unresolvable"] += 1
            continue
        # Re-check inside the loop: two covers can share one generated image.
        existing = await conn.fetchval(
            "select 1 from public.media_assets "
            "where (object_key = $1 or legacy_url = $1) and deleted_at is null limit 1",
            row["path"],
        )
        if existing:
            counts["skipped"] += 1
            continue
        await insert_asset(
            conn,
            owner_kind=COVER_OWNER_KIND,
            owner_id=row["gen_id"],
            role=row["gen_type"],
            user_id=row["user_id"],
            visibility="private",
            storage_provider="legacy",
            legacy_url=row["path"],
        )
        counts["enrolled"] += 1
    return counts


async def missing_thumbnail_counts(
    conn: asyncpg.Connection, sector: str | None = None
) -> list[asyncpg.Record]:
    """Count R2 rows that SHOULD have a thumbnail and do not."""
    return await conn.fetch(
        f"""
        select owner_kind, role, visibility, count(*) as n
          from public.media_assets
         where storage_provider = 'r2' and deleted_at is null
           and thumbnail_key is null
           and object_key is not null
           and {_ROLE_EXCLUSION}
           and ($1::text is null or owner_kind = $1)
         group by owner_kind, role, visibility
         order by owner_kind, role, visibility
        """,
        sector,
    )


async def add_thumbnail_row(
    conn: asyncpg.Connection, provider: R2StorageProvider, row: object
) -> str:
    """Generate + verify + record ONE missing thumbnail. 'added' | 'skipped' | 'failed'.

    Same safety shape as [migrate_row], and for the same reason: the ORIGINAL is
    never rewritten, never re-keyed and never deleted. A thumbnail is written
    beside it, `head` proves it landed, and only then does the ledger row learn
    about it. A failure anywhere leaves the row exactly as it was, so the read
    path keeps serving the full object and a rerun simply tries again.
    """
    if row["thumbnail_key"]:
        return "skipped"  # resumable: already has one
    try:
        source = await provider.view_url(object_key=row["object_key"], visibility=row["visibility"])
        data = await download_image(source)
    except Exception as exc:
        log.warning("asset %s: source download failed: %s", row["id"], exc)
        return "failed"

    try:
        thumbnail_key = await provider.put_thumbnail_for(
            data, object_key=row["object_key"], visibility=row["visibility"]
        )
    except Exception as exc:
        log.warning("asset %s: thumbnail generate/upload failed: %s", row["id"], exc)
        return "failed"

    # VERIFY before recording — an unrecorded thumbnail is a harmless orphan; a
    # recorded-but-absent one is a broken card.
    try:
        size = await provider.head(object_key=thumbnail_key, visibility=row["visibility"])
        if size <= 0:
            log.warning("asset %s: thumbnail missing after upload", row["id"])
            return "failed"
    except Exception as exc:
        log.warning("asset %s: thumbnail verify failed: %s", row["id"], exc)
        return "failed"

    # Guarded on `thumbnail_key is null` so a concurrent writer wins rather than
    # being overwritten.
    await conn.execute(
        "update public.media_assets set thumbnail_key = $2, updated_at = now() "
        "where id = $1 and thumbnail_key is null",
        row["id"],
        thumbnail_key,
    )
    return "added"


async def add_missing_thumbnails(
    conn: asyncpg.Connection, sector: str | None = None, limit: int = 100_000
) -> dict[str, int]:
    """Backfill thumbnails for R2 objects written before their upload path asked
    for one — AI-enhanced covers (`generated_image`) and try-on results
    (`tryon_result`) above all. Reports added/skipped/failed."""
    provider = get_storage_provider()
    if not isinstance(provider, R2StorageProvider):
        raise RuntimeError("R2 is not configured — cannot backfill thumbnails.")
    rows = await conn.fetch(
        f"""
        select id, owner_kind, role, visibility, object_key, thumbnail_key
          from public.media_assets
         where storage_provider = 'r2' and deleted_at is null
           and thumbnail_key is null
           and object_key is not null
           and {_ROLE_EXCLUSION}
           and ($1::text is null or owner_kind = $1)
         order by created_at
         limit $2
        """,
        sector,
        limit,
    )
    counts = {"added": 0, "skipped": 0, "failed": 0}
    for row in rows:
        counts[await add_thumbnail_row(conn, provider, row)] += 1
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
