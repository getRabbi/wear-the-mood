"""Discover shopping catalog API (DISCOVER spec §12, §17, §19, §37).

Serves the personalized product feed, saves, and the behavioural signal that
ranking reads. Auth is required on every route: this is per-user personalization
and per-user state, and the user id always comes from the verified JWT, never
from anything the client sends (CLAUDE.md §11).

Two boundaries this file will not cross:

* **No affiliate URL ever reaches the client.** Products carry an opaque
  `affiliate_ref` that only the Phase 4 redirect service can resolve. A raw
  retailer link in a response would be a link the app could open unvalidated
  (§18, §38, safety rule 11).
* **No client-supplied price, discount, stock or entitlement is trusted.**
  Everything monetary is read from the database inside the request (§38).
"""

from __future__ import annotations

from datetime import UTC, datetime

import asyncpg
from fastapi import APIRouter, Body, Depends, Query

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.flags import flag_enabled
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.discover import (
    CatalogFacets,
    FacetValue,
    InteractionRequest,
    MerchantSummary,
    Money,
    Product,
    ProductPage,
    ProductVariant,
    SavedProduct,
    SaveProductRequest,
    ShoppingPreferences,
)
from app.services.discover.catalog import (
    CatalogFilters,
    Cursor,
    InvalidCursor,
    build_where,
    clamp_limit,
    facet_label,
    match_reason_for,
    normalize_country,
    normalize_currency,
)

router = APIRouter(tags=["discover"])

# The columns every product response is built from. Listed once so the feed,
# the saved list and any future single-product read cannot drift into returning
# different shapes for the same entity.
_PRODUCT_COLUMNS = """
    p.id, p.title, p.brand, p.description, p.category, p.subcategory,
    p.price_minor, p.original_price_minor, p.currency,
    p.image_urls, p.image_focal_x, p.image_focal_y,
    p.colors, p.sizes, p.stock_status, p.try_on_status, p.sponsored,
    p.last_synced_at, p.created_at,
    m.id as merchant_id, m.name as merchant_name, m.logo_url as merchant_logo
"""


async def _require_shopping(conn: asyncpg.Connection) -> None:
    """Shopping is behind its own flag, checked SERVER-side.

    The app gates its UI too, but a flag the client alone enforces is not a
    kill switch — an older build, or a modified one, would keep calling. Off by
    default so an environment that has not been switched on serves nothing
    (§14, §30).
    """
    if not await flag_enabled(conn, "feature_shopping", default=False):
        raise ApiError(ErrorCode.NOT_FOUND, "Shopping is not available.", 404)


def _money(amount: object, currency: object) -> Money | None:
    if amount is None or currency is None:
        return None
    return Money(amount_minor=int(amount), currency=str(currency))


def _product(row: asyncpg.Record, *, saved: bool = False, reason: str | None = None) -> Product:
    return Product(
        id=str(row["id"]),
        merchant=MerchantSummary(
            id=str(row["merchant_id"]),
            name=row["merchant_name"],
            logo_url=row["merchant_logo"],
        ),
        title=row["title"],
        brand=row["brand"],
        description=row["description"],
        category=row["category"],
        subcategory=row["subcategory"],
        price=Money(amount_minor=int(row["price_minor"]), currency=str(row["currency"])),
        original_price=_money(row["original_price_minor"], row["currency"]),
        image_urls=list(row["image_urls"] or []),
        image_focal_x=float(row["image_focal_x"]),
        image_focal_y=float(row["image_focal_y"]),
        colors=list(row["colors"] or []),
        sizes=list(row["sizes"] or []),
        stock_status=row["stock_status"],
        try_on_status=row["try_on_status"],
        match_reason=reason,
        saved=saved,
        sponsored=bool(row["sponsored"]),
        # Correlates a card with the click it produces. An id, not a URL.
        tracking_token=f"p:{row['id']}",
        last_synced_at=row["last_synced_at"].isoformat() if row["last_synced_at"] else None,
    )


async def _variants(
    conn: asyncpg.Connection, product_ids: list[str]
) -> dict[str, list[ProductVariant]]:
    """Variants for a page of products, in one round trip rather than N."""
    if not product_ids:
        return {}
    rows = await conn.fetch(
        """
        select v.id, v.product_id, v.color, v.size, v.price_minor,
               v.original_price_minor, v.stock_status, v.available, p.currency
          from public.product_variants v
          join public.products p on p.id = v.product_id
         where v.product_id = any($1::uuid[]) and v.available
         order by v.size, v.color
        """,
        product_ids,
    )
    out: dict[str, list[ProductVariant]] = {}
    for r in rows:
        out.setdefault(str(r["product_id"]), []).append(
            ProductVariant(
                id=str(r["id"]),
                color=r["color"],
                size=r["size"],
                price=_money(r["price_minor"], r["currency"]),
                original_price=_money(r["original_price_minor"], r["currency"]),
                stock_status=r["stock_status"],
                available=bool(r["available"]),
            )
        )
    return out


