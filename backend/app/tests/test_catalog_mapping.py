"""Per-merchant feed mapping.

Written after pointing the importer at a real feed for the first time, which
skipped 100% of records: `id` was an integer, `price` a float in major units,
and there was no currency field at all. The normalizer was right to refuse all
three — so the mapping layer exists to let a merchant DECLARE what its fields
mean, and these tests pin the conversions that declaration authorises.
"""

from __future__ import annotations

import pytest

from app.services.catalog.mapping import (
    apply_mapping,
    minor_unit_exponent,
    to_minor_units,
    validate_field_map,
)
from app.services.catalog.normalize import FeedRecordError, normalize

# The shape a real feed actually sends.
REAL_RECORD = {
    "id": 1,
    "title": "Essence Mascara Lash Princess",
    "description": "A mascara.",
    "brand": "Essence",
    "category": "beauty",
    "price": 9.99,
    "stock": 99,
    "images": ["https://cdn.example.test/a.webp"],
}
CONFIG = {
    "field_map": {
        "external_id": "id",
        "title": "title",
        "description": "description",
        "brand": "brand",
        "category": "category",
        "price_minor": "price",
        "image_urls": "images",
        "stock_status": "stock",
    },
    "price_format": "major",
    "default_currency": "USD",
    "stock_map": {"low_stock_at": 10},
}


def test_an_unmapped_feed_is_passed_through_untouched() -> None:
    # A merchant already speaking the canonical shape must be unaffected by the
    # existence of this layer.
    canonical = {"external_id": "a", "title": "t", "price_minor": 100, "currency": "USD"}
    assert apply_mapping(canonical, {}) is canonical


def test_the_real_record_becomes_importable() -> None:
    mapped = apply_mapping(REAL_RECORD, CONFIG)
    product = normalize(mapped)  # would previously raise
    assert product.external_id == "1"
    assert product.price_minor == 999
    assert product.currency == "USD"
    assert product.stock_status == "in_stock"
    assert product.image_urls == ["https://cdn.example.test/a.webp"]


def test_an_integer_id_becomes_the_string_key_the_catalog_uses() -> None:
    assert apply_mapping({"id": 42}, {"field_map": {"external_id": "id"}})["external_id"] == "42"


# ── money ───────────────────────────────────────────────────────────────────


def test_major_units_convert_in_decimal_not_binary_float() -> None:
    # 9.99 * 100 in binary float is 998.9999999999999, and int() of that is 998
    # — one cent lost per product, every sync, forever.
    assert to_minor_units(9.99, "USD") == 999
    assert to_minor_units("9.99", "USD") == 999
    assert to_minor_units(0.07, "USD") == 7
    assert to_minor_units(1234.56, "USD") == 123456


@pytest.mark.parametrize(
    ("currency", "exponent"), [("USD", 2), ("BDT", 2), ("JPY", 0), ("KRW", 0), ("KWD", 3)]
)
def test_the_currency_exponent_is_respected(currency: str, exponent: int) -> None:
    # Scaling JPY by 100 would multiply every Japanese price by a hundred.
    assert minor_unit_exponent(currency) == exponent


def test_a_zero_decimal_currency_is_not_scaled() -> None:
    assert to_minor_units(9800, "JPY") == 9800


def test_an_unparseable_price_is_left_for_the_normalizer_to_refuse() -> None:
    # Not silently zeroed: a price of 0 is a claim, and a wrong one.
    mapped = apply_mapping({"id": 1, "price": "abc"}, CONFIG)
    assert mapped["price_minor"] == "abc"
    with pytest.raises(FeedRecordError, match="price_minor"):
        normalize({**mapped, "title": "t"})


def test_a_negative_price_is_refused() -> None:
    assert to_minor_units(-5, "USD") is None


# ── stock ───────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("count", "expected"),
    [(0, "out_of_stock"), (1, "low_stock"), (10, "low_stock"), (11, "in_stock"), (99, "in_stock")],
)
def test_a_stock_count_becomes_a_status(count: int, expected: str) -> None:
    mapped = apply_mapping({"id": 1, "stock": count}, CONFIG)
    assert mapped["stock_status"] == expected


def test_a_label_feed_is_translated_by_declared_values() -> None:
    config = {
        "field_map": {"stock_status": "availability"},
        "stock_map": {"values": {"sold out": "out_of_stock", "in stock": "in_stock"}},
    }
    assert apply_mapping({"availability": "Sold Out"}, config)["stock_status"] == "out_of_stock"


def test_a_boolean_availability_is_understood() -> None:
    config = {"field_map": {"stock_status": "available"}, "stock_map": {}}
    assert apply_mapping({"available": False}, config)["stock_status"] == "out_of_stock"


def test_a_count_without_a_threshold_is_not_invented() -> None:
    # Passed through, so the normalizer falls back to `unknown` — honest rather
    # than a guess about what "7 in stock" means to this merchant.
    config = {"field_map": {"stock_status": "stock"}, "stock_map": {}}
    assert apply_mapping({"stock": 7}, config)["stock_status"] == 7
    assert (
        normalize(
            {
                "external_id": "a",
                "title": "t",
                "price_minor": 1,
                "currency": "USD",
                "stock_status": 7,
            }
        ).stock_status
        == "unknown"
    )


# ── nested paths + typos ────────────────────────────────────────────────────


def test_a_dotted_path_reads_nested_json() -> None:
    config = {"field_map": {"external_id": "meta.sku"}}
    assert apply_mapping({"meta": {"sku": "ABC"}}, config)["external_id"] == "ABC"


def test_a_missing_nested_path_is_absent_not_an_error() -> None:
    config = {"field_map": {"external_id": "meta.sku"}}
    assert "external_id" not in apply_mapping({"meta": {}}, config)


def test_a_typo_in_a_field_map_is_reported() -> None:
    # A misspelled canonical name maps nothing, which looks exactly like a feed
    # that changed shape. The run says so instead.
    assert validate_field_map({"external_id": "id", "titel": "title"}) == ["titel"]
    assert validate_field_map({"external_id": "id"}) == []


def test_a_single_image_string_becomes_a_list() -> None:
    config = {"field_map": {"image_urls": "thumbnail"}, "price_format": "major"}
    assert apply_mapping({"thumbnail": "https://x.test/a.png"}, config)["image_urls"] == [
        "https://x.test/a.png"
    ]
