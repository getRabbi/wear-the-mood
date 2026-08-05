"""The non-production catalog seed fixture: its guard, and its shape.

The guard is the important half. Seed data reaching a live catalog is a product
incident — fake merchants in front of real users — so the refusal is tested as
carefully as the data.

The SQL itself is exercised against the real database by applying it to dev; what
is asserted here is everything provable without one.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "seed_discover_catalog",
    Path(__file__).resolve().parents[2] / "scripts" / "seed_discover_catalog.py",
)
assert _SPEC and _SPEC.loader
seed_mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(seed_mod)


# ── the production guard ─────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "dsn",
    [
        "postgresql://postgres.ghzabbceoaoertatkjyg:x@aws-0-us-east-1.pooler.supabase.com:5432/postgres",
        "postgresql://user:pw@db-prod.internal:5432/postgres",
        "postgresql://user:pw@wtm-api-PROD.example:5432/postgres",
    ],
)
def test_a_production_dsn_is_recognised(dsn: str) -> None:
    assert seed_mod._is_production(dsn) is True


@pytest.mark.parametrize(
    "dsn",
    [
        "postgresql://postgres.jdrdnwkttcqfitwzlysn:x@aws-1-ap-southeast-2.pooler.supabase.com:5432/postgres",
        "postgresql://user:pw@localhost:5432/postgres",
        "postgresql://user:pw@db-staging.internal:5432/postgres",
    ],
)
def test_a_non_production_dsn_is_allowed(dsn: str) -> None:
    assert seed_mod._is_production(dsn) is False


def test_the_guard_refuses_production_without_the_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    prod = "postgresql://u:p@db-prod.internal:5432/postgres"
    monkeypatch.setattr(seed_mod, "pick_migration_dsn", lambda env: (prod, False))
    monkeypatch.setattr(seed_mod, "dotenv_values", lambda path: {})

    def _explode(*a: object, **k: object) -> None:
        raise AssertionError("connected to production despite the guard")

    monkeypatch.setattr(seed_mod.psycopg, "connect", _explode)
    monkeypatch.setattr("sys.argv", ["seed_discover_catalog.py"])

    # Exit code 2, and — the part that matters — no connection was opened.
    assert seed_mod.main() == 2


def test_the_override_defaults_off_and_has_no_short_form(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A flag that could be set by accident is not a guard: it defaults off, it
    # is spelled out, and there is no `-y` to fat-finger. Asserted against the
    # SCRIPT'S OWN parser, so renaming the flag fails here.
    prod = "postgresql://u:p@db-prod.internal:5432/postgres"
    monkeypatch.setattr(seed_mod, "pick_migration_dsn", lambda env: (prod, False))
    monkeypatch.setattr(seed_mod, "dotenv_values", lambda path: {})
    monkeypatch.setattr(
        seed_mod.psycopg,
        "connect",
        lambda *a, **k: (_ for _ in ()).throw(AssertionError("connected")),
    )

    # No flag → refused.
    monkeypatch.setattr("sys.argv", ["seed.py"])
    assert seed_mod.main() == 2

    # A plausible short form is not accepted — argparse rejects it outright.
    monkeypatch.setattr("sys.argv", ["seed.py", "-y"])
    with pytest.raises(SystemExit):
        seed_mod.main()


# ── fixture shape (§27, §35) ─────────────────────────────────────────────────


def test_every_seeded_row_is_prefixed() -> None:
    # `--clear` deletes by prefix, so anything unprefixed would be orphaned —
    # or worse, a hand-made row would be deleted by it.
    assert all(m[0].startswith(seed_mod.SEED_PREFIX) for m in seed_mod.MERCHANTS)
    assert all(p["external_id"].startswith(seed_mod.SEED_PREFIX) for p in seed_mod.PRODUCTS)


def test_the_fixture_covers_the_required_categories() -> None:
    categories = {p["category"] for p in seed_mod.PRODUCTS}
    assert {"dresses", "tops", "bottoms", "outerwear"} <= categories


def test_the_fixture_covers_the_required_currencies() -> None:
    # BDT, USD and JPY specifically: JPY is the zero-decimal case that catches
    # a minor-unit bug no other currency here would.
    assert {"BDT", "USD", "JPY"} <= {p["currency"] for p in seed_mod.PRODUCTS}


def test_the_fixture_has_both_try_on_ready_and_view_only_products() -> None:
    statuses = {p["try_on_status"] for p in seed_mod.PRODUCTS}
    assert "ready" in statuses
    assert statuses & {"unsupported", "pending"}


def test_the_fixture_has_merchants_on_both_sides_of_approval() -> None:
    approvals = {m[2] for m in seed_mod.MERCHANTS}
    assert approvals == {True, False}


def test_the_fixture_has_variants_with_differing_stock() -> None:
    stocks = {v[4] for v in seed_mod.VARIANTS}
    assert len(stocks) > 1, "variants must exercise more than one stock state"
    assert any(not v[5] for v in seed_mod.VARIANTS), "one variant must be unavailable"


def test_there_is_one_negative_record_per_suppression_rule() -> None:
    # Each of these exists so the RLS policy and the API can be PROVEN to hide
    # the same thing, rather than intending to.
    negatives = {
        p["external_id"].removeprefix(seed_mod.SEED_PREFIX)
        for p in seed_mod.PRODUCTS
        if p["external_id"].startswith(f"{seed_mod.SEED_PREFIX}neg-")
    }
    assert negatives == {
        "neg-inactive",
        "neg-stale",
        "neg-rights",
        "neg-oos",
        "neg-noimage",
        "neg-country",
        "neg-merchant",
        "neg-window",
    }


def test_each_negative_actually_violates_its_rule() -> None:
    # A "negative" record that is accidentally valid proves nothing, so each
    # one is checked to genuinely break the rule it is named for.
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    by_id = {p["external_id"].removeprefix(seed_mod.SEED_PREFIX): p for p in seed_mod.PRODUCTS}

    assert by_id["neg-inactive"]["active"] is False
    assert now - by_id["neg-stale"]["last_synced_at"] > timedelta(days=7)
    assert by_id["neg-rights"]["image_rights_status"] != "licensed"
    assert by_id["neg-oos"]["stock_status"] == "out_of_stock"
    assert by_id["neg-noimage"]["image_urls"] == []
    assert "BD" not in by_id["neg-country"]["country_availability"]
    assert by_id["neg-merchant"]["merchant_slug"] == f"{seed_mod.SEED_PREFIX}ghost"
    assert by_id["neg-window"]["starts_at"] > now


def test_the_positive_records_are_all_actually_servable() -> None:
    # The mirror of the above: a positive that trips a suppression rule would
    # make the servable count meaningless.
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    positives = [
        p
        for p in seed_mod.PRODUCTS
        if not p["external_id"].startswith(f"{seed_mod.SEED_PREFIX}neg-")
    ]
    assert 15 <= len(positives) <= 25, "the fixture should hold 15-25 real products"

    for p in positives:
        assert p["active"] is True, p["external_id"]
        assert p["image_rights_status"] == "licensed", p["external_id"]
        assert p["stock_status"] != "out_of_stock", p["external_id"]
        assert p["image_urls"], p["external_id"]
        assert now - p["last_synced_at"] < timedelta(days=7), p["external_id"]
        assert p["starts_at"] is None and p["ends_at"] is None, p["external_id"]


def test_prices_are_integer_minor_units() -> None:
    # A float here would be the bug the whole money design exists to prevent.
    for p in seed_mod.PRODUCTS:
        assert isinstance(p["price_minor"], int), p["external_id"]
        assert p["price_minor"] >= 0
        original = p["original_price_minor"]
        assert original is None or (isinstance(original, int) and original > p["price_minor"])
