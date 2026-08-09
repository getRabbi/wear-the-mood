"""Per-merchant field mapping: a real feed's shape -> the canonical shape.

This sits between the fetcher and `normalize`, and exists because no merchant
publishes our field names. It is deliberately the ONLY place that adapts to a
source: `normalize` stays strict, so the guarantees that strictness buys — a
price cannot drift by a factor of 100, an unusable image cannot reach a card —
are never weakened to accommodate a feed.

What it will do, given an explicit per-merchant declaration:

  * rename fields, including out of nested objects (`meta.sku`)
  * coerce a numeric id to the string the catalog keys on
  * scale a human price (9.99) into minor units (999), in DECIMAL
  * supply a currency the feed omits
  * turn a stock COUNT into a stock STATUS

What it will not do: infer any of the above. An unmapped feed is passed through
unchanged, so a merchant that already speaks the canonical shape is unaffected.
"""

from __future__ import annotations

import logging
from decimal import Decimal, InvalidOperation
from typing import Any

log = logging.getLogger("fashionos.catalog.mapping")

# Currencies whose minor unit IS the major unit. Scaling one of these by 100
# would multiply every price by a hundred, which is the exact failure the
# catalog's integer-minor-unit design exists to prevent.
ZERO_DECIMAL = frozenset(
    {
        "JPY",
        "KRW",
        "VND",
        "CLP",
        "ISK",
        "PYG",
        "RWF",
        "UGX",
        "VUV",
        "XAF",
        "XOF",
        "XPF",
        "BIF",
        "DJF",
        "GNF",
        "KMF",
        "MGA",
    }
)
# Three-decimal currencies. Rare, but scaling them by 100 is just as wrong.
THREE_DECIMAL = frozenset({"BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"})

# The canonical fields a map may target. Anything else in a field_map is a typo,
# and silently ignoring typos is how a mapping appears to work and does not.
CANONICAL_FIELDS = frozenset(
    {
        "external_id",
        "title",
        "description",
        "brand",
        "category",
        "subcategory",
        "audience",
        "price_minor",
        "original_price_minor",
        "currency",
        "image_urls",
        "image_focal_x",
        "image_focal_y",
        "colors",
        "sizes",
        "variants",
        "country_availability",
        # Must travel WITH country_availability, not be inferred from it. A
        # source that sends no countries can mean two different things, and this
        # field is how it says which. Dropping it here silently turned every
        # network product into `unrestricted` — the exact bug migration 0064
        # exists to remove — because `_eligibility()` cannot tell "the adapter
        # said unknown" from "the adapter said nothing" once the key is gone.
        "country_eligibility",
        "stock_status",
        "try_on_status",
        "affiliate_ref",
        "sponsored",
        "starts_at",
        "ends_at",
    }
)


def minor_unit_exponent(currency: str) -> int:
    code = (currency or "").strip().upper()
    if code in ZERO_DECIMAL:
        return 0
    if code in THREE_DECIMAL:
        return 3
    return 2


def _dig(record: dict[str, Any], path: str) -> Any:
    """Read `a.b.c` out of nested dicts, or None."""
    current: Any = record
    for part in path.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


def to_minor_units(value: Any, currency: str) -> int | None:
    """A human price -> integer minor units, in decimal.

    Via `str()` rather than `float()` arithmetic on purpose: `9.99 * 100` in
    binary floating point is 998.9999999999999, and `int()` of that is 998. One
    cent per product, every sync, forever. `Decimal("9.99") * 100` is exactly
    999.
    """
    if value is None or isinstance(value, bool):
        return None
    try:
        amount = Decimal(str(value).strip())
    except (InvalidOperation, ValueError):
        return None
    if amount < 0:
        return None
    scaled = amount * (10 ** minor_unit_exponent(currency))
    # A feed offering more precision than the currency has is quantized, not
    # rejected: 9.999 USD is a rounding artifact, not a different price.
    return int(scaled.quantize(Decimal("1")))


def _stock_from(value: Any, stock_map: dict[str, Any]) -> Any:
    """Translate a feed's stock value into one of our statuses.

    Handles the two shapes a real feed uses: a label ("In Stock", "sold out")
    and a COUNT (0, 3, 99). A count needs `low_stock_at` to be meaningful —
    without it the number is passed through and the normalizer will fall back to
    `unknown`, which is honest rather than invented.
    """
    values = stock_map.get("values") or {}
    if isinstance(value, str):
        mapped = values.get(value.strip().lower()) or values.get(value.strip())
        return mapped or value
    if isinstance(value, bool):
        return "in_stock" if value else "out_of_stock"
    if isinstance(value, int):
        threshold = stock_map.get("low_stock_at")
        if value <= 0:
            return "out_of_stock"
        if isinstance(threshold, int) and value <= threshold:
            return "low_stock"
        return "in_stock" if threshold is not None else value
    return value


def validate_field_map(field_map: dict[str, Any]) -> list[str]:
    """Canonical field names in a map that we do not recognise."""
    return sorted(k for k in field_map if k not in CANONICAL_FIELDS)


def apply_mapping(raw: dict[str, Any], config: dict[str, Any]) -> dict[str, Any]:
    """One raw feed record -> a canonical record `normalize` can read.

    Never raises: a record this cannot map is returned as far as it got, and the
    normalizer refuses it with a per-record error the run reports. One
    unmappable row must not end a sync.
    """
    if not isinstance(raw, dict):
        return raw

    field_map: dict[str, Any] = config.get("field_map") or {}
    price_format = (config.get("price_format") or "minor").lower()
    default_currency = (config.get("default_currency") or "").strip().upper()
    stock_map: dict[str, Any] = config.get("stock_map") or {}

    # Identity when unconfigured: a feed already speaking our shape is untouched.
    if not field_map and price_format == "minor" and not default_currency and not stock_map:
        return raw

    out: dict[str, Any] = {}
    for canonical in CANONICAL_FIELDS:
        source = field_map.get(canonical, canonical)
        value = _dig(raw, source) if isinstance(source, str) else None
        if value is not None:
            out[canonical] = value

    # Identity is a STRING in this catalog; a feed's integer id is still a
    # perfectly good id, it just has to be spelled the way the key is.
    if "external_id" in out and not isinstance(out["external_id"], str):
        out["external_id"] = str(out["external_id"])

    currency = str(out.get("currency") or default_currency or "").strip().upper()
    if currency:
        out["currency"] = currency

    if price_format == "major":
        for field in ("price_minor", "original_price_minor"):
            if field in out:
                converted = to_minor_units(out[field], currency)
                if converted is None:
                    # Leave the original in place; the normalizer will refuse it
                    # and the run will say which record and why.
                    continue
                out[field] = converted

    if "stock_status" in out:
        out["stock_status"] = _stock_from(out["stock_status"], stock_map)

    # A single image string is a list of one.
    if isinstance(out.get("image_urls"), str):
        out["image_urls"] = [out["image_urls"]]

    return out