async def _preferences(conn: asyncpg.Connection, user_id: str) -> asyncpg.Record | None:
    return await conn.fetchrow(
        """
        select country, currency, budget_min_minor, budget_max_minor, sizes,
               favorite_categories, avoided_colors, modest_preference,
               personalization_enabled, hidden_merchant_ids, updated_at
          from public.shopping_preferences where user_id = $1
        """,
        user_id,
    )


@router.get("/discover/products", response_model=ProductPage)
async def list_products(
    user: CurrentUser = Depends(get_current_user),
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
    """One page of the personalized catalog.

    Prices in `min_price`/`max_price` are MINOR UNITS, matching everything else.
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)

        prefs = await _preferences(conn, user.id)
        # The user's saved shopping country wins over a query parameter, so the
        # feed does not silently change region because a stale client sent an
        # old value. Precise location is never consulted (§34, §36).
        resolved_country = normalize_country((prefs["country"] if prefs else None) or country)
        resolved_currency = normalize_currency((prefs["currency"] if prefs else None) or currency)

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

        hidden = list(prefs["hidden_merchant_ids"]) if prefs else []
        where, params = build_where(filters, position, hidden_merchant_ids=hidden)
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

        # Fetch one extra to learn whether another page exists, without a
        # second COUNT query that would race with inserts anyway.
        has_more = len(rows) > take
        page_rows = rows[:take]
        ids = [str(r["id"]) for r in page_rows]

        saved_ids = set()
        if ids:
            saved_rows = await conn.fetch(
                "select product_id from public.saved_products "
                "where user_id = $1 and product_id = any($2::uuid[])",
                user.id,
                ids,
            )
            saved_ids = {str(r["product_id"]) for r in saved_rows}

        variants = await _variants(conn, ids)

        # Personalization inputs. A user who has turned personalization off
        # still gets a feed — just an unranked one (§36).
        personalize = bool(prefs["personalization_enabled"]) if prefs else True
        closet_categories: set[str] = set()
        if personalize:
            closet_rows = await conn.fetch(
                "select distinct lower(category) as category from public.wardrobe_items "
                "where user_id = $1 and category is not null limit 40",
                user.id,
            )
            closet_categories = {r["category"] for r in closet_rows if r["category"]}
        favorites = (
            {c.lower() for c in (prefs["favorite_categories"] or [])}
            if prefs and personalize
            else set()
        )
        budget_max = prefs["budget_max_minor"] if prefs and personalize else None

        # Nothing at all in this region, as opposed to nothing matching the
        # filters — a different empty state (§24).
        region_empty = False
        if not page_rows and position is None and resolved_country:
            region_empty = (
                await conn.fetchval(
                    """
                    select not exists (
                      select 1 from public.products p
                        join public.merchants m on m.id = p.merchant_id
                       where public.product_is_servable(p) and m.approved
                         and ($1 = any(p.country_availability) or p.country_availability = '{}')
                    )
                    """,
                    resolved_country,
                )
                or False
            )

        items = []
        for r in page_rows:
            product = _product(
                r,
                saved=str(r["id"]) in saved_ids,
                reason=match_reason_for(
                    dict(r),
                    closet_categories=closet_categories,
                    favorite_categories=favorites,
                    budget_max_minor=budget_max,
                ),
            )
            items.append(product.model_copy(update={"variants": variants.get(product.id, [])}))

        last = page_rows[-1] if page_rows else None
        # Seconds since epoch of the last preference change — monotonic, and 0
        # when the user has no preferences row. The app keys its offline cache
        # on this, so any preference change drops a page ranked under the old
        # profile rather than serving it as current.
        updated = prefs["updated_at"] if prefs else None
        profile_version = int(updated.timestamp()) if updated is not None else 0

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
            profile_version=profile_version,
        )


@router.get("/discover/facets", response_model=CatalogFacets)
async def facets(
    user: CurrentUser = Depends(get_current_user),
    country: str | None = Query(default=None, max_length=2),
) -> CatalogFacets:
    """Filter vocabularies for the CURRENTLY SERVABLE catalog (§11.2).

    Derived from the same servability rules the feed uses, so a filter can
    never be offered that returns nothing: a size that exists only on expired,
    unlicensed, out-of-stock or un-shippable products is not in the list.

    An empty result is a valid answer — a region with no catalog has no facets
    — and the client falls back to its curated defaults rather than showing an
    empty sheet (§24).
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        prefs = await _preferences(conn, user.id)
        resolved = normalize_country((prefs["country"] if prefs else None) or country)

        where, params = build_where(CatalogFilters(country=resolved), None)
        row = await conn.fetchrow(
            f"""
            select
              coalesce(array_agg(distinct p.category) filter (where p.category is not null), '{{}}')
                as categories,
              coalesce(array_agg(distinct s) filter (where s is not null), '{{}}') as sizes,
              coalesce(array_agg(distinct c) filter (where c is not null), '{{}}') as colors,
              coalesce(
                array_agg(distinct m.name || '|' || m.id::text) filter (where m.id is not null),
                '{{}}'
              ) as merchants,
              min(p.price_minor) as min_price,
              max(p.price_minor) as max_price,
              -- One currency per region in practice; if a region ever mixes
              -- them the bounds are meaningless, so this reports the mix and
              -- the caller drops the bounds rather than comparing apples to
              -- yen.
              count(distinct p.currency) as currency_count,
              min(p.currency) as currency,
              bool_or(p.try_on_status = 'ready') as try_on_available,
              bool_or(
                p.original_price_minor is not null
                and p.original_price_minor > p.price_minor
              ) as discount_available
            from public.products p
            join public.merchants m on m.id = p.merchant_id
            left join lateral unnest(p.sizes) as s on true
            left join lateral unnest(p.colors) as c on true
            where {where}
            """,
            *params,
        )

        if row is None:
            return CatalogFacets()

        def values(raw: object) -> list[FacetValue]:
            return [
                FacetValue(value=str(v), label=facet_label(str(v)))
                for v in (raw or [])
                if str(v).strip()
            ]

        merchants = []
        for entry in row["merchants"] or []:
            name, _, merchant_id = str(entry).rpartition("|")
            if merchant_id:
                merchants.append(FacetValue(value=merchant_id, label=name))

        # Price bounds only make sense within one currency.
        single_currency = (row["currency_count"] or 0) == 1
        currency = row["currency"] if single_currency else None

        return CatalogFacets(
            categories=values(row["categories"]),
            sizes=values(row["sizes"]),
            colors=values(row["colors"]),
            merchants=merchants,
            min_price=_money(row["min_price"], currency),
            max_price=_money(row["max_price"], currency),
            try_on_available=bool(row["try_on_available"]),
            discount_available=bool(row["discount_available"]),
        )


@router.get("/discover/saved", response_model=list[SavedProduct])
async def list_saved(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(default=50, ge=1, le=100),
) -> list[SavedProduct]:
    """Saved products, newest first.

    Deliberately does NOT apply the servability filter: a product that has gone
    out of stock or whose offer ended must still appear in Saved, with its
    state, rather than vanishing without explanation (§11.3).
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        rows = await conn.fetch(
            f"""
            select {_PRODUCT_COLUMNS},
                   s.saved_at, s.price_alert_enabled, s.availability_alert_enabled,
                   s.saved_price_minor
              from public.saved_products s
              join public.products p on p.id = s.product_id
              join public.merchants m on m.id = p.merchant_id
             where s.user_id = $1
             order by s.saved_at desc
             limit $2
            """,
            user.id,
            limit,
        )
        return [
            SavedProduct(
                product=_product(r, saved=True),
                saved_at=r["saved_at"].isoformat(),
                price_alert_enabled=bool(r["price_alert_enabled"]),
                availability_alert_enabled=bool(r["availability_alert_enabled"]),
                # Derived server-side from the price stored at save time —
                # never from a discount the client claims (§38).
                price_dropped=(
                    r["saved_price_minor"] is not None
                    and int(r["price_minor"]) < int(r["saved_price_minor"])
                ),
            )
            for r in rows
        ]


@router.put("/discover/saved/{product_id}", status_code=204)
async def save_product(
    product_id: str,
    body: SaveProductRequest = Body(default_factory=SaveProductRequest),
    user: CurrentUser = Depends(get_current_user),
) -> None:
    """Save a product. Idempotent: the primary key makes a double-tap one row."""
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        # Read the price HERE rather than accepting one from the client, so the
        # price-drop comparison later is against something we actually served.
        row = await conn.fetchrow(
            "select price_minor, currency from public.products where id = $1::uuid",
            product_id,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Product not found.", 404)

        await conn.execute(
            """
            insert into public.saved_products
              (user_id, product_id, price_alert_enabled, availability_alert_enabled,
               saved_price_minor, saved_currency)
            values ($1, $2::uuid, $3, $4, $5, $6)
            on conflict (user_id, product_id) do update
              set price_alert_enabled = excluded.price_alert_enabled,
                  availability_alert_enabled = excluded.availability_alert_enabled
            """,
            user.id,
            product_id,
            body.price_alert_enabled,
            body.availability_alert_enabled,
            int(row["price_minor"]),
            str(row["currency"]),
        )


@router.delete("/discover/saved/{product_id}", status_code=204)
async def unsave_product(
    product_id: str,
    user: CurrentUser = Depends(get_current_user),
) -> None:
    """Unsave. Also idempotent — removing something already gone is success."""
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await conn.execute(
            "delete from public.saved_products where user_id = $1 and product_id = $2::uuid",
            user.id,
            product_id,
        )


@router.post("/discover/interactions", status_code=204)
async def record_interaction(
    body: InteractionRequest,
    user: CurrentUser = Depends(get_current_user),
) -> None:
    """Record one behavioural signal.

    Idempotent when the client supplies `client_event_id`: the unique index on
    (user_id, client_event_id) turns a retry into a no-op, so a dropped
    response cannot double-count a save or an impression (§37.3).
    """
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await conn.execute(
            """
            insert into public.product_interactions
              (user_id, product_id, merchant_id, event_type, feed_placement,
               story_id, tracking_token, client_event_id)
            values ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8)
            on conflict (user_id, client_event_id) where client_event_id is not null
              do nothing
            """,
            user.id,
            body.product_id,
            body.merchant_id,
            body.event_type,
            body.feed_placement,
            body.story_id,
            body.tracking_token,
            body.client_event_id,
        )


@router.get("/discover/preferences", response_model=ShoppingPreferences)
async def get_preferences(
    user: CurrentUser = Depends(get_current_user),
) -> ShoppingPreferences:
    """The user's shopping preferences. A missing row means all-defaults."""
    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        row = await _preferences(conn, user.id)
        if row is None:
            return ShoppingPreferences()
        currency = row["currency"]
        return ShoppingPreferences(
            country=row["country"],
            currency=currency,
            budget_min=_money(row["budget_min_minor"], currency),
            budget_max=_money(row["budget_max_minor"], currency),
            sizes=list(row["sizes"] or []),
            favorite_categories=list(row["favorite_categories"] or []),
            avoided_colors=list(row["avoided_colors"] or []),
            modest_preference=bool(row["modest_preference"]),
            personalization_enabled=bool(row["personalization_enabled"]),
        )


