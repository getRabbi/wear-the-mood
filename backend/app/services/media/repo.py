"""media_assets persistence + batched read-resolution (INFRA_UPGRADE Phase 1B ·
COMMIT 3). Service-role only (the worker / backend write; clients never do).

``insert_asset`` records one object on the ledger. ``resolve_images`` turns a page
of owner rows into viewable URLs in ONE query + a single batched signing pass, so
a list/feed never makes the client fetch URLs one-by-one (§8). It is INERT for
legacy rows (their legacy_url passes through unchanged), so wiring it into a
serving endpoint changes nothing until bytes actually move to R2.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

import asyncpg

from app.services.media import get_storage_provider, resolve_view_url
from app.services.media.base import Visibility
from app.services.media.r2 import R2StorageProvider, public_url_for
from app.services.storage import create_signed_url


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
