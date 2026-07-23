"""media_assets persistence + batched read-resolution (INFRA_UPGRADE Phase 1B ·
COMMIT 3). Service-role only (the worker / backend write; clients never do).

``insert_asset`` records one object on the ledger. ``resolve_images`` turns a page
of owner rows into viewable URLs in ONE query + a single batched signing pass, so
a list/feed never makes the client fetch URLs one-by-one (§8). It is INERT for
legacy rows (their legacy_url passes through unchanged), so wiring it into a
serving endpoint changes nothing until bytes actually move to R2.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

import asyncpg

from app.services.media import get_storage_provider, resolve_view_url
from app.services.media.base import StoredObject, Visibility
from app.services.media.r2 import R2StorageProvider, public_url_for
from app.services.storage import create_signed_url

log = logging.getLogger("fashionos.media.repo")

# Mark the cutout READY + point the column at the new object, mirroring
# app.workers.bg_worker._DONE_CUTOUT_UPDATE (kept here to avoid a worker→repo import
# cycle; the two statements must stay in sync). thumbnail_url is legacy — the read
# endpoint overlays media_assets.thumbnail_key for r2 items.
_CUTOUT_DONE_UPDATE = """
    update public.wardrobe_items
       set cutout_status = 'done',
           cutout_url = $2,
           thumbnail_url = coalesce(thumbnail_url, $2)
     where id = $1::uuid
