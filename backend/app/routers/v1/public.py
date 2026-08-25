"""Unauthenticated PUBLIC READS — the backend half of iOS Guest Mode.

App Review guideline 5.1.1(v) says an app may not require an account to see
content that does not need one. Before this file, every route in `/v1` sat
behind `Depends(get_current_user)`, so a signed-out client could read nothing at
all — not even the feature flags that decide whether Discover exists. That was
the real cause of the rejection: not a missing button, a missing public surface.

What this file is, and is not:

* It is **additive**. Not one existing route is touched, relaxed, or given an
  optional-auth dependency. The authenticated endpoints keep their exact
  contracts, their per-user data and their ownership checks. If this whole
  module were deleted, the signed-in app would behave identically.
* It is **read-only**. There is no POST that writes a row. The single POST here
  resolves a merchant destination and stores nothing.
* It serves **only what WTM already publishes to everybody**: the catalog it
  syndicates, the news it curates, the giveaways people list for the public,
  and the flags that decide which of those are switched on.

Three rules the routes below do not break:

1. **No per-user field is ever computed.** No `saved`, no personalization, no
   ownership, no interaction history, no preferences, no closet. Where the
   authenticated mirror reads `saved_products`, `shopping_preferences`,
   `product_interactions` or `wardrobe_items`, the public one simply does not.
2. **No identity leaves.** The giveaway routes redact owner id and owner name,
   which the authenticated route does return. Unauthenticated is a wider
   audience than signed-in, so the public view is deliberately NARROWER than
   the private one, never merely equal to it.
3. **No affiliate URL is ever pre-disclosed.** Same as the private route: the
   destination is built server-side, validated against the merchant domain
   allow-list, and returned once, on an explicit tap.

Rate limits are bucketed by IP (there is no user to bucket by) and are tighter
than the authenticated equivalents, because an anonymous caller is the one worth
scraping the catalog with.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Body, Query, Request

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.rate_limit import client_ip, enforce_rate_limit
from app.models.common import ErrorCode
from app.models.discover import (
    AffiliateClickRequest,
    AffiliateClickResponse,
    CatalogFacets,
    MerchantSummary,
    Product,
    ProductDetail,
    ProductPage,
)
from app.models.flags import FlagsResponse
from app.models.giveaway import GiveawayResponse
from app.models.news import NewsItemResponse
from app.routers.v1 import discover as private_discover
from app.routers.v1 import giveaways as private_giveaways
from app.routers.v1 import news as private_news
from app.services.discover.affiliate import (
    AffiliateError,
    MerchantRedirect,
    resolve_destination,
)
from app.services.discover.catalog import (
    CatalogFilters,
    Cursor,
    InvalidCursor,
    build_where,
    clamp_limit,
    normalize_country,
    normalize_currency,
)

log = logging.getLogger("fashionos.public")

router = APIRouter(tags=["public"])

# Reused from the authenticated module rather than copied. A second copy of the
# product SELECT is a second thing to keep in step, and the day they drift is
# the day the guest catalog starts answering a different shape from the
# signed-in one.
_PRODUCT_COLUMNS = private_discover._PRODUCT_COLUMNS
_product = private_discover._product
_variants = private_discover._variants
_uuid_or_404 = private_discover._uuid_or_404
_require_shopping = private_discover._require_shopping


async def _limit(request: Request, conn: asyncpg.Connection, name: str, per_hour: int) -> None:
    """Per-IP fixed window. Fails open on a limiter error, like every other
    caller of `enforce_rate_limit` — a broken counter must not take a public
    endpoint down."""
    await enforce_rate_limit(
        conn,
        bucket=f"pub:{name}:{client_ip(request)}",
        limit=per_hour,
        window_seconds=3600,
    )


# ── flags ────────────────────────────────────────────────────────────────────


@router.get("/public/flags", response_model=FlagsResponse)
async def public_flags(request: Request) -> FlagsResponse:
    """The same global flag map the authenticated route returns.

    Flags are service configuration, identical for every caller, and carry no
    user data — the private route's own docstring says per-user targeting would
    be a later, separate change. A guest needs them because without them every
    flag reads OFF on the client, Discover never appears, and the guest
    experience is an empty shell.
    """
    async with get_pool().acquire() as conn:
        await _limit(request, conn, "flags", 240)
        rows = await conn.fetch("select key, enabled from public.feature_flags")
    return FlagsResponse(flags={r["key"]: r["enabled"] for r in rows})


# ── catalog ──────────────────────────────────────────────────────────────────


@router.get("/public/discover/products", response_model=ProductPage)
async def public_list_products(
    request: Request,
    cursor: str | None = Query(default=None, max_length=512),
    limit: int | None = Query(default=None, ge=1, le=50),
    country: str | None = Query(default=None, max_length=2),
    currency: str | None = Query(default=None, max_length=3),
    category: str | None = Query(default=None, max_length=64),
    subcategory: str | None = Query(default=None, max_length=64),
    audience: str | None = Query(default=None, max_length=32),
    color: list[str] | None = Query(default=None),
    size: list[str] | None = Query(default=None),
    brand: list[str] | None = Query(default=None),
    min_price: int | None = Query(default=None, ge=0),
    max_price: int | None = Query(default=None, ge=0),
    try_on_ready: bool = Query(default=False),
    discounted: bool = Query(default=False),
    q: str | None = Query(default=None, max_length=120),
) -> ProductPage:
    """One page of the catalog, UNPERSONALIZED.

    Same servability, region and ordering rules as the signed-in feed — it
    builds its WHERE clause with the same `build_where` — so a guest and a
    member browsing the same country see the same products in the same order.

    What is deliberately absent: no `shopping_preferences` lookup (so the
    country comes from the query alone), no `saved_products` join (`saved` is
    always false), no closet read, and no `match_reason` — every one of those
    describes a person, and there is no person here. `profile_version` is 0 for
    the same reason, which also keeps the client's offline cache from ever
    confusing a guest page with a member's.
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        # Browsing is generous; search is the expensive path and the one worth
        # scraping with, so it is limited separately and harder.
        await _limit(request, conn, "shop", 600)
        if (q or "").strip():
            await _limit(request, conn, "shopsearch", 120)

        resolved_country = normalize_country(country)
        resolved_currency = normalize_currency(currency)

        filters = CatalogFilters(
            country=resolved_country,
            currency=resolved_currency,
            category=category,
            subcategory=subcategory,
            audience=audience,
            colors=[c for c in (color or []) if c],
            sizes=[s for s in (size or []) if s],
            brands=[b for b in (brand or []) if b],
            min_price_minor=min_price,
            max_price_minor=max_price,
            try_on_ready=try_on_ready,
            discounted=discounted,
            search=(q or "").strip() or None,
        )

        try:
            position = Cursor.decode(cursor) if cursor else None
        except InvalidCursor as exc:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "Invalid cursor.", 400) from exc

        # No hidden-merchant list: hiding a merchant is a per-user preference.
        where, params = build_where(filters, position, hidden_merchant_ids=[])
        take = clamp_limit(limit)

        rows = await conn.fetch(
            f"""
            select {_PRODUCT_COLUMNS}
              from public.products p
              join public.merchants m on m.id = p.merchant_id
             where {where}
             order by p.created_at desc, p.id desc
             limit {take + 1}
            """,
            *params,
        )

        has_more = len(rows) > take
        page_rows = rows[:take]
        ids = [str(r["id"]) for r in page_rows]
        variants = await _variants(conn, ids)

        region_empty = False
        if not page_rows and position is None and resolved_country:
            region_empty = (
                await conn.fetchval(
                    """
                    select not exists (
                      select 1 from public.products p
                        join public.merchants m on m.id = p.merchant_id
                       where public.product_is_servable(p) and m.approved
                         and public.product_ships_to(p.country_eligibility,
                               p.country_availability, m.shipping_countries, $1)
                    )
                    """,
                    resolved_country,
                )
                or False
            )

        items = []
        for r in page_rows:
            product = _product(r, saved=False)
            items.append(product.model_copy(update={"variants": variants.get(product.id, [])}))

        last = page_rows[-1] if page_rows else None
        return ProductPage(
            server_time=datetime.now(UTC).isoformat(),
            items=items,
            next_cursor=(
                Cursor(created_at=last["created_at"], product_id=str(last["id"])).encode()
                if has_more and last is not None
                else None
            ),
            region_empty=region_empty,
            country=resolved_country,
            currency=resolved_currency,
            profile_version=0,
        )


