"""Discover catalog: eligibility, cursors and deterministic ranking.

Kept out of the router so the rules are testable without HTTP, and so the
router stays a thin translation layer (CLAUDE.md §3).

Two things here are load-bearing:

* **The cursor.** Pagination is keyset, not offset. Offset pagination re-runs
  the query for every page, so a row inserted between page 1 and page 2 shifts
  everything down and the user sees a duplicate — the exact "offset drift and
  duplicate cards" §23 forbids. A keyset cursor names the last row seen, so the
  next page starts strictly after it no matter what was inserted meanwhile.

* **Ranking is deterministic and weighted, not machine-learned** (§19). The
  weights live in one place and sum to 1.0 so a change is visibly a trade-off
  rather than a quiet inflation of one signal.
"""

from __future__ import annotations

import base64
import binascii
import json
from dataclasses import dataclass, field
from datetime import datetime

# §19.2 — starting points, deliberately in config rather than scattered through
# the query. They sum to 1.0; the assertion below is what keeps that true.
RANKING_WEIGHTS: dict[str, float] = {
    "style_preference": 0.25,
    "closet_compatibility": 0.20,
    "current_mood": 0.15,
    "color_preference": 0.10,
    "budget_fit": 0.10,
    "behavioral": 0.10,
    "freshness": 0.05,
    "merchant_quality": 0.05,
}

assert abs(sum(RANKING_WEIGHTS.values()) - 1.0) < 1e-9, "ranking weights must sum to 1.0"

# How many products a page holds. Small enough that the first screen is quick,
# large enough that a tall tablet does not paginate on arrival.
DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50


class InvalidCursor(ValueError):
    """The cursor was not something this server issued."""


@dataclass(frozen=True)
class Cursor:
    """Keyset position: the (created_at, id) of the last row already returned."""

    created_at: datetime
    product_id: str

    def encode(self) -> str:
        raw = json.dumps(
            {"t": self.created_at.isoformat(), "i": self.product_id},
            separators=(",", ":"),
        ).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    @classmethod
    def decode(cls, value: str) -> Cursor:
        try:
            padded = value + "=" * (-len(value) % 4)
            data = json.loads(base64.urlsafe_b64decode(padded))
            return cls(created_at=datetime.fromisoformat(data["t"]), product_id=str(data["i"]))
        except (
            binascii.Error,
            ValueError,
            KeyError,
            TypeError,
            json.JSONDecodeError,
        ) as exc:
            # A malformed cursor is a client bug or someone poking at the API.
            # Either way it must be a clean 400, never a 500 and never a silent
            # reset to page 1 that loops the user through the same products.
            raise InvalidCursor("malformed cursor") from exc


@dataclass
class CatalogFilters:
    """The §11.2 filter set, normalized. Every field is optional."""

    country: str | None = None
    category: str | None = None
    subcategory: str | None = None
    colors: list[str] = field(default_factory=list)
    sizes: list[str] = field(default_factory=list)
    brands: list[str] = field(default_factory=list)
    min_price_minor: int | None = None
    max_price_minor: int | None = None
    currency: str | None = None
    try_on_ready: bool = False
    discounted: bool = False
    search: str | None = None
    audience: str | None = None

    @property
    def active_count(self) -> int:
        """How many filters are set — the app shows `Filters · N` (§11.2)."""
        return sum(
            [
                bool(self.category),
                bool(self.subcategory),
                bool(self.colors),
                bool(self.sizes),
                bool(self.brands),
                self.min_price_minor is not None or self.max_price_minor is not None,
                self.try_on_ready,
                self.discounted,
                bool(self.audience),
            ]
        )


def normalize_country(value: str | None) -> str | None:
    """ISO-3166-1 alpha-2, uppercase. Anything else is treated as absent rather
    than passed through to the query as a filter that silently matches nothing."""
    if not value:
        return None
    code = value.strip().upper()
    return code if len(code) == 2 and code.isalpha() else None


def normalize_currency(value: str | None) -> str | None:
    """ISO-4217, uppercase."""
    if not value:
        return None
    code = value.strip().upper()
    return code if len(code) == 3 and code.isalpha() else None


def clamp_limit(value: int | None) -> int:
    if value is None:
        return DEFAULT_PAGE_SIZE
    return max(1, min(int(value), MAX_PAGE_SIZE))


#: Stage names for the candidate funnel, in the order the filters apply.
#:
#: Named here rather than in the router so that "why is this section empty" is
#: answered in the same vocabulary the query is built from — see
#: [build_stages] and [build_funnel_sql].
STAGE_PRODUCT_STATE = "after_product_state"
STAGE_REGION = "after_region_filter"
STAGE_PREFERENCES = "after_preferences"
STAGE_FILTERS = "after_explicit_filters"
STAGE_CURSOR = "after_cursor"


