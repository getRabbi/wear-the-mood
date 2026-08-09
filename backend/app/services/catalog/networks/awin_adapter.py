"""Awin row -> the canonical shape the existing normalizer already validates.

The normalizer is not loosened for Awin. Everything Awin-specific is decided
here, and what leaves this module is an ordinary canonical record that
`normalize()` accepts or refuses on its own terms.

Decisions taken from the LIVE feed, not from documentation:

* **Identity is `merchant_product_id`.** It is the retailer's own product id
  (an AliExpress item id), stable across category feeds and across syncs.
  `aw_product_id` is Awin's surrogate and is per-feed — using it would make the
  same product a different product in a different feed. Uniqueness is already
  scoped to `(merchant_id, external_id)` by 0053, so two merchants sharing a
  numeric id cannot collide.

* **Stock is `unknown`.** The live feed sends `stock_quantity` of 0 for ~92% of
  rows that are plainly purchasable, so the column is a default rather than
  inventory. Mapping it literally would mark most of the catalogue out of stock
  and `product_is_servable()` would then hide it. A merchant whose stock is
  verified can opt in through the existing `stock_map` config.

* **Currency is per-ROW.** One feed carried both CNY and USD. A feed-level
  currency would have mispriced 13% of it.

* **No country availability is asserted.** The feed says nothing about where a
  product ships; the programme's region is where the PROGRAMME is, which is not
  the same claim. Left empty, which the catalog already reads as unrestricted-
  but-unknown, rather than invented.

* **Sizes, colours, variants, delivery: not fabricated.** The observed feed
  sends none of them, and the columns that exist (`brand_name`, `description`,
  `language`, `last_updated`, `delivery_cost`) were empty on every row.
"""

from __future__ import annotations

import logging
from typing import Any

log = logging.getLogger("fashionos.catalog.awin.adapter")

# Awin's own click-tracking host. `aw_deep_link` points here and carries the
# publisher id; it is the destination that earns commission, so it must reach
# the catalog intact — the affiliate redirect validates it against the
# merchant's allow-list later.
AWIN_CLICK_HOSTS = ("awin1.com", "www.awin1.com")


def _clean(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _first_http(*candidates: Any) -> str | None:
    for candidate in candidates:
        text = _clean(candidate)
        if text and (text.startswith("http://") or text.startswith("https://")):
            return text
    return None


def awin_row_to_canonical(row: dict[str, Any]) -> dict[str, Any]:
    """One Awin CSV row -> a canonical record.

    Never raises. A row this cannot make sense of comes out missing the fields
    the normalizer requires, and the normalizer refuses it with a named reason
    that the run reports — one bad row must not end a 150k-row feed.
    """
    external_id = _clean(row.get("merchant_product_id")) or _clean(row.get("aw_product_id"))

    # The image the retailer serves is preferred over Awin's cached copy: it is
    # the higher-resolution original, and it is the one whose rights are the
    # merchant's to grant.
    image = _first_http(row.get("merchant_image_url"), row.get("aw_image_url"))

    # The tracked link is what we want; the raw retailer URL is the fallback so
    # a feed missing the tracked one still produces a shoppable product rather
    # than a dead end.
    deep_link = _first_http(row.get("aw_deep_link"), row.get("merchant_deep_link"))

    canonical: dict[str, Any] = {
        "external_id": external_id,
        "title": _clean(row.get("product_name")),
        "description": _clean(row.get("description")),
        "brand": _clean(row.get("brand_name")),
        # `category_name` was empty in one live feed and populated in another,
        # so both are tried before giving up.
        "category": _clean(row.get("category_name")) or _clean(row.get("merchant_category")),
        "currency": _clean(row.get("currency")),
        "image_urls": [image] if image else [],
        # The affiliate reference the redirect service resolves. Awin's deep
        # link is already absolute and already tracked.
        "affiliate_ref": deep_link,
        # Deliberately absent rather than guessed. See the module docstring.
        "stock_status": "unknown",
        "country_availability": [],
        "colors": [],
        "sizes": [],
        "variants": [],
        "try_on_status": "unsupported",
        "sponsored": False,
    }

    # Price. Passed through as the feed's own decimal string; the merchant's
    # `price_format = 'major'` config makes the existing mapping layer convert it
    # in Decimal. Doing the arithmetic here would duplicate — and eventually
    # contradict — the one place that already gets it right.
    price = _clean(row.get("search_price"))
    if price:
        canonical["price_minor"] = price
    was = _clean(row.get("product_price_old"))
    if was:
        canonical["original_price_minor"] = was

    return canonical


def feed_provenance(row: dict[str, Any]) -> dict[str, str]:
    """Non-secret source identifiers worth keeping for support and debugging."""
    out = {}
    for key, column in (
        ("awin_product_id", "aw_product_id"),
        ("awin_feed_id", "data_feed_id"),
        ("awin_merchant_id", "merchant_id"),
    ):
        value = _clean(row.get(column))
        if value:
            out[key] = value
    return out
