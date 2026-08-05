"""Discover shopping catalog schemas (DISCOVER spec §12, §17, §34, §37).

Money crosses the wire as INTEGER MINOR UNITS plus an ISO-4217 code, never a
float and never a pre-formatted string. The client formats it for the user's
locale; the server never guesses what a currency symbol should look like in
someone else's language, and no FX conversion happens anywhere.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

# Typed ranking reasons. The server sends a CODE, not display text, so the app
# can localize it — §37.2 is explicit that a reason is "a typed code, not
# arbitrary display text".
MatchReason = Literal[
    "closet_match",
    "mood_match",
    "style_match",
    "budget_fit",
    "color_match",
    "trending",
    "new_arrival",
    "price_drop",
    "curated",
]

StockStatus = Literal["in_stock", "low_stock", "out_of_stock", "unknown"]
TryOnStatus = Literal["unsupported", "pending", "ready"]

FeedPlacement = Literal[
    "story_rail",
    "feed_grid",
    "complete_look",
    "search",
    "saved",
    "product_details",
]

InteractionType = Literal[
    "impression",
    "open",
    "save",
    "unsave",
    "try_on",
    "add_to_look",
    "shop_click",
    "not_my_style",
    "too_expensive",
    "wrong_size",
    "wrong_category",
    "hide_product",
    "hide_merchant",
    "report_info",
]


class Money(BaseModel):
    """An amount in the smallest unit of ``currency`` (cents, poisha, yen)."""

    amount_minor: int = Field(ge=0)
    currency: str = Field(min_length=3, max_length=3)


class MerchantSummary(BaseModel):
    id: str
    name: str
    logo_url: str | None = None


class ProductVariant(BaseModel):
    id: str
    color: str | None = None
    size: str | None = None
    price: Money | None = None
    original_price: Money | None = None
    stock_status: StockStatus = "unknown"
    available: bool = True


class Product(BaseModel):
    id: str
    merchant: MerchantSummary
    title: str
    brand: str | None = None
    description: str | None = None
    category: str | None = None
    subcategory: str | None = None

    price: Money
    original_price: Money | None = None

    image_urls: list[str] = Field(default_factory=list)
    # 0..1 in each axis; where a portrait crop should centre (§6.2).
    image_focal_x: float = 0.5
    image_focal_y: float = 0.5

    colors: list[str] = Field(default_factory=list)
    sizes: list[str] = Field(default_factory=list)
    variants: list[ProductVariant] = Field(default_factory=list)

    stock_status: StockStatus = "unknown"
    try_on_status: TryOnStatus = "unsupported"
    # Exactly ONE reason per card (§8.1, anti-clutter rule 7).
    match_reason: MatchReason | None = None
    saved: bool = False
    sponsored: bool = False

    # Opaque analytics correlation id. Never a URL, never anything private.
    tracking_token: str | None = None
    # When price and stock were last confirmed, so the client can say so on a
    # source that goes stale (§12.15, §35).
    last_synced_at: str | None = None


class ProductPage(BaseModel):
    """One page of the catalog. Cursor-based so pages cannot drift (§23, §37.2)."""

    # Bumped when the shape changes incompatibly; older clients read what they
    # understand and ignore the rest (§37.4).
    schema_version: int = 1
    server_time: str
    items: list[Product] = Field(default_factory=list)
    next_cursor: str | None = None
    cache_ttl_seconds: int = 300

    # The region the server actually RESOLVED for this request, which is not
    # necessarily what the client asked for — saved preferences win. Echoed so
    # the app can key its offline cache on the real region and drop a cached
    # page when the account's country or currency changes elsewhere (§34).
    country: str | None = None
    currency: str | None = None
    # Monotonic stamp of the user's shopping preferences. Any preference change
    # moves it, which invalidates a cached page that was ranked under the old
    # profile. 0 when the user has no preferences row.
    profile_version: int = 0
    # True when the region has no catalog at all, so the app shows the
    # broader-content state rather than pretending the filter was too narrow
    # (§24 "no products in region").
    region_empty: bool = False


class FacetValue(BaseModel):
    """One selectable filter option (§11.2).

    [value] is the CANONICAL value the API filters on and never changes with
    language; [label] is display text the client may override with its own
    localization. Keeping them apart is what lets an app translate "Dresses"
    without breaking the query that uses `dresses`.
    """

    value: str
    label: str
    count: int = 0


class CatalogFacets(BaseModel):
    """Filter vocabularies derived from the CURRENTLY SERVABLE catalog.

    Country-aware: a size or colour that exists only on products which cannot
    ship to this user is not offered, because a filter that always returns
    nothing is worse than no filter.
    """

    categories: list[FacetValue] = Field(default_factory=list)
    sizes: list[FacetValue] = Field(default_factory=list)
    colors: list[FacetValue] = Field(default_factory=list)
    merchants: list[FacetValue] = Field(default_factory=list)

    # Bounds in minor units, with the currency they are expressed in. Null when
    # the region has no catalog — an empty facet set is a valid answer, not an
    # error (§24).
    min_price: Money | None = None
    max_price: Money | None = None

    try_on_available: bool = False
    discount_available: bool = False

    @property
    def is_empty(self) -> bool:
        return not (self.categories or self.sizes or self.colors or self.merchants)


class SaveProductRequest(BaseModel):
    price_alert_enabled: bool = True
    availability_alert_enabled: bool = False


class SavedProduct(BaseModel):
    product: Product
    saved_at: str
    price_alert_enabled: bool
    availability_alert_enabled: bool
    # Set when the current price is below what it was when saved. Derived from
    # the stored price, never from anything the client sends (§38).
    price_dropped: bool = False


class InteractionRequest(BaseModel):
    product_id: str | None = None
    merchant_id: str | None = None
    event_type: InteractionType
    feed_placement: FeedPlacement | None = None
    story_id: str | None = None
    tracking_token: str | None = None
    # Stable across retries of the same user action; makes the write idempotent.
    client_event_id: str | None = Field(default=None, max_length=64)


class ShoppingPreferences(BaseModel):
    country: str | None = Field(default=None, min_length=2, max_length=2)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    budget_min: Money | None = None
    budget_max: Money | None = None
    sizes: list[str] = Field(default_factory=list)
    favorite_categories: list[str] = Field(default_factory=list)
    avoided_colors: list[str] = Field(default_factory=list)
    modest_preference: bool = False
    personalization_enabled: bool = True
