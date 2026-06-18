"""Daily Offers (FEATURES_COMMUNITY_PLUS · Daily Offer).

Serves the active, in-window curated/affiliate offers for the Newsroom strip.
Affiliate attribution is appended at serve time (§18) — no PII is stored or sent.
Deliberately separate from the social feed to protect trust.
"""

from __future__ import annotations

import json
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.offer import Offer

router = APIRouter(tags=["offers"])

# Non-PII attribution so partners can credit the app for the referral (§18).
_ATTRIBUTION = {"utm_source": "fashionos", "utm_medium": "app"}


def _attributed(url: str) -> str:
    """Append attribution params without clobbering the partner's own query."""
    try:
        parts = urlparse(url)
        query = dict(parse_qsl(parts.query))
        query.update(_ATTRIBUTION)
        return urlunparse(parts._replace(query=urlencode(query)))
    except Exception:
        return url


def _jsonb(value: object) -> object:
    return json.loads(value) if isinstance(value, str) else value


@router.get("/offers/today", response_model=list[Offer])
async def offers_today(
    user: CurrentUser = Depends(get_current_user),
) -> list[Offer]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select id, title, brand, image_url, discount_label, affiliate_url, topics
              from public.offers
             where is_active
               and (valid_from is null or valid_from <= now())
               and (valid_to   is null or valid_to   >= now())
             order by created_at desc
            """
        )
    return [
        Offer(
            id=str(r["id"]),
            title=r["title"],
            brand=r["brand"],
            image_url=r["image_url"],
            discount_label=r["discount_label"],
            affiliate_url=_attributed(r["affiliate_url"]),
            topics=[str(t) for t in (_jsonb(r["topics"]) or [])],
        )
        for r in rows
    ]