@dataclass(frozen=True)
class FilterStage:
    """One named group of hard filters, and the SQL that applies it."""

    name: str
    clause: str


def build_stages(
    filters: CatalogFilters,
    cursor: Cursor | None,
    *,
    hidden_merchant_ids: list[str] | None = None,
) -> tuple[list[FilterStage], list[object]]:
    """The hard filters for one catalog page, GROUPED and NAMED.

    Every clause here is a HARD filter from §19.1 — a product that fails any of
    them is not ranked lower, it is not shown. The servability rules (active,
    in-window, in-stock, rights cleared, image present, freshly synced) live in
    ``product_is_servable`` in migration 0053, so this and the RLS policy cannot
    drift apart.

    Returned as stages rather than one string so the diagnostic funnel counts
    exactly what the page query filtered on. A funnel written separately would
    drift from the query within a release and then confidently explain the wrong
    thing (§14).
    """
    params: list[object] = []
    stages: list[FilterStage] = []
    state_clauses = [
        "public.product_is_servable(p)",
        "m.approved",
    ]
    region_clauses = [
        # Deliverable to SOMEONE, regardless of who is asking. A product listing
        # only countries its merchant will not ship to can be bought by nobody,
        # so it is a broken listing rather than a regional one — and the country
        # clause below cannot catch it, because a new user has no country yet
        # and that clause does not run at all (§34, §35).
        #
        # Scoped to `listed` products on purpose. This clause detects a
        # CONTRADICTION between two positive claims; a product whose eligibility
        # is unknown makes no claim to contradict, and dropping it here would
        # hide it from every user who has not told us where they are, which is
        # not what "we don't know yet" should cost.
        "(p.country_eligibility <> 'listed' or m.shipping_countries = '{}'"
        " or p.country_availability && m.shipping_countries)",
    ]

    def param(value: object) -> str:
        params.append(value)
        return f"${len(params)}"

    if filters.country:
        # ONE function, defined in migration 0064, rather than a clause spelled
        # out here and again in every other query that asks the same question.
        #
        # The important case is `unknown`: a product whose source said nothing
        # about shipping is answered by what an admin VERIFIED about the
        # merchant, and if nobody verified anything the answer is no. Treating
        # silence as "ships worldwide" is how a shopper in Dhaka gets shown a
        # product that will never reach them (§34).
        # `unknown` is admitted here and nowhere else. product_ships_to still
        # answers the delivery question truthfully — it says no, because nobody
        # has checked — but "we do not know" is not the same refusal as "this
        # product says it does not go there", and only the second should hide a
        # product. A network feed supplies no shipping data at all, so treating
        # silence as a refusal would empty the affiliate catalog for every user
        # who has told us where they live.
        #
        # What it must NOT become is `unrestricted`: that is a positive claim we
        # have no evidence for, and it is the exact bug 0064 exists to prevent.
        # The product is shown with `shipping_availability='unknown'` and the
        # client says so in words; the retailer resolves it at checkout.
        #
        # A `listed` product that excludes this country, or an `unrestricted`
        # one whose merchant will not ship there, is still hidden — those are
        # claims, and they say no.
        c = param(filters.country)
        region_clauses.append(
            "(public.product_ships_to(p.country_eligibility, p.country_availability,"
            f" m.shipping_countries, {c})"
            " or p.country_eligibility = 'unknown')"
        )

    # CURRENCY IS NOT A FILTER. It used to be — `p.currency = $n`, fed straight
    # from `shopping_preferences.currency` — which meant a shopper who set BDT
    # would be served an empty catalog the instant every listing was priced in
    # USD. Nothing surfaced that: `region_empty` only ever asked about COUNTRY,
    # so the app received "no products" with no reason attached and the section
    # simply was not there.
    #
    # The architecture does not require merchant-native currency matching:
    # every product carries its own `Money(amount_minor, currency)` and the
    # client formats what the merchant actually charges. There is no FX
    # infrastructure to convert with, and none is invented here. So the value
    # stays what it always should have been — a PREFERENCE, echoed back on the
    # page and part of the cache key — and it no longer decides whether the
    # catalog exists. If merchant-native filtering is ever genuinely required it
    # belongs behind an explicit, user-visible filter, not behind a display
    # setting nobody chose.
    filter_clauses: list[str] = []
    if filters.category:
        filter_clauses.append(f"p.category = {param(filters.category)}")
    if filters.subcategory:
        filter_clauses.append(f"p.subcategory = {param(filters.subcategory)}")
    if filters.audience:
        filter_clauses.append(f"p.audience = {param(filters.audience)}")
    if filters.colors:
        filter_clauses.append(f"p.colors && {param(filters.colors)}")
    if filters.sizes:
        filter_clauses.append(f"p.sizes && {param(filters.sizes)}")
    if filters.brands:
        filter_clauses.append(f"p.brand = any({param(filters.brands)})")
    if filters.min_price_minor is not None:
        filter_clauses.append(f"p.price_minor >= {param(filters.min_price_minor)}")
    if filters.max_price_minor is not None:
        filter_clauses.append(f"p.price_minor <= {param(filters.max_price_minor)}")
    if filters.try_on_ready:
        # 'pending' is NOT ready. A product is only labelled Try-On Ready once
        # compatibility has actually passed (§35).
        #
        # `product_tryon_ready` (0065) rather than the column, because readiness
        # is three conditions and the column is one of them: licensed image
        # rights and a usable image are the other two. Filtering on the column
        # alone returned products the feed then serialized as `unsupported`,
        # which is a filter that contradicts its own results.
        filter_clauses.append("public.product_tryon_ready(p)")
    if filters.discounted:
        filter_clauses.append(
            "p.original_price_minor is not null and p.original_price_minor > p.price_minor"
        )
    if filters.search:
        # Simple case-insensitive match across the fields a shopper types into.
        # Deliberately not full-text ranking yet — §19 says deterministic rules
        # first, and an unexplained relevance order is worse than an obvious one.
        term = param(f"%{filters.search}%")
        filter_clauses.append(
            f"(p.title ilike {term} or p.brand ilike {term} or p.category ilike {term})"
        )

    preference_clauses: list[str] = []
    if hidden_merchant_ids:
        preference_clauses.append(
            f"not (p.merchant_id = any({param(hidden_merchant_ids)}::uuid[]))"
        )

    stages.append(FilterStage(STAGE_PRODUCT_STATE, _and(state_clauses)))
    stages.append(FilterStage(STAGE_REGION, _and(region_clauses)))
    stages.append(FilterStage(STAGE_PREFERENCES, _and(preference_clauses)))
    stages.append(FilterStage(STAGE_FILTERS, _and(filter_clauses)))

    if cursor is not None:
        # Strictly after the last row seen, in the same (created_at, id) order
        # the index provides. The row comparison is what makes this a single
        # index range scan rather than an OR the planner has to unpick.
        t = param(cursor.created_at)
        i = param(cursor.product_id)
        stages.append(FilterStage(STAGE_CURSOR, f"(p.created_at, p.id) < ({t}, {i}::uuid)"))

    return stages, params


