"""Product ingestion: normalization, the change-detection hash, and the rules
that decide what a feed is allowed to say.

The database-level proofs (idempotency, deactivation, restore) are exercised
against real Postgres in DEV; what is asserted here is everything provable
without one — and in particular the hash, because "a second run changes
nothing" rests entirely on it.
"""

from __future__ import annotations

import pytest

from app.services.catalog.models import MAX_RUN_ERRORS, FeedProduct, SyncOutcome
from app.services.catalog.normalize import (
    FeedRecordError,
    normalize,
    resolve_rights,
    resolve_tryon,
    usable_image_url,
)
from app.services.catalog.sync import _backoff_minutes

BASE = {
    "external_id": "sku-1",
    "title": "Silk blouse",
    "price_minor": 89900,
    "currency": "bdt",
    "image_urls": ["https://cdn.example.test/a.jpg"],
}


# ── normalization ───────────────────────────────────────────────────────────


def test_a_minimal_record_normalizes() -> None:
    p = normalize(dict(BASE))
    assert p.external_id == "sku-1"
    assert p.currency == "BDT"  # uppercased to ISO-4217
    assert p.price_minor == 89900


@pytest.mark.parametrize("missing", ["external_id", "title", "price_minor", "currency"])
def test_a_record_without_an_identity_or_a_price_is_refused(missing: str) -> None:
    raw = dict(BASE)
    raw.pop(missing)
    with pytest.raises(FeedRecordError):
        normalize(raw)


def test_a_float_price_is_refused_rather_than_rounded() -> None:
    # 19.99 in a feed is ambiguous — cents, or a rounding artifact? The catalog's
    # money contract is integer minor units, and guessing is how a price drifts
    # into one the retailer does not honour.
    with pytest.raises(FeedRecordError, match="float"):
        normalize({**BASE, "price_minor": 19.99})


def test_an_original_price_that_is_not_a_discount_is_dropped() -> None:
    # A struck-through price that is lower than the real one insults the reader.
    p = normalize({**BASE, "original_price_minor": 50000})
    assert p.original_price_minor is None
    assert normalize({**BASE, "original_price_minor": 99900}).original_price_minor == 99900


@pytest.mark.parametrize(
    "url",
    [
        "not-a-url",
        "/relative/path.jpg",
        "data:image/png;base64,iVBOR",
        "file:///etc/passwd",
        "javascript:alert(1)",
        "",
    ],
)
def test_unusable_image_urls_never_enter_the_catalog(url: str) -> None:
    # The same rule the app applies client-side. Dropped at IMPORT so it can
    # never reach a product card or be sent to a paid render.
    assert usable_image_url(url) is False
    assert normalize({**BASE, "image_urls": [url]}).image_urls == []


def test_image_order_is_preserved_because_the_first_one_is_the_try_on_source() -> None:
    urls = ["https://a.test/2.jpg", "https://a.test/1.jpg", "https://a.test/2.jpg"]
    assert normalize({**BASE, "image_urls": urls}).image_urls == [
        "https://a.test/2.jpg",
        "https://a.test/1.jpg",
    ]


def test_country_codes_are_normalized_and_junk_dropped() -> None:
    p = normalize({**BASE, "country_availability": ["bd", "US", "bad", "jp", 7]})
    assert p.country_availability == ["BD", "JP", "US"]


def test_one_malformed_variant_does_not_lose_the_product() -> None:
    p = normalize(
        {
            **BASE,
            "variants": [
                {"external_id": "v1", "price_minor": 100},
                {"external_id": "v2", "price_minor": 1.5},  # bad
                {"price_minor": 100},  # no id
            ],
        }
    )
    assert [v.external_id for v in p.variants] == ["v1"]


# ── the change-detection hash ───────────────────────────────────────────────


def test_the_same_payload_hashes_the_same() -> None:
    assert normalize(dict(BASE)).content_hash() == normalize(dict(BASE)).content_hash()


def test_key_and_list_ORDER_do_not_change_the_hash() -> None:
    # A paginated feed may hand back sizes/colours in a different order every
    # time. If that moved the hash, every run would rewrite the whole catalog
    # and `last_synced_at` would stop meaning anything.
    a = normalize({**BASE, "sizes": ["S", "M"], "colors": ["red", "blue"]})
    b = normalize({**BASE, "colors": ["blue", "red"], "sizes": ["M", "S"]})
    assert a.content_hash() == b.content_hash()


@pytest.mark.parametrize(
    "change",
    [
        {"price_minor": 79900},
        {"title": "Silk blouse v2"},
        {"stock_status": "out_of_stock"},
        {"image_urls": ["https://cdn.example.test/b.jpg"]},
    ],
)
def test_a_real_change_moves_the_hash(change: dict) -> None:
    assert normalize(dict(BASE)).content_hash() != normalize({**BASE, **change}).content_hash()


# ── rights + try-on readiness ───────────────────────────────────────────────


def test_rights_come_from_merchant_config_not_from_the_feed() -> None:
    # A merchant asserting per-row that it holds image rights is exactly the
    # claim that needs a human behind it.
    assert resolve_rights("licensed") == "licensed"
    assert resolve_rights("anything-else") == "unknown"
    assert resolve_rights("") == "unknown"


def test_a_feed_cannot_declare_itself_try_on_ready_without_cleared_rights() -> None:
    product = normalize({**BASE, "try_on_status": "ready"})
    status, image = resolve_tryon(product, "unknown")
    assert (status, image) == ("unsupported", None)


def test_a_feed_cannot_declare_ready_with_no_usable_image() -> None:
    # `ready` with nothing to send is the dead tap the app already refuses to
    # draw; it must not be representable in the first place.
    product = normalize({**BASE, "image_urls": ["nonsense"], "try_on_status": "ready"})
    assert resolve_tryon(product, "licensed") == ("unsupported", None)


def test_ready_with_rights_and_an_image_resolves_to_the_first_image() -> None:
    product = normalize({**BASE, "try_on_status": "ready"})
    assert resolve_tryon(product, "licensed") == ("ready", "https://cdn.example.test/a.jpg")


def test_pending_stays_pending() -> None:
    product = normalize({**BASE, "try_on_status": "pending"})
    status, _ = resolve_tryon(product, "licensed")
    assert status == "pending"


def test_an_unknown_try_on_value_is_not_ready() -> None:
    product = normalize({**BASE, "try_on_status": "definitely-ready-trust-me"})
    assert resolve_tryon(product, "licensed") == ("unsupported", None)


# ── backoff + error bounding ────────────────────────────────────────────────


def test_backoff_grows_and_is_capped() -> None:
    # A feed failing for a day is not fixed by asking again in five minutes; the
    # cap keeps a recovered feed from waiting a week.
    assert _backoff_minutes(1) == 15
    assert _backoff_minutes(2) == 30
    assert _backoff_minutes(3) == 60
    assert _backoff_minutes(50) == 12 * 60


def test_run_errors_are_bounded() -> None:
    # The 26th identical 'missing price' is not new information, and the run
    # summary has to stay readable at 3am.
    outcome = SyncOutcome("run", "running")
    for i in range(MAX_RUN_ERRORS + 20):
        outcome.add_error(f"sku-{i}", "missing price")
    assert len(outcome.errors) == MAX_RUN_ERRORS


def test_a_feed_product_hash_is_stable_across_instances() -> None:
    a = FeedProduct(external_id="x", title="t", price_minor=1, currency="USD")
    b = FeedProduct(external_id="x", title="t", price_minor=1, currency="USD")
    assert a.content_hash() == b.content_hash()
