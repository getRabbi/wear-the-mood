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


def build_where(
    filters: CatalogFilters,
    cursor: Cursor | None,
    *,
    hidden_merchant_ids: list[str] | None = None,
) -> tuple[str, list[object]]:
    """The WHERE clause and its parameters for one catalog page.

    Every clause here is a HARD filter from §19.1 — a product that fails any of
    them is not ranked lower, it is not shown. The servability rules (active,
    in-window, in-stock, rights cleared, image present, freshly synced) live in
    ``product_is_servable`` in migration 0053, so this and the RLS policy cannot
    drift apart.
    """
    params: list[object] = []
    clauses = [
        "public.product_is_servable(p)",
        "m.approved",
    ]

    def param(value: object) -> str:
        params.append(value)
        return f"${len(params)}"

    if filters.country:
        # Availability AND the merchant actually shipping there. A product
        # listed for a country the merchant will not ship to is not available
        # (§34 "merchant shipping eligibility must be checked before ranking").
        c = param(filters.country)
        clauses.append(f"({c} = any(p.country_availability) or p.country_availability = '{{}}')")
        clauses.append(f"({c} = any(m.shipping_countries) or m.shipping_countries = '{{}}')")

    if filters.currency:
        clauses.append(f"p.currency = {param(filters.currency)}")
    if filters.category:
        clauses.append(f"p.category = {param(filters.category)}")
    if filters.subcategory:
        clauses.append(f"p.subcategory = {param(filters.subcategory)}")
    if filters.audience:
        clauses.append(f"p.audience = {param(filters.audience)}")
    if filters.colors:
        clauses.append(f"p.colors && {param(filters.colors)}")
    if filters.sizes:
        clauses.append(f"p.sizes && {param(filters.sizes)}")
    if filters.brands:
        clauses.append(f"p.brand = any({param(filters.brands)})")
    if filters.min_price_minor is not None:
        clauses.append(f"p.price_minor >= {param(filters.min_price_minor)}")
    if filters.max_price_minor is not None:
        clauses.append(f"p.price_minor <= {param(filters.max_price_minor)}")
    if filters.try_on_ready:
        # 'pending' is NOT ready. A product is only labelled Try-On Ready once
        # compatibility has actually passed (§35).
        clauses.append("p.try_on_status = 'ready'")
    if filters.discounted:
        clauses.append(
            "p.original_price_minor is not null and p.original_price_minor > p.price_minor"
        )
    if filters.search:
        # Simple case-insensitive match across the fields a shopper types into.
        # Deliberately not full-text ranking yet — §19 says deterministic rules
        # first, and an unexplained relevance order is worse than an obvious one.
        term = param(f"%{filters.search}%")
        clauses.append(f"(p.title ilike {term} or p.brand ilike {term} or p.category ilike {term})")
    if hidden_merchant_ids:
        clauses.append(f"not (p.merchant_id = any({param(hidden_merchant_ids)}::uuid[]))")

    if cursor is not None:
        # Strictly after the last row seen, in the same (created_at, id) order
        # the index provides. The row comparison is what makes this a single
        # index range scan rather than an OR the planner has to unpick.
        t = param(cursor.created_at)
        i = param(cursor.product_id)
        clauses.append(f"(p.created_at, p.id) < ({t}, {i}::uuid)")

    return " and ".join(clauses), params


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
