"""Where a product can actually be delivered — and the difference between not
knowing and no restriction.

`country_availability` has always been an array where empty means unrestricted.
That was safe while a person who knew the answer typed every row. It stops being
safe the moment a feed we did not write supplies products with no shipping data:
empty then reads as "ships worldwide", and a shopper in Dhaka is shown a product
that will never reach them.

So absence has a name now, and these are the tests that keep the three states
apart.
"""

from __future__ import annotations

import pytest

from app.services.catalog.normalize import normalize
from app.services.discover.catalog import CatalogFilters, build_where

BASE = {
    "external_id": "sku-1",
    "title": "Silk blouse",
    "price_minor": 89900,
    "currency": "BDT",
    "image_urls": ["https://cdn.example.test/a.jpg"],
}


# ── the three states ────────────────────────────────────────────────────────


def test_naming_countries_means_those_countries() -> None:
    p = normalize({**BASE, "country_availability": ["bd", "IN"]})
    assert p.country_eligibility == "listed"
    assert p.country_availability == ["BD", "IN"]


def test_saying_nothing_still_defaults_to_the_behaviour_that_shipped() -> None:
    # The hand-curated catalog has always read an empty list as unrestricted.
    # Changing that silently would alter what is already live, so a source that
    # declares nothing keeps the old meaning; a source that KNOWS it has no
    # shipping data says so.
    assert normalize(dict(BASE)).country_eligibility == "unrestricted"


def test_a_source_with_no_shipping_data_declares_unknown() -> None:
    p = normalize({**BASE, "country_eligibility": "unknown"})
    assert p.country_eligibility == "unknown"
    assert p.country_availability == []


def test_naming_countries_wins_over_any_declaration() -> None:
    # A feed that lists countries AND claims to know nothing has still listed
    # countries. The positive evidence is the more specific claim.
    p = normalize({**BASE, "country_availability": ["BD"], "country_eligibility": "unknown"})
    assert p.country_eligibility == "listed"


@pytest.mark.parametrize("junk", ["worldwide", "", "UNKNOWN!", None, 7])
def test_an_unrecognised_declaration_does_not_invent_a_fourth_state(junk: object) -> None:
    assert normalize({**BASE, "country_eligibility": junk}).country_eligibility == "unrestricted"


def test_eligibility_is_part_of_the_change_hash() -> None:
    # Otherwise a merchant whose shipping data starts arriving would keep the
    # stale value forever: the importer would see an unchanged hash and skip.
    unknown = normalize({**BASE, "country_eligibility": "unknown"})
    assert unknown.content_hash() != normalize(dict(BASE)).content_hash()


# ── the query the shopper actually runs ─────────────────────────────────────


def _where(country: str | None) -> str:
    where, _ = build_where(CatalogFilters(country=country), None)
    return where


def test_a_country_filter_asks_the_one_shared_function() -> None:
    # Rather than a clause spelled out here and again in every other query that
    # asks the same question. The definition lives in migration 0064.
    assert "public.product_ships_to(" in _where("BD")


def test_no_country_asked_means_no_country_clause() -> None:
    # A user who has not told us where they are still sees the catalog.
    assert "product_ships_to" not in _where(None)


def test_the_contradiction_check_no_longer_hides_unknown_products() -> None:
    # The "deliverable to somebody" clause exists to catch a product listing
    # countries its merchant will not ship to — two positive claims that
    # disagree. A product that makes no claim has nothing to contradict, and
    # dropping it here would hide it from every user without a country set.
    where = _where(None)
    assert "p.country_eligibility <> 'listed'" in where


def test_an_empty_availability_array_is_no_longer_a_wildcard_in_sql() -> None:
    # The old clause `$1 = any(p.country_availability) or p.country_availability = '{}'`
    # is precisely the bug: it passed every unknown-shipping product for every
    # country on earth. It must not come back.
    where = _where("BD")
    assert "p.country_availability = '{}'" not in where
    assert "m.shipping_countries = '{}'" not in where.split("product_ships_to")[1]


# ── the seam between the adapter and the normalizer ─────────────────────────
#
# The adapter and the normalizer were each correct and each tested. The field
# was lost BETWEEN them, and nothing looked there — so a network product went in
# as `unrestricted` and satisfied every country filter with no shipping evidence
# whatsoever. These tests exercise the composed pipeline in production's order,
# because that is the only place the defect was visible.


def test_the_adapters_unknown_survives_mapping() -> None:
    from app.services.catalog.mapping import apply_mapping
    from app.services.catalog.networks.awin_adapter import awin_row_to_canonical

    row = {
        "merchant_product_id": "1005001382060076",
        "product_name": "Cotton tee",
        "search_price": "32.48",
        "currency": "CNY",
        "merchant_image_url": "https://cdn.example.test/a.jpg",
        "aw_deep_link": "https://www.awin1.com/pclick.php?p=1",
    }
    # The production config for the Awin merchant: prices in major units, which
    # is what takes apply_mapping off its identity shortcut and through the
    # field-copy that dropped the key.
    config = {"price_format": "major", "default_currency": "", "field_map": {}, "stock_map": {}}

    canonical = awin_row_to_canonical(row)
    assert canonical["country_eligibility"] == "unknown"

    mapped = apply_mapping(canonical, config)
    assert mapped.get("country_eligibility") == "unknown", (
        "apply_mapping dropped country_eligibility; the normalizer will then "
        "default it to 'unrestricted'"
    )

    product = normalize(mapped)
    assert product.country_eligibility == "unknown"
    assert product.price_minor == 3248  # major -> integer minor still correct


def test_a_feed_that_says_nothing_is_still_unrestricted() -> None:
    # The fix must not change the hand-curated catalog, where an absent key has
    # always meant "no restriction".
    from app.services.catalog.mapping import apply_mapping

    config = {"price_format": "major", "default_currency": "", "field_map": {}, "stock_map": {}}
    mapped = apply_mapping(dict(BASE), config)
    assert normalize(mapped).country_eligibility == "unrestricted"


def test_country_eligibility_is_a_mappable_field() -> None:
    # It is part of the canonical shape, so a field_map naming it is a valid
    # map, not a typo.
    from app.services.catalog.mapping import validate_field_map

    assert validate_field_map({"country_eligibility": "ships"}) == []