def _and(clauses: list[str]) -> str:
    """Conjoin, or ``true`` for an empty stage — so a stage that applies nothing
    still occupies its place in the funnel instead of silently disappearing."""
    return " and ".join(clauses) if clauses else "true"


def build_where(
    filters: CatalogFilters,
    cursor: Cursor | None,
    *,
    hidden_merchant_ids: list[str] | None = None,
) -> tuple[str, list[object]]:
    """The WHERE clause and its parameters for one catalog page."""
    stages, params = build_stages(filters, cursor, hidden_merchant_ids=hidden_merchant_ids)
    return " and ".join(s.clause for s in stages), params


def build_funnel_sql(stages: list[FilterStage]) -> str:
    """A ONE-round-trip query counting survivors after each stage.

    Cumulative on purpose: each column applies its own stage AND every stage
    before it, so reading left to right shows exactly where the candidates went.
    That is the difference between "the section is empty" and "the section is
    empty because this account's country removed the last four products" (§14).
    """
    columns = ["count(*) as catalog_candidates"]
    applied: list[str] = []
    for stage in stages:
        applied.append(stage.clause)
        columns.append(f"count(*) filter (where {' and '.join(applied)}) as {stage.name}")
    return (
        f"select {', '.join(columns)} "
        "from public.products p join public.merchants m on m.id = p.merchant_id"
    )


def match_reason_for(
    row: dict[str, object],
    *,
    closet_categories: set[str] | None = None,
    favorite_categories: set[str] | None = None,
    budget_max_minor: int | None = None,
) -> str | None:
    """The ONE reason shown on a card (§8.1).

    Ordered most-specific first: "matches your closet" is a better thing to say
    than "trending", so a product that qualifies for both says the former.
    Returns None rather than inventing a reason — no reason at all beats a
    generic one the user cannot act on.
    """
    category = (row.get("category") or "").strip().lower()
    original = row.get("original_price_minor")
    price = row.get("price_minor")

    if closet_categories and category and category in closet_categories:
        return "closet_match"
    if favorite_categories and category and category in favorite_categories:
        return "style_match"
    if isinstance(original, int) and isinstance(price, int) and original > price:
        return "price_drop"
    if budget_max_minor is not None and isinstance(price, int) and price <= budget_max_minor:
        return "budget_fit"
    return None


def facet_label(value: str) -> str:
    """A human-readable default for a canonical facet value.

    The CLIENT owns display text and may localize it; this is the fallback for
    a value the client has never seen, which is the whole point of returning
    canonical values and labels separately. `evening_wear` → `Evening Wear`.
    """
    return " ".join(part.capitalize() for part in value.replace("_", " ").split())