@router.get("/public/discover/facets", response_model=CatalogFacets)
async def public_facets(
    request: Request,
    country: str | None = Query(default=None, max_length=2),
) -> CatalogFacets:
    """Filter vocabularies for the servable catalog.

    Delegates to the private implementation's own query by calling it with no
    user context available — see the note there: facets are derived from the
    catalog, never from the caller, so there is nothing per-user to strip.
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await _limit(request, conn, "facets", 240)
        return await private_discover.build_public_facets(conn, country)


@router.get("/public/discover/products/{product_id}", response_model=ProductDetail)
async def public_product_detail(request: Request, product_id: str) -> ProductDetail:
    """One product, revalidated at open — the same freshness contract as the
    signed-in route, minus the two per-user booleans.

    `saved` is false and `try_on_completed` is false, because both are questions
    about a person and there is no person. They are reported as false rather
    than omitted so the response shape is identical and the client needs no
    special case.
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await _limit(request, conn, "product", 600)
        row = await conn.fetchrow(
            f"""
            select {_PRODUCT_COLUMNS},
                   public.product_is_servable(p) as servable,
                   m.approved as merchant_approved,
                   p.country_availability, p.country_eligibility, m.shipping_countries,
                   p.last_synced_at < now() - public.product_staleness_limit() as stale,
                   (p.affiliate_ref is not null and length(btrim(p.affiliate_ref)) > 0)
                     as has_affiliate_ref,
                   (m.allowed_domains <> '{{}}') as has_allowed_domains,
                   coalesce(c.status, 'missing') as affiliate_status
              from public.products p
              join public.merchants m on m.id = p.merchant_id
              left join public.merchant_affiliate_config c on c.merchant_id = m.id
             where p.id = $1::uuid
            """,
            _uuid_or_404(product_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Product not found.", 404)

        variants = await _variants(conn, [product_id])
        product = _product(row, saved=False).model_copy(
            update={"variants": variants.get(product_id, [])}
        )

        servable = bool(row["servable"]) and bool(row["merchant_approved"])
        available = list(row["country_availability"] or [])
        shipping = list(row["shipping_countries"] or [])
        if row["country_eligibility"] == "unknown":
            delivery = sorted(set(shipping))
        elif available and shipping:
            delivery = sorted(set(available) & set(shipping))
        else:
            delivery = sorted(set(available or shipping))

        return ProductDetail(
            product=product,
            servable=servable,
            stale=bool(row["stale"]),
            delivery_countries=delivery,
            shoppable=(
                servable
                and bool(row["has_affiliate_ref"])
                and bool(row["has_allowed_domains"])
                and row["affiliate_status"] == "ok"
            ),
            try_on_completed=False,
            server_time=datetime.now(UTC).isoformat(),
        )


@router.get("/public/discover/products/{product_id}/similar", response_model=list[Product])
async def public_similar_products(
    request: Request,
    product_id: str,
    limit: int = Query(default=8, ge=1, le=20),
) -> list[Product]:
    """Alternatives to this product — same category, then same merchant, newest
    first. Identical rules to the signed-in route, without the caller's country
    preference or hidden-merchant list."""
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await _limit(request, conn, "similar", 600)
        anchor = await conn.fetchrow(
            "select category, merchant_id from public.products where id = $1::uuid",
            _uuid_or_404(product_id),
        )
        if anchor is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Product not found.", 404)

        where, params = build_where(
            CatalogFilters(category=anchor["category"]),
            None,
            hidden_merchant_ids=[],
        )
        params.append(product_id)
        exclude = f"${len(params)}::uuid"
        params.append(str(anchor["merchant_id"]))
        same_merchant = f"${len(params)}::uuid"

        rows = await conn.fetch(
            f"""
            select {_PRODUCT_COLUMNS}
              from public.products p
              join public.merchants m on m.id = p.merchant_id
             where {where} and p.id <> {exclude}
             order by (p.merchant_id = {same_merchant}) desc, p.created_at desc, p.id desc
             limit {clamp_limit(limit)}
            """,
            *params,
        )
        return [_product(r, saved=False) for r in rows]


@router.post(
    "/public/discover/products/{product_id}/click",
    response_model=AffiliateClickResponse,
)
async def public_affiliate_destination(
    request: Request,
    product_id: str,
    body: AffiliateClickRequest = Body(default_factory=AffiliateClickRequest),
) -> AffiliateClickResponse:
    """Resolve the ONE merchant destination this product may open.

    A POST, matching the shape shipped clients already speak, but it is a read:
    **nothing is recorded**. The private route inserts an `affiliate_clicks` row
    keyed to a user and dedupes it with an idempotency key; neither is possible
    or wanted here, and an anonymous row in a table the commission funnel is
    judged on would be worse than no row at all.

    Everything that makes the private route safe is kept: the URL is built from
    server-side configuration, validated against the merchant's domain
    allow-list before it is returned, and a rejection is logged as a reason code
    with no candidate URL and no affiliate tag in the line.
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        # Tighter than the rest: this is the endpoint that produces outbound
        # commercial links, and the only one where volume costs a merchant
        # relationship rather than just bandwidth.
        await _limit(request, conn, "shopclick", 120)

        row = await conn.fetchrow(
            """
            select p.id, p.affiliate_ref, p.merchant_id,
                   public.product_is_servable(p) as servable,
                   m.name as merchant_name, m.logo_url as merchant_logo,
                   m.approved as merchant_approved, m.allowed_domains,
                   c.url_template, c.affiliate_tag, c.tag_param,
                   coalesce(c.status, 'missing') as affiliate_status
              from public.products p
              join public.merchants m on m.id = p.merchant_id
              left join public.merchant_affiliate_config c on c.merchant_id = m.id
             where p.id = $1::uuid
            """,
            _uuid_or_404(product_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Product not found.", 404)
        if not row["servable"] or not row["merchant_approved"]:
            raise ApiError(ErrorCode.NOT_FOUND, "This product is no longer available.", 404)

        try:
            url, _host = resolve_destination(
                row["affiliate_ref"],
                MerchantRedirect(
                    allowed_domains=tuple(row["allowed_domains"] or ()),
                    url_template=row["url_template"],
                    affiliate_tag=row["affiliate_tag"],
                    tag_param=row["tag_param"] or "tag",
                    status=row["affiliate_status"],
                ),
            )
        except AffiliateError as exc:
            log.warning(
                "public affiliate redirect rejected: merchant=%s reason=%s",
                row["merchant_id"],
                exc.reason,
            )
            raise ApiError(
                ErrorCode.PROVIDER_ERROR,
                "We couldn't open this store right now.",
                502,
            ) from exc

        return public_click_response(row, url)


def public_click_response(row: object, url: str) -> AffiliateClickResponse:
    """The public destination response, in the SAME shape the private route
    returns — because the shipped client parses one model for both.

    `click_id` is deliberately an empty string. The private route returns the id
    of the `affiliate_clicks` row it just wrote; there is no such row here and
    inventing an id would be a receipt for something that never happened. The
    client reads `url`, `merchant` and `try_on_completed` and never looks at it.

    `try_on_completed` is false for the same reason it is on the product detail:
    it is a question about a person, and there is no person.

    Pulled out of the handler so it can be unit-tested against the real Pydantic
    model without a database. It was not, and the first version passed field
    names (`merchant_name`, `merchant_host`) that do not exist on
    [AffiliateClickResponse] — which validated as a 500 on the first real
    production call and nowhere earlier.
    """
    return AffiliateClickResponse(
        click_id="",
        url=url,
        merchant=MerchantSummary(
            id=str(row["merchant_id"]),
            name=row["merchant_name"],
            logo_url=row["merchant_logo"],
        ),
        try_on_completed=False,
    )


# ── newsroom ─────────────────────────────────────────────────────────────────


@router.get("/public/news", response_model=list[NewsItemResponse])
async def public_news(
    request: Request,
    limit: int = Query(20, ge=1, le=50),
    before: datetime | None = Query(None),
    with_image: bool = Query(False),
) -> list[NewsItemResponse]:
    """Newest-first fashion news.

    The private route already computes nothing per user — its own docstring
    says so — so this is the same query with the same lifecycle gate, and a
    guest sees exactly the newsroom a member sees.
    """
    async with get_pool().acquire() as conn:
        await _limit(request, conn, "news", 300)
        return await private_news.list_news_rows(
            conn, limit=limit, before=before, with_image=with_image
        )


@router.get("/public/news/{news_id}", response_model=NewsItemResponse)
async def public_news_item(request: Request, news_id: UUID) -> NewsItemResponse:
    """ONE story by id, so the article reader and shared links stand alone."""
    async with get_pool().acquire() as conn:
        await _limit(request, conn, "news", 300)
        row = await private_news.news_row(conn, str(news_id))
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "News item not found.", 404)
        return private_news._to_news_response(row)


# ── giveaways (public information only) ──────────────────────────────────────


def _public_giveaway(row: asyncpg.Record, images: list[str], thumbs: list[str]) -> GiveawayResponse:
    """The public view of a listing: what it is, not who is giving it away.

    Owner id and owner name are REDACTED. The signed-in route returns both, and
    that is fine inside an account boundary — but a display name attached to a
    coarse area, readable by anyone with the URL and no account, is a different
    thing entirely. Everything about the caller (their claim, their pickup chat,
    whether it is theirs) is absent because there is no caller.
    """
    return GiveawayResponse(
        id=str(row["id"]),
        owner_id="",
        owner_name=None,
        wardrobe_item_id=None,
        title=row["title"],
        description=row["description"],
        images=images,
        thumbnails=thumbs,
        size=row["size"],
        category=row["category"],
        condition=row["condition"],
        area_label=row["area_label"],
        status=row["status"],
        is_mine=False,
        my_claim_status=None,
        my_claim_id=None,
        chat_id=None,
        chat_status=None,
        claim_count=row["claim_count"],
        created_at=row["created_at"],
    )


_PUBLIC_GIVEAWAY_SELECT = """
    select g.id, g.title, g.description, g.images, g.size, g.category,
           g.condition, g.area_label, g.status, g.created_at,
           (select count(*) from public.giveaway_claims c
             where c.giveaway_id = g.id) as claim_count
      from public.giveaways g
"""


@router.get("/public/giveaways", response_model=list[GiveawayResponse])
async def public_giveaways(
    request: Request,
    category: str | None = Query(None),
    size: str | None = Query(None),
    limit: int = Query(30, ge=1, le=60),
) -> list[GiveawayResponse]:
    """Available listings, newest first, with owners redacted.

    The block filter the private route applies is per-user and simply does not
    apply: there is no caller to have blocked anyone. Hidden and soft-deleted
    listings are excluded exactly as they are for a member.
    """
    async with get_pool().acquire() as conn:
        await _limit(request, conn, "giveaways", 300)
        rows = await conn.fetch(
            _PUBLIC_GIVEAWAY_SELECT
            + """
             where g.status = 'available'
               and g.hidden_at is null and g.deleted_at is null
               and ($1::text is null or g.category = $1)
               and ($2::text is null or g.size = $2)
             order by g.created_at desc
             limit $3
            """,
            category,
            size,
            limit,
        )
        out = []
        for r in rows:
            images, thumbs = await private_giveaways.resolve_public_images(conn, r)
            out.append(_public_giveaway(r, images, thumbs))
        return out


@router.get("/public/giveaways/{giveaway_id}", response_model=GiveawayResponse)
async def public_giveaway(request: Request, giveaway_id: UUID) -> GiveawayResponse:
    """One listing's public information and its published rules. Entering it
    requires an account, and that check lives on the private claim route, which
    this file does not mirror."""
    async with get_pool().acquire() as conn:
        await _limit(request, conn, "giveaways", 300)
        row = await conn.fetchrow(
            _PUBLIC_GIVEAWAY_SELECT
            + " where g.id = $1::uuid and g.deleted_at is null and g.hidden_at is null",
            str(giveaway_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        images, thumbs = await private_giveaways.resolve_public_images(conn, row)
        return _public_giveaway(row, images, thumbs)