@router.put("/discover/preferences", response_model=ShoppingPreferences)
async def put_preferences(
    body: ShoppingPreferences,
    user: CurrentUser = Depends(get_current_user),
) -> ShoppingPreferences:
    """Update shopping preferences (§36 user controls)."""
    country = normalize_country(body.country)
    currency = normalize_currency(body.currency)
    if body.country and country is None:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Invalid country code.", 400)
    if body.currency and currency is None:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Invalid currency code.", 400)

    async with get_pool().acquire() as conn:
        await _require_shopping(conn)
        await conn.execute(
            """
            insert into public.shopping_preferences
              (user_id, country, currency, budget_min_minor, budget_max_minor,
               sizes, favorite_categories, avoided_colors, modest_preference,
               personalization_enabled, updated_at)
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())
            on conflict (user_id) do update set
              country = excluded.country,
              currency = excluded.currency,
              budget_min_minor = excluded.budget_min_minor,
              budget_max_minor = excluded.budget_max_minor,
              sizes = excluded.sizes,
              favorite_categories = excluded.favorite_categories,
              avoided_colors = excluded.avoided_colors,
              modest_preference = excluded.modest_preference,
              personalization_enabled = excluded.personalization_enabled,
              updated_at = now()
            """,
            user.id,
            country,
            currency,
            body.budget_min.amount_minor if body.budget_min else None,
            body.budget_max.amount_minor if body.budget_max else None,
            body.sizes,
            body.favorite_categories,
            body.avoided_colors,
            body.modest_preference,
            body.personalization_enabled,
        )
        return body.model_copy(update={"country": country, "currency": currency})
