"""Account lifecycle — data export + deletion (CLAUDE.md §10).

Both are MANDATORY for store/GDPR compliance. Export returns all of the user's
own rows as JSON. Deletion removes the auth user, which cascades through
`profiles` to every user-owned table (§5); the two service-role tables that hold
a `user_id` but no FK are cleaned explicitly — idempotency keys are dropped and
the AI cost log is anonymized (user_id -> null) so aggregate spend survives
without PII (§10, §14). Everything is scoped to the JWT user_id (§11).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Response

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user

router = APIRouter(tags=["account"])

_PROFILE_QUERY = (
    "select id, username, display_name, avatar_url, body_data, timezone, "
    "onboarding_completed, created_at, updated_at "
    "from public.profiles where id = $1::uuid"
)

# (key, SQL) — each selects the user's own rows ($1 = user_id), excluding the
# internal vector/embedding columns. Order is chronological where it helps.
_EXPORT_QUERIES: list[tuple[str, str]] = [
    (
        "credits",
        "select balance, daily_free_used, daily_reset_on, updated_at "
        "from public.credits where user_id = $1::uuid",
    ),
    (
        "wardrobe_items",
        "select id, title, category, subcategory, color, pattern, brand, image_url, "
        "cutout_url, thumbnail_url, tags, cost, purchase_date, last_worn_at, "
        "wear_count, created_at, updated_at "
        "from public.wardrobe_items where user_id = $1::uuid order by created_at",
    ),
    (
        "outfits",
        "select id, name, item_ids, cover_image_url, created_at, updated_at "
        "from public.outfits where user_id = $1::uuid order by created_at",
    ),
    (
        "tryon_jobs",
        "select id, status, person_image_url, garment_image_url, wardrobe_item_id, "
        "provider, error, created_at, updated_at "
        "from public.tryon_jobs where user_id = $1::uuid order by created_at",
    ),
    (
        "tryon_results",
        "select id, job_id, result_image_url, created_at "
        "from public.tryon_results where user_id = $1::uuid order by created_at",
    ),
    (
        "taste_signals",
        "select id, signal_type, subject_type, subject_id, weight, created_at "
        "from public.taste_signals where user_id = $1::uuid order by created_at",
    ),
    (
        "consents",
        "select id, consent_type, version, granted, created_at "
        "from public.consents where user_id = $1::uuid order by created_at",
    ),
    (
        "posts",
        "select id, caption, image_url, outfit_id, visibility, like_count, "
        "comment_count, created_at, updated_at "
        "from public.posts where user_id = $1::uuid order by created_at",
    ),
    (
        "follows",
        "select followee_id, created_at "
        "from public.follows where follower_id = $1::uuid",
    ),
    (
        "likes",
        "select post_id, created_at from public.likes where user_id = $1::uuid",
    ),
    (
        "comments",
        "select id, post_id, body, created_at "
        "from public.comments where user_id = $1::uuid order by created_at",
    ),
    (
        "reports",
        "select id, subject_type, subject_id, reason, status, created_at "
        "from public.reports where reporter_id = $1::uuid order by created_at",
    ),
]


@router.get("/account/export")
async def export_account(
    user: CurrentUser = Depends(get_current_user),
) -> dict[str, object]:
    async with get_pool().acquire() as conn:
        profile_row = await conn.fetchrow(_PROFILE_QUERY, user.id)
        profile = dict(profile_row) if profile_row else None
        # asyncpg returns jsonb as raw text; decode body_data so it nests cleanly.
        if profile and isinstance(profile.get("body_data"), str):
            try:
                profile["body_data"] = json.loads(profile["body_data"])
            except ValueError:
                pass

        data: dict[str, object] = {
            "exported_at": datetime.now(UTC).isoformat(),
            "user_id": user.id,
            "email": user.email,
            "profile": profile,
        }
        for key, sql in _EXPORT_QUERIES:
            rows = await conn.fetch(sql, user.id)
            data[key] = [dict(r) for r in rows]
    return data


@router.delete("/account", status_code=204)
async def delete_account(
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "delete from public.idempotency_keys where user_id = $1::uuid",
                user.id,
            )
            await conn.execute(
                "update public.ai_usage_log set user_id = null where user_id = $1::uuid",
                user.id,
            )
            # Removing the auth user cascades profiles -> every user-owned table (§5).
            await conn.execute(
                "delete from auth.users where id = $1::uuid",
                user.id,
            )
    return Response(status_code=204)
