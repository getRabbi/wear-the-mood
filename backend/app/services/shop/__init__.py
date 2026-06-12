"""Shop-the-look (CLAUDE.md §18). Resolve the affiliate link builder from config;
default to a neutral web search until the founder configures an affiliate program."""

from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings
from app.services.shop.base import ShopLink, ShopLinkBuilder

__all__ = ["ShopLink", "ShopLinkBuilder", "get_shop_builder"]


@lru_cache
def get_shop_builder() -> ShopLinkBuilder:
    """Affiliate retailer search when AFFILIATE_SEARCH_URL is configured; a plain
    web search (unattributed) otherwise so the feature works pre-partnership."""
    s = get_settings()
    if s.affiliate_search_url:
        return ShopLinkBuilder(
            name=s.affiliate_provider or "affiliate",
            search_url=s.affiliate_search_url,
            query_param=s.affiliate_query_param,
            tag_param=s.affiliate_tag_param,
            tag=s.affiliate_tag,
        )
    return ShopLinkBuilder(name="stub", search_url="https://www.google.com/search")
