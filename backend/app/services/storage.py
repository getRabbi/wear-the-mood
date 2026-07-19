"""Supabase Storage helpers for server-side jobs (CLAUDE.md §8, §11).

Used by the worker to fetch an original wardrobe image and write back its
cutout. Uploads use the service-role key (server-only) so they bypass RLS and
can write into any user's folder; the key never leaves the backend (§11).
"""

from __future__ import annotations

from uuid import uuid4

import httpx

from app.core.config import get_settings

_BUCKET = "wardrobe"
_TIMEOUT = 30.0


async def download_image(url: str) -> bytes:
    """Fetch the bytes at a (public) image URL."""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.content


async def delete_object(bucket: str, path: str) -> None:
    """Delete a single storage object (service-role). Used to remove a user's
    sensitive avatar on account deletion (§10)."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.delete(
            f"{base}/storage/v1/object/{bucket}/{path}",
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
        )
        resp.raise_for_status()


async def upload_cutout(user_id: str, png: bytes) -> str:
    """Upload a PNG cutout under the user's folder and return its public URL."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    path = f"{user_id}/cutout/{uuid4()}.png"
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(
            f"{base}/storage/v1/object/{_BUCKET}/{path}",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": "image/png",
            },
            content=png,
        )
        resp.raise_for_status()
    return f"{base}/storage/v1/object/public/{_BUCKET}/{path}"


_TRYON_RESULTS_BUCKET = "tryon-results"


async def upload_tryon_result(user_id: str, image: bytes, content_type: str = "image/png") -> str:
    """Persist a generated try-on image into the PRIVATE `tryon-results` bucket
    (so the user's history survives FASHN's short retention, §8) and return its
    STORAGE PATH — the app/backend mints a short-lived signed URL to display it."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    ext = "jpg" if "jpeg" in content_type or "jpg" in content_type else "png"
    path = f"{user_id}/result/{uuid4()}.{ext}"
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(
            f"{base}/storage/v1/object/{_TRYON_RESULTS_BUCKET}/{path}",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": content_type,
            },
            content=image,
        )
        resp.raise_for_status()
    return path


async def upload_private_image(
    bucket: str, user_id: str, prefix: str, image: bytes, content_type: str = "image/png"
) -> str:
    """Upload an image into a PRIVATE Supabase bucket under the user's folder and
    return its STORAGE PATH (signed on serve). Generalizes upload_tryon_result for
    AI Studio outputs (enhanced items, catalog shots) in legacy mode."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    ext = "jpg" if "jpeg" in content_type or "jpg" in content_type else "png"
    path = f"{user_id}/{prefix}/{uuid4()}.{ext}"
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(
            f"{base}/storage/v1/object/{bucket}/{path}",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": content_type,
            },
            content=image,
        )
        resp.raise_for_status()
    return path


async def create_signed_url(bucket: str, path: str, expires_in: int = 3600) -> str:
    """Mint a short-lived signed URL for a private object (service-role)."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(
            f"{base}/storage/v1/object/sign/{bucket}/{path}",
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
            json={"expiresIn": expires_in},
        )
        resp.raise_for_status()
        signed = resp.json().get("signedURL") or resp.json().get("signedUrl")
    return f"{base}/storage/v1{signed}"


# ── prefix delete (account erasure, §10 / Phase 4A) ──────────────────────────


async def _list_entries(
    client: httpx.AsyncClient, base: str, key: str, bucket: str, prefix: str
) -> list[dict]:
    """One page of a Supabase Storage folder listing (files + sub-folders)."""
    resp = await client.post(
        f"{base}/storage/v1/object/list/{bucket}",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
        json={
            "prefix": prefix,
            "limit": 1000,
            "offset": 0,
            "sortBy": {"column": "name", "order": "asc"},
        },
    )
    resp.raise_for_status()
    return resp.json()


async def _collect_files(
    client: httpx.AsyncClient,
    base: str,
    key: str,
    bucket: str,
    prefix: str,
    out: list[str],
    depth: int = 0,
) -> None:
    """Recurse a Supabase prefix, appending every FILE's full path to `out`. A
    Supabase 'folder' entry has id == null; a file has a non-null id."""
    if depth > 6:  # guard against pathological nesting
        return
    for entry in await _list_entries(client, base, key, bucket, prefix):
        name = entry.get("name")
        if not name:
            continue
        full = f"{prefix}/{name}" if prefix else name
        if entry.get("id") is None:
            await _collect_files(client, base, key, bucket, full, out, depth + 1)
        else:
            out.append(full)


async def list_prefix(bucket: str, prefix: str) -> list[str]:
    """Recursively list every file path under `prefix` in a Supabase bucket."""
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    out: list[str] = []
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        await _collect_files(client, base, key, bucket, prefix.rstrip("/"), out)
    return out


async def delete_prefix(bucket: str, prefix: str) -> int:
    """Delete EVERY object under `prefix` in a Supabase bucket (account erasure).
    Returns the number deleted (0 if the prefix is empty)."""
    paths = await list_prefix(bucket, prefix)
    if not paths:
        return 0
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    key = settings.supabase_service_role_key
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        for i in range(0, len(paths), 100):  # bulk-delete in chunks
            resp = await client.request(
                "DELETE",
                f"{base}/storage/v1/object/{bucket}",
                headers={"apikey": key, "Authorization": f"Bearer {key}"},
                json={"prefixes": paths[i : i + 100]},
            )
            resp.raise_for_status()
    return len(paths)
