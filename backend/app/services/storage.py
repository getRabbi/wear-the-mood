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


async def upload_tryon_result(
    user_id: str, image: bytes, content_type: str = "image/png"
) -> str:
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