"""


@dataclass(frozen=True)
class ResolvedImage:
    """A resolved object: the full-size viewable URL + its thumbnail URL (if any)."""

    url: str | None
    thumb_url: str | None = None


async def insert_asset(
    conn: asyncpg.Connection,
    *,
    owner_kind: str,
    owner_id: object,
    role: str,
    user_id: object | None,
    visibility: Visibility,
    storage_provider: str,
    object_key: str | None = None,
    thumbnail_key: str | None = None,
    public_url: str | None = None,
    legacy_url: str | None = None,
    content_hash: str | None = None,
    mime_type: str | None = None,
) -> str:
    """Record one image on the ledger; ``migrated_at`` is stamped for r2 writes."""
    return await conn.fetchval(
        """
        insert into public.media_assets
          (owner_kind, owner_id, role, user_id, visibility, storage_provider,
           object_key, thumbnail_key, public_url, legacy_url, content_hash,
           mime_type, migrated_at)
        values ($1, $2::uuid, $3, $4::uuid, $5, $6, $7, $8, $9, $10, $11, $12,
                case when $6 = 'r2' then now() else null end)
        returning id
        """,
        owner_kind,
        str(owner_id),
        role,
        str(user_id) if user_id is not None else None,
        visibility,
        storage_provider,
        object_key,
        thumbnail_key,
        public_url,
        legacy_url,
        content_hash,
        mime_type,
    )


async def _safe_delete_object(
    object_key: str | None, thumbnail_key: str | None, *, visibility: Visibility
) -> None:
    """Best-effort delete of an R2 object (+ thumbnail). Never raises — an orphaned
    object can be swept later and must never fail a completed replacement."""
    if not object_key:
        return
    provider = get_storage_provider()
    if not isinstance(provider, R2StorageProvider):
        return
    try:
        await provider.delete(
            object_key=object_key, visibility=visibility, thumbnail_key=thumbnail_key
        )
    except Exception as exc:  # noqa: BLE001 - cleanup is best-effort (§9)
        log.warning("orphan cleanup failed for object %s: %s", object_key, exc)


async def _replace_role_asset(
    conn: asyncpg.Connection,
    *,
    owner_id: object,
    role: str,
    user_id: object | None,
    obj: StoredObject,
    visibility: Visibility,
) -> list[tuple[str | None, str | None]]:
    """Point the SINGLE active (wardrobe_item, role) ledger row at ``obj`` — update
    the existing active row in place, or insert if none exists — collapsing any
    accidental duplicates to exactly one active row. MUST run inside a transaction
    with the rows already locked. Returns the (object_key, thumbnail_key) of every
    row it displaced, for post-commit cleanup (§9). Never deletes objects itself."""
    rows = await conn.fetch(
        "select id, object_key, thumbnail_key from public.media_assets "
        "where owner_kind = 'wardrobe_item' and owner_id = $1::uuid and role = $2 "
        "and deleted_at is null order by created_at for update",
        str(owner_id),
        role,
    )
    displaced = [(r["object_key"], r["thumbnail_key"]) for r in rows]
    if rows:
        await conn.execute(
            "update public.media_assets set object_key = $2, thumbnail_key = $3, "
            "content_hash = $4, storage_provider = 'r2', visibility = $5, "
            "mime_type = 'image/png', public_url = null, legacy_url = null, "
            "migrated_at = now() where id = $1",
            rows[0]["id"],
            obj.object_key,
            obj.thumbnail_key,
            obj.content_hash,
            visibility,
        )
        if len(rows) > 1:  # collapse any legacy duplicates so one active row remains
            await conn.execute(
                "update public.media_assets set deleted_at = now() where id = any($1::uuid[])",
                [r["id"] for r in rows[1:]],
            )
    else:
        await insert_asset(
            conn,
            owner_kind="wardrobe_item",
            owner_id=owner_id,
            role=role,
            user_id=user_id,
            visibility=visibility,
            storage_provider="r2",
            object_key=obj.object_key,
            thumbnail_key=obj.thumbnail_key,
            content_hash=obj.content_hash,
            mime_type="image/png",
        )
    return displaced


async def replace_cutout_assets(
    conn: asyncpg.Connection,
    *,
    item_id: object,
    user_id: object | None,
    cutout: StoredObject,
    mask: StoredObject | None,
) -> None:
    """Atomically install a freshly-uploaded cutout (+ optional editable mask) as
    the active assets of a wardrobe item and mark it done (§ BG upgrade §9). The
    new objects MUST already be uploaded. Order of operations:

      1. lock the item + its active cutout/cutout_mask rows,
      2. update-or-insert those rows to the new objects, mark the item done,
      3. commit,
      4. only THEN best-effort delete the displaced old objects.

    On any DB failure the new objects are best-effort deleted and the error
    re-raised, so a caller can mark the item failed. Old objects are never removed
    before commit, and no ambiguous duplicate active rows survive success.
    """
    try:
        async with conn.transaction():
            await conn.execute(
                "select id from public.wardrobe_items where id = $1::uuid for update",
                str(item_id),
            )
            displaced = await _replace_role_asset(
                conn,
                owner_id=item_id,
                role="cutout",
                user_id=user_id,
                obj=cutout,
                visibility="private",
            )
            if mask is not None:
                displaced += await _replace_role_asset(
                    conn,
                    owner_id=item_id,
                    role="cutout_mask",
                    user_id=user_id,
                    obj=mask,
                    visibility="private",
                )
            await conn.execute(_CUTOUT_DONE_UPDATE, str(item_id), cutout.object_key)
    except Exception:
        # DB replacement failed AFTER the uploads — delete what we just wrote so a
        # retry doesn't leak objects. Never touch the OLD objects (still referenced).
        await _safe_delete_object(cutout.object_key, cutout.thumbnail_key, visibility="private")
        if mask is not None:
            await _safe_delete_object(mask.object_key, mask.thumbnail_key, visibility="private")
        raise
    # Committed — the old objects are now unreferenced; best-effort remove them.
    for object_key, thumbnail_key in displaced:
        await _safe_delete_object(object_key, thumbnail_key, visibility="private")


async def resolve_image_list(
    conn: asyncpg.Connection,
    owner_kind: str,
    owner_id: object,
    role: str,
    urls: list[str],
) -> list[ResolvedImage]:
    """Resolve an ORDERED list of image urls (e.g. a giveaway's images array)
    against media_assets, matched by legacy_url. R2 public → CDN url + thumbnail;
    a legacy / un-migrated / brand-new url passes through (no thumbnail)."""
    if not urls:
        return []
    rows = await conn.fetch(
        """
        select storage_provider, visibility, object_key, thumbnail_key,
               public_url, legacy_url
          from public.media_assets
         where owner_kind = $1 and owner_id = $2::uuid and role = $3
           and deleted_at is null
        """,
        owner_kind,
        str(owner_id),
        role,
    )
    by_legacy = {r["legacy_url"]: r for r in rows if r["legacy_url"]}
    provider = get_storage_provider()
    base_url = getattr(provider, "_base_url", "")

    out: list[ResolvedImage] = []
    for url in urls:
        r = by_legacy.get(url)
        if r is None or r["storage_provider"] != "r2":
            out.append(ResolvedImage(url=url, thumb_url=None))  # passthrough
            continue
        if r["visibility"] == "public":
            full = r["public_url"] or public_url_for(base_url, r["object_key"] or "")
            thumb = public_url_for(base_url, r["thumbnail_key"]) if r["thumbnail_key"] else None
        else:  # defensive — giveaway images are public
            full = await resolve_view_url(
                storage_provider="r2",
                visibility="private",
                owner_kind=owner_kind,
                role=role,
                object_key=r["object_key"],
            )
            thumb = None
        out.append(ResolvedImage(url=full or url, thumb_url=thumb))
    return out


async def resolve_private_path(
    conn: asyncpg.Connection, path: str | None, supabase_bucket: str
) -> str | None:
    """Sign a single private selfie path/key for DISPLAY (avatar, profile-pic,
    try-on photo) — these store a bare path, not a URL, and the app can no longer
    self-sign once bytes live in R2 (no client keys, §11).

    R2 object (recorded in media_assets by object_key) → R2 signed url; a legacy
    Supabase path → Supabase signed url; an already-absolute http url is returned
    unchanged. None → None.
    """
    if not path:
        return None
    if path.startswith("http"):
        return path
    is_r2 = await conn.fetchval(
        "select 1 from public.media_assets "
        "where object_key = $1 and storage_provider = 'r2' and deleted_at is null limit 1",
        path,
    )
    if is_r2:
        provider = get_storage_provider()
        if isinstance(provider, R2StorageProvider):
            return await provider.view_url(object_key=path, visibility="private")
    try:
        return await create_signed_url(supabase_bucket, path)
    except Exception:  # never let a transient signing error 500 the screen
        return None


async def resolve_images(
    conn: asyncpg.Connection,
    owner_kind: str,
    owner_ids: Sequence[object],
    roles: Iterable[str],
) -> dict[tuple[str, str], ResolvedImage]:
    """Map ``(owner_id, role) -> ResolvedImage`` for the given owner rows. r2
    objects resolve to public CDN URLs / batch-signed private URLs; legacy objects
    pass through (public http) or sign via the existing Supabase signer."""
    ids = [str(o) for o in owner_ids]
    if not ids:
        return {}
    rows = await conn.fetch(
        """
        select owner_id, role, storage_provider, visibility,
               object_key, thumbnail_key, public_url, legacy_url
          from public.media_assets
         where owner_kind = $1
           and role = any($2::text[])
           and owner_id = any($3::uuid[])
           and deleted_at is null
        """,
        owner_kind,
        list(roles),
        ids,
    )

    # Batch-sign every r2 PRIVATE key (object + thumbnail) in one client pass.
    provider = get_storage_provider()
    private_keys: list[str] = []
    for r in rows:
        if r["storage_provider"] == "r2" and r["visibility"] == "private":
            for k in (r["object_key"], r["thumbnail_key"]):
                if k:
                    private_keys.append(k)
    signed: dict[str, str] = {}
    if private_keys and isinstance(provider, R2StorageProvider):
        signed = await provider.presign_get_many(private_keys)
    base_url = getattr(provider, "_base_url", "")

    out: dict[tuple[str, str], ResolvedImage] = {}
    for r in rows:
        sp, vis = r["storage_provider"], r["visibility"]
        if sp == "r2":
            if vis == "public":
                url = r["public_url"] or public_url_for(base_url, r["object_key"] or "")
                thumb = public_url_for(base_url, r["thumbnail_key"]) if r["thumbnail_key"] else None
            else:
                url = signed.get(r["object_key"]) if r["object_key"] else None
                thumb = signed.get(r["thumbnail_key"]) if r["thumbnail_key"] else None
        else:  # legacy — passthrough (public/http) or signed Supabase path
            url = await resolve_view_url(
                storage_provider="legacy",
                visibility=vis,
                owner_kind=owner_kind,
                role=r["role"],
                legacy_url=r["legacy_url"],
            )
            thumb = None
        out[(str(r["owner_id"]), r["role"])] = ResolvedImage(url=url, thumb_url=thumb)
    return out
