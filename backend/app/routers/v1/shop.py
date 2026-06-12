"""Shop-the-look — affiliate deep links (CLAUDE.md §18, §24).

Returns an attributed shoppable link for a query (a trend, a wardrobe piece, an
outfit). The affiliate program/tag stays backend-only and remote-swappable (§11);
the app opens the link and logs affiliate_link_clicked (§15). Auth required.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.supabase_auth import CurrentUser, get_current_user
from app.services.shop import ShopLink, get_shop_builder

router = APIRouter(tags=["shop"])


@router.get("/shop/link", response_model=ShopLink)
async def shop_link(
    q: str = Query(min_length=1, max_length=200),
    label: str = Query("Shop this look", max_length=80),
    user: CurrentUser = Depends(get_current_user),
) -> ShopLink:
    """Build a shoppable (affiliate when configured) search link for `q`."""
    return get_shop_builder().build(q.strip(), label=label)
