"""Daily Guide (FEATURES_COMMUNITY_PLUS · Daily Guide).

Serves the day's editorial styling guide for the Home "Today" section — the
latest curated guide dated on or before today. The intro line could be
personalised per user via app.services.llm (the provider wrapper + ai_usage_log
cost logging are already used by the stylist), but the curated copy stands alone
and stays fast/offline, which matters while the Anthropic account has no credits.
"""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.guide import DailyGuide, GuideCta

router = APIRouter(tags=["guide"])


def _jsonb(value: object) -> object:
    return json.loads(value) if isinstance(value, str) else value


@router.get("/guide/today", response_model=DailyGuide)
async def guide_today(
    user: CurrentUser = Depends(get_current_user),
) -> DailyGuide:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            select id, date, title, summary, body, image_url, topics, cta, created_at
              from public.daily_guides
             where date <= current_date
             order by date desc, created_at desc
             limit 1
            """
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "No guide available.", 404)
    return DailyGuide(
        id=str(row["id"]),
        date=row["date"],
        title=row["title"],
        summary=row["summary"],
        body=row["body"],
        image_url=row["image_url"],
        topics=[str(t) for t in (_jsonb(row["topics"]) or [])],
        cta=[GuideCta(**c) for c in (_jsonb(row["cta"]) or [])],
        created_at=row["created_at"],
    )
