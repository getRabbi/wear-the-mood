"""Legacy Supabase store adapter (INFRA_UPGRADE Phase 1B · COMMIT 2).

Resolves objects still on the original Supabase Storage (media_assets rows with
``storage_provider='legacy'``) so the unified resolver can serve them DURING the
migration (point A — mixed legacy/r2 never breaks a surface). New writes do NOT
come here — they go to R2.

Two legacy shapes exist:
  * legacy_url is a full ``http(s)://`` URL → the object is in a public Supabase
    bucket (wardrobe / post-images) or already a usable URL → serve it as-is.
  * legacy_url is a bare storage PATH (``<uid>/...``) → the object is in a PRIVATE
    Supabase bucket → sign it with the existing service-role signer. The bucket
    isn't stored on the row, so we map it from (owner_kind, role).
"""

from __future__ import annotations

from app.services.storage import create_signed_url

# (owner_kind, role) → private Supabase bucket, for signing not-yet-migrated
# private legacy objects whose legacy_url is a storage path (migrations 0003/
# 0007/0008/0009). Wardrobe/posts/giveaways are public-bucket URLs → not here.
LEGACY_PRIVATE_BUCKET: dict[tuple[str, str], str] = {
    ("profile", "avatar"): "avatars",
    ("profile", "profile_pic"): "profile-pictures",
    ("tryon_photo", "tryon_photo"): "avatars",
    ("tryon_result", "result"): "tryon-results",
}


async def legacy_private_view_url(bucket: str, path: str, ttl: int = 3600) -> str:
    """Mint a short-lived signed URL for a private legacy Supabase object."""
    return await create_signed_url(bucket, path, expires_in=ttl)
