"""Turn a raw feed record into a [FeedProduct], or refuse it.

Everything questionable is decided HERE rather than at the writer, so the
database only ever sees data that has already been argued with.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlparse

from app.services.catalog.models import (
    ALLOWED_RIGHTS,
    ALLOWED_STOCK,
    FeedProduct,
    FeedVariant,
)

log = logging.getLogger("fashionos.catalog.normalize")

# Money is integer minor units. A float here is a bug in the feed adapter, not
# something to round helpfully.
MAX_PRICE_MINOR = 10**12


class FeedRecordError(ValueError):
    """A record that cannot be represented. Skipped and counted, never written."""


def _require_str(raw: dict[str, Any], key: str, *, max_len: int = 500) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value.strip():
        raise FeedRecordError(f"missing or empty {key}")
    return value.strip()[:max_len]


def _minor_units(value: Any, field: str) -> int:
    """An integer number of minor units, or a refusal.

    Floats are refused rather than converted. `19.99` in a JSON feed is
    ambiguous — cents? a rounding artifact? — and the catalog's whole money
    contract is that nobody guesses.
    """
    if isinstance(value, bool) or value is None:
        raise FeedRecordError(f"{field} is not an integer minor-unit amount")
    if isinstance(value, float):
        raise FeedRecordError(f"{field} must be integer minor units, got a float ({value})")
    if isinstance(value, str):
        if not value.strip().lstrip("-").isdigit():
            raise FeedRecordError(f"{field} is not an integer minor-unit amount")
        value = int(value)
    if not isinstance(value, int):
        raise FeedRecordError(f"{field} is not an integer minor-unit amount")
    if value < 0 or value > MAX_PRICE_MINOR:
        raise FeedRecordError(f"{field} out of range")
    return value


def usable_image_url(url: Any) -> bool:
    """Whether a URL is something a renderer and a try-on provider can fetch.

    The same rule the app applies client-side: absolute http(s) with a host.
    Anything else — a relative path, `data:`, `file:`, a bare filename — is
    dropped at import so it can never reach a product card or a paid render.
    """
    if not isinstance(url, str) or not url.strip():
        return False
    parsed = urlparse(url.strip())
    return parsed.scheme in ("http", "https") and bool(parsed.hostname)


def _images(raw: dict[str, Any]) -> list[str]:
    candidates = raw.get("image_urls") or raw.get("images") or []
    if isinstance(candidates, str):
        candidates = [candidates]
    if not isinstance(candidates, list):
        return []
    # De-duplicated but ORDER-PRESERVING: image[0] is the display image and the
    # try-on source, so which one is first is a decision, not an accident.
    seen: set[str] = set()
    out: list[str] = []
    for candidate in candidates:
        if not usable_image_url(candidate):
            continue
        url = candidate.strip()
        if url in seen:
            continue
        seen.add(url)
        out.append(url)
    return out[:10]


def _codes(raw: dict[str, Any], key: str) -> list[str]:
    """ISO-3166-1 alpha-2, uppercased, junk dropped."""
    values = raw.get(key) or []
    if isinstance(values, str):
        values = [values]
    if not isinstance(values, list):
        return []
    return sorted({v.strip().upper() for v in values if isinstance(v, str) and len(v.strip()) == 2})


ELIGIBILITY = ("listed", "unrestricted", "unknown")


def _eligibility(raw: dict[str, Any], countries: list[str]) -> str:
    """How much the source actually told us about where this product can ship.

    Three distinct states, because collapsing them is how a product with NO
    shipping information ends up passing every country filter as if it shipped
    worldwide:

    * ``listed``       — these specific countries, and no others.
    * ``unrestricted`` — the source positively asserts no restriction.
    * ``unknown``      — the source said nothing. Not a synonym for the above.

    A source that names countries is `listed` whatever it claims; a source that
    names none defaults to `unrestricted` only because that is what an empty
    list has always meant for the hand-curated catalog, and changing that
    silently would alter what is already live. A source with no shipping data —
    an affiliate network feed, say — sets `unknown` for itself.
    """
    if countries:
        return "listed"
    declared = str(raw.get("country_eligibility") or "").strip().lower()
    return declared if declared in ELIGIBILITY else "unrestricted"


def _strings(raw: dict[str, Any], key: str, *, limit: int = 40) -> list[str]:
    values = raw.get(key) or []
    if isinstance(values, str):
        values = [values]
    if not isinstance(values, list):
        return []
    return [v.strip()[:60] for v in values if isinstance(v, str) and v.strip()][:limit]


def _stock(value: Any) -> str:
    text = str(value or "unknown").strip().lower().replace("-", "_").replace(" ", "_")
    return text if text in ALLOWED_STOCK else "unknown"


def _timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def _variants(raw: dict[str, Any]) -> list[FeedVariant]:
    values = raw.get("variants") or []
    if not isinstance(values, list):
        return []
    out: list[FeedVariant] = []
    for item in values[:100]:
        if not isinstance(item, dict):
            continue
        ext = item.get("external_id") or item.get("sku")
        if not isinstance(ext, str) or not ext.strip():
            continue
        try:
            price = (
                _minor_units(item["price_minor"], "variant.price_minor")
                if item.get("price_minor") is not None
                else None
            )
            original = (
                _minor_units(item["original_price_minor"], "variant.original_price_minor")
                if item.get("original_price_minor") is not None
                else None
            )
        except FeedRecordError:
            # One malformed variant does not invalidate the product; it is the
            # variant that is dropped, and the product keeps its own price.
            continue
        out.append(
            FeedVariant(
                external_id=ext.strip()[:200],
                color=(item.get("color") or None),
                size=(item.get("size") or None),
                price_minor=price,
                original_price_minor=original,
                stock_status=_stock(item.get("stock_status")),
                available=bool(item.get("available", True)),
            )
        )
    return out


def normalize(raw: dict[str, Any]) -> FeedProduct:
    """One raw feed record -> a [FeedProduct]. Raises [FeedRecordError]."""
    if not isinstance(raw, dict):
        raise FeedRecordError("record is not an object")

    external_id = _require_str(raw, "external_id", max_len=200)
    title = _require_str(raw, "title", max_len=300)

    currency = str(raw.get("currency") or "").strip().upper()
    if len(currency) != 3 or not currency.isalpha():
        raise FeedRecordError(f"currency must be an ISO-4217 code, got {currency!r}")

    price_minor = _minor_units(raw.get("price_minor"), "price_minor")
    original_raw = raw.get("original_price_minor")
    original = (
        _minor_units(original_raw, "original_price_minor") if original_raw is not None else None
    )
    # A "discount" that is not one would render a struck-through price that
    # insults the reader. Dropped rather than shown.
    if original is not None and original <= price_minor:
        original = None

    focal_x = raw.get("image_focal_x", 0.5)
    focal_y = raw.get("image_focal_y", 0.5)
    try:
        focal_x = min(max(float(focal_x), 0.0), 1.0)
        focal_y = min(max(float(focal_y), 0.0), 1.0)
    except (TypeError, ValueError):
        focal_x, focal_y = 0.5, 0.5

    countries = _codes(raw, "country_availability")

    return FeedProduct(
        external_id=external_id,
        title=title,
        price_minor=price_minor,
        currency=currency,
        description=(raw.get("description") or None),
        brand=(raw.get("brand") or None),
        category=(raw.get("category") or None),
        subcategory=(raw.get("subcategory") or None),
        audience=(raw.get("audience") or None),
        original_price_minor=original,
        image_urls=_images(raw),
        image_focal_x=focal_x,
        image_focal_y=focal_y,
        colors=_strings(raw, "colors"),
        sizes=_strings(raw, "sizes"),
        variants=_variants(raw),
        country_availability=countries,
        country_eligibility=_eligibility(raw, countries),
        stock_status=_stock(raw.get("stock_status")),
        try_on_status=str(raw.get("try_on_status") or "unsupported").strip().lower(),
        affiliate_ref=(raw.get("affiliate_ref") or external_id),
        sponsored=bool(raw.get("sponsored", False)),
        starts_at=_timestamp(raw.get("starts_at")),
        ends_at=_timestamp(raw.get("ends_at")),
    )


def resolve_rights(feed_default: str) -> str:
    """The rights status an imported product gets.

    Deliberately NOT taken from the feed record. A merchant asserting per-row
    that it holds the rights to an image is exactly the claim that needs a human
    behind it, so the decision comes from `merchant_feed_config`, which only an
    admin can set. Anything but a configured `licensed` lands as `unknown`,
    which `product_is_servable()` already suppresses.
    """
    value = (feed_default or "unknown").strip().lower()
    return value if value in ALLOWED_RIGHTS else "unknown"


def resolve_tryon(product: FeedProduct, rights: str) -> tuple[str, str | None]:
    """`(try_on_status, tryon_image_url)` for an imported product.

    Readiness is DERIVED, never copied. A feed may say `ready`; this decides
    whether that is representable:

    * rights not cleared -> `unsupported`. Rendering a garment we may not use is
      worse than not offering it.
    * no usable image -> `unsupported`. `ready` with nothing to send is the dead
      tap the app already refuses to draw.
    * feed says `pending` -> stays `pending`; the feed is allowed to say "not yet".

    The chosen image is the first usable one, which is also the display image.
    An admin can override it later, and the writer never overwrites that.
    """
    claimed = (
        product.try_on_status if product.try_on_status in {"pending", "ready"} else "unsupported"
    )
    if claimed == "unsupported":
        return "unsupported", None
    if rights != "licensed":
        return "unsupported", None
    image = next((u for u in product.image_urls if usable_image_url(u)), None)
    if image is None:
        return "unsupported", None
    if claimed == "pending":
        return "pending", image
    return "ready", image
