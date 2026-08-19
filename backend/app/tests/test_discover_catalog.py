"""Discover catalog — cursors, eligibility, money, flag gating and idempotency.

The pure rules (cursor encoding, filter construction, match reasons) are tested
directly. The routes are tested against a fake connection, like the rest of the
suite, so the SQL that is actually sent can be asserted — which is the only way
to prove a hard filter is present rather than merely intended.
"""

from __future__ import annotations

import time
from datetime import UTC, datetime

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.discover.catalog import (
    RANKING_WEIGHTS,
    STAGE_FILTERS,
    STAGE_PREFERENCES,
    STAGE_PRODUCT_STATE,
    STAGE_REGION,
    CatalogFilters,
    Cursor,
    InvalidCursor,
    build_funnel_sql,
    build_stages,
    build_where,
    clamp_limit,
    facet_label,
    match_reason_for,
    normalize_country,
    normalize_currency,
)

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": "u1",
            "aud": "authenticated",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


# ── fake connection ──────────────────────────────────────────────────────────


class _Conn:
    def __init__(self, handlers: list[tuple[str, str, object]]) -> None:
        self.handlers = handlers
        self.calls: list[tuple[str, str, tuple]] = []

    def _dispatch(self, method: str, sql: str, args: tuple) -> object:
        flat = " ".join(sql.split())
        self.calls.append((method, flat, args))
        for m, frag, value in self.handlers:
            if m == method and frag in flat:
                return value(flat, args) if callable(value) else value
        # The real limiter's SQL function answers true under the limit, so an
        # unstubbed rate-limit check must ALLOW. Returning None here would make
        # every limited route 429 for reasons unrelated to the test.
        if "app_rate_limit" in flat:
            return True
        return "UPDATE 0" if method == "execute" else None

    async def fetchrow(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchrow", sql, args)

    async def fetchval(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchval", sql, args)

    async def fetch(self, sql: str, *args: object) -> object:
        return self._dispatch("fetch", sql, args) or []

    async def execute(self, sql: str, *args: object) -> object:
        return self._dispatch("execute", sql, args)

    def sql_calls(self, fragment: str) -> list[tuple[str, str, tuple]]:
        return [c for c in self.calls if fragment in c[1]]


class _Acquire:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _Conn:
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self) -> _Acquire:
        return _Acquire(self.conn)


def _wire(monkeypatch: pytest.MonkeyPatch, conn: _Conn) -> None:
    import app.routers.v1.discover as mod

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))


def _flag(enabled: bool = True) -> tuple[str, str, object]:
    return ("fetchval", "from public.feature_flags", enabled)


_ROW = {
    "id": "11111111-1111-1111-1111-111111111111",
    "title": "Black silk dress",
    "brand": "Studio Label",
    "description": "A dress.",
    "category": "dresses",
    "subcategory": "evening",
    "price_minor": 349900,
    "original_price_minor": 499900,
    "currency": "BDT",
    "image_urls": ["https://cdn.test/dress.jpg"],
    "image_focal_x": 0.5,
    "image_focal_y": 0.35,
    "colors": ["black"],
    "sizes": ["M"],
    "stock_status": "in_stock",
    "try_on_status": "ready",
    # Derived by the query, not stored: `known` is a hand-curated product whose
    # shipping we can speak to. A network product answers `unknown` and the
    # client says so in words rather than implying coverage.
    "shipping_availability": "known",
    "sponsored": False,
    "last_synced_at": datetime(2026, 8, 5, tzinfo=UTC),
    "created_at": datetime(2026, 8, 5, tzinfo=UTC),
    "merchant_id": "22222222-2222-2222-2222-222222222222",
    "merchant_name": "Studio Label",
    "merchant_logo": None,
}


# ── auth + flag gate ─────────────────────────────────────────────────────────


def test_every_route_requires_a_token() -> None:
    assert client.get("/v1/discover/products").status_code == 401
    assert client.get("/v1/discover/saved").status_code == 401
    assert client.put("/v1/discover/saved/x").status_code == 401
    assert client.post("/v1/discover/interactions", json={"event_type": "open"}).status_code == 401


def test_shopping_off_serves_nothing_even_to_an_authenticated_client(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The flag is enforced SERVER-side, so an older or modified client that
    # keeps calling still gets nothing (§14, §30).
    conn = _Conn([_flag(False)])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/products", headers=_auth()).status_code == 404
    assert conn.sql_calls("from public.products") == []


def test_shopping_flag_defaults_off_when_no_row_exists(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # No feature_flags row at all → the fake returns None → default False.
    conn = _Conn([])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/products", headers=_auth()).status_code == 404


# ── cursors ──────────────────────────────────────────────────────────────────


def test_cursor_round_trips() -> None:
    original = Cursor(created_at=datetime(2026, 8, 5, 12, 30, tzinfo=UTC), product_id="abc")
    assert Cursor.decode(original.encode()) == original


def test_cursor_is_url_safe_and_unpadded() -> None:
    encoded = Cursor(created_at=datetime.now(UTC), product_id="abc").encode()
    assert "=" not in encoded and "+" not in encoded and "/" not in encoded


@pytest.mark.parametrize("bad", ["", "!!!!", "Zm9vYmFy", "eyJ0IjoxfQ"])
def test_a_malformed_cursor_is_rejected_not_reset(bad: str) -> None:
    # Silently restarting at page 1 would loop the user through the same
    # products forever; a clean error is recoverable.
    with pytest.raises(InvalidCursor):
        Cursor.decode(bad)


def test_a_bad_cursor_is_a_400_not_a_500(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.get("/v1/discover/products?cursor=!!!not-a-cursor", headers=_auth())
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


# ── hard filters (§19.1) ─────────────────────────────────────────────────────


def test_servability_is_always_required() -> None:
    where, _ = build_where(CatalogFilters(), None)
    # Active, in-window, in-stock, rights-cleared, image present and freshly
    # synced all live in this one function so RLS and the API cannot drift.
    assert "public.product_is_servable(p)" in where
    assert "m.approved" in where


def test_country_filters_on_availability_and_shipping() -> None:
    where, params = build_where(CatalogFilters(country="BD"), None)
    assert "country_availability" in where
    # A product listed for a country the merchant will not ship to is not
    # available there (§34).
    assert "m.shipping_countries" in where
    assert "BD" in params


def test_an_undeliverable_product_is_excluded_even_with_no_country() -> None:
    # A brand-new user has no shopping country, so the country clause above
    # never runs for them. A product listing only countries its merchant will
    # not ship to can be bought by nobody, and must not reach that user's feed
    # — otherwise Product Details opens saying it ships nowhere while the Shop
    # button still works (§34, §35).
    where, _ = build_where(CatalogFilters(), None)
    assert "p.country_availability && m.shipping_countries" in where
    # An unverified merchant is still "unrestricted" here: this clause detects a
    # contradiction between two positive claims, not a missing one.
    assert "m.shipping_countries = '{}'" in where
    # And it only judges products that made a claim. One whose shipping is
    # unknown has nothing to contradict, and excluding it here would hide it
    # from every user who has not set a country — see 0064.
    assert "p.country_eligibility <> 'listed'" in where


def test_try_on_ready_filters_on_the_database_gate() -> None:
    """The filter asks `product_tryon_ready`, not the bare column.

    Readiness is three conditions — an earned `ready` status, licensed image
    rights, and a usable image — and 0065 states them in one place so the RLS
    policy, the API and the filter cannot drift. Filtering on the column alone
    returned rows the feed then serialized as `unsupported`, i.e. a filter that
    contradicted its own results.
    """
    where, _ = build_where(CatalogFilters(try_on_ready=True), None)
    assert "public.product_tryon_ready(p)" in where
    # 'pending' is still not ready, and nothing here reintroduces it.
    assert "pending" not in where


def test_cursor_clause_is_a_strict_keyset_comparison() -> None:
    cursor = Cursor(created_at=datetime(2026, 8, 5, tzinfo=UTC), product_id="abc")
    where, params = build_where(CatalogFilters(), cursor)
    assert "(p.created_at, p.id) <" in where
    assert cursor.created_at in params and "abc" in params


def test_hidden_merchants_are_excluded() -> None:
    where, params = build_where(CatalogFilters(), None, hidden_merchant_ids=["m1"])
    assert "not (p.merchant_id = any(" in where
    assert ["m1"] in params


def test_filters_are_parameterized_never_interpolated() -> None:
    # The one place a catalog API gets injected. Every user value must arrive
    # as a bound parameter, not inside the SQL string.
    evil = "'; drop table public.products; --"
    where, params = build_where(CatalogFilters(category=evil, search=evil), None)
    assert evil not in where
    assert evil in params
    assert f"%{evil}%" in params


def test_active_filter_count_drives_the_compact_indicator() -> None:
    assert CatalogFilters().active_count == 0
    assert CatalogFilters(category="dresses", try_on_ready=True).active_count == 2
    # A price range is ONE filter however many bounds it has.
    assert CatalogFilters(min_price_minor=0, max_price_minor=500000).active_count == 1


# ── normalization ────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("bd", "BD"), (" BD ", "BD"), ("BGD", None), ("B1", None), ("", None), (None, None)],
)
def test_country_normalization(raw: str | None, expected: str | None) -> None:
    assert normalize_country(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("bdt", "BDT"), ("USD", "USD"), ("US", None), ("US1", None), (None, None)],
)
def test_currency_normalization(raw: str | None, expected: str | None) -> None:
    assert normalize_currency(raw) == expected


def test_page_size_is_clamped() -> None:
    assert clamp_limit(None) == 20
    assert clamp_limit(0) == 1
    assert clamp_limit(9999) == 50


# ── ranking ──────────────────────────────────────────────────────────────────


def test_ranking_weights_sum_to_one() -> None:
    # A weight change should be a visible trade-off, not a quiet inflation.
    assert abs(sum(RANKING_WEIGHTS.values()) - 1.0) < 1e-9


def test_match_reason_prefers_the_most_specific() -> None:
    row = {"category": "Dresses", "price_minor": 100, "original_price_minor": 200}
    # Closet beats everything: "matches your closet" is the most actionable
    # thing we can say.
    assert (
        match_reason_for(row, closet_categories={"dresses"}, favorite_categories={"dresses"})
        == "closet_match"
    )
    assert match_reason_for(row, favorite_categories={"dresses"}) == "style_match"
    assert match_reason_for(row) == "price_drop"


def test_match_reason_is_none_rather_than_invented() -> None:
    # No reason at all beats a generic one the user cannot act on (§8.1).
    assert match_reason_for({"category": "shoes", "price_minor": 100}) is None


def test_match_reason_returns_a_code_never_display_text() -> None:
    # §37.2: the client localizes; the server never sends prose.
    reason = match_reason_for({"category": "d", "price_minor": 1}, closet_categories={"d"})
    assert reason == "closet_match"
    assert " " not in reason


# ── responses ────────────────────────────────────────────────────────────────


def test_products_are_returned_with_money_as_minor_units(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn([_flag(), ("fetch", "from public.products p", [_ROW])])
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/products", headers=_auth()).json()

    item = body["items"][0]
    assert item["price"] == {"amount_minor": 349900, "currency": "BDT"}
    assert item["original_price"] == {"amount_minor": 499900, "currency": "BDT"}
    # Never a float and never a pre-formatted string with a symbol in it.
    assert isinstance(item["price"]["amount_minor"], int)


def test_no_affiliate_url_or_reference_reaches_the_client(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Safety rule 11 / §18: the app must never receive a retailer link it could
    # open unvalidated.
    conn = _Conn([_flag(), ("fetch", "from public.products p", [_ROW])])
    _wire(monkeypatch, conn)
    raw = client.get("/v1/discover/products", headers=_auth()).text

    assert "affiliate" not in raw.lower()
    # The selected columns do not include it in the first place.
    feed_sql = conn.sql_calls("from public.products p")[0][1]
    assert "affiliate_ref" not in feed_sql


def test_next_cursor_appears_only_when_another_page_exists(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn([_flag(), ("fetch", "from public.products p", [_ROW])])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/products", headers=_auth()).json()["next_cursor"] is None

    # One more row than the page size means there IS a next page.
    rows = [dict(_ROW, id=f"{i:08d}-1111-1111-1111-111111111111") for i in range(3)]
    conn = _Conn([_flag(), ("fetch", "from public.products p", rows)])
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/products?limit=2", headers=_auth()).json()
    assert len(body["items"]) == 2
    assert body["next_cursor"] is not None


def test_the_page_carries_a_schema_version(monkeypatch: pytest.MonkeyPatch) -> None:
    # §37.4: older clients must be able to tell the shape apart.
    conn = _Conn([_flag(), ("fetch", "from public.products p", [_ROW])])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/products", headers=_auth()).json()["schema_version"] == 1


# ── saves ────────────────────────────────────────────────────────────────────


def test_saving_stores_the_server_side_price_not_a_client_claim(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # §38: never trust a client-supplied price. The price-drop comparison later
    # is only meaningful against a price we actually served.
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products where id", {"price_minor": 1000, "currency": "BDT"}),
        ]
    )
    _wire(monkeypatch, conn)
    resp = client.put(
        "/v1/discover/saved/11111111-1111-1111-1111-111111111111",
        json={"price_alert_enabled": True},
        headers=_auth(),
    )
    assert resp.status_code == 204

    insert = conn.sql_calls("insert into public.saved_products")[0]
    assert 1000 in insert[2] and "BDT" in insert[2]


def test_saving_is_idempotent(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products where id", {"price_minor": 1, "currency": "BDT"}),
        ]
    )
    _wire(monkeypatch, conn)
    client.put("/v1/discover/saved/11111111-1111-1111-1111-111111111111", headers=_auth())

    # The primary key turns a double-tap into one row.
    sql = conn.sql_calls("insert into public.saved_products")[0][1]
    assert "on conflict (user_id, product_id) do update" in sql


def test_saving_an_unknown_product_is_404(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products where id", None)])
    _wire(monkeypatch, conn)
    resp = client.put("/v1/discover/saved/11111111-1111-1111-1111-111111111111", headers=_auth())
    assert resp.status_code == 404
    assert conn.sql_calls("insert into public.saved_products") == []


def test_unsaving_something_already_gone_succeeds(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.delete("/v1/discover/saved/11111111-1111-1111-1111-111111111111", headers=_auth())
    assert resp.status_code == 204


def test_saved_list_keeps_unavailable_products(monkeypatch: pytest.MonkeyPatch) -> None:
    # §11.3: a saved product that sold out must show its state, not vanish.
    conn = _Conn(
        [
            _flag(),
            (
                "fetch",
                "from public.saved_products s",
                [
                    dict(
                        _ROW,
                        stock_status="out_of_stock",
                        saved_at=datetime(2026, 8, 1, tzinfo=UTC),
                        price_alert_enabled=True,
                        availability_alert_enabled=False,
                        saved_price_minor=499900,
                    )
                ],
            ),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/saved", headers=_auth()).json()

    assert body[0]["product"]["stock_status"] == "out_of_stock"
    # Price fell from what it was when saved — derived server-side.
    assert body[0]["price_dropped"] is True
    saved_sql = conn.sql_calls("from public.saved_products s")[0][1]
    assert "product_is_servable" not in saved_sql


# ── interactions ─────────────────────────────────────────────────────────────


def test_an_interaction_retry_cannot_double_count(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/discover/interactions",
        json={
            "product_id": "11111111-1111-1111-1111-111111111111",
            "event_type": "save",
            "feed_placement": "feed_grid",
            "client_event_id": "evt-1",
        },
        headers=_auth(),
    )
    assert resp.status_code == 204

    sql = conn.sql_calls("insert into public.product_interactions")[0][1]
    assert "on conflict (user_id, client_event_id)" in sql
    assert "do nothing" in sql


def test_an_unknown_interaction_type_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/discover/interactions",
        json={"event_type": "please_rank_me_first"},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert conn.sql_calls("insert into public.product_interactions") == []


# ── preferences ──────────────────────────────────────────────────────────────


def test_preferences_default_when_no_row_exists(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/preferences", headers=_auth()).json()
    assert body["personalization_enabled"] is True
    assert body["country"] is None


def test_an_invalid_country_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.put(
        "/v1/discover/preferences",
        json={"country": "XX1", "personalization_enabled": True},
        headers=_auth(),
    )
    # Pydantic's length bound catches it before the handler does; either way it
    # never reaches the database.
    assert resp.status_code in (400, 422)
    assert conn.sql_calls("insert into public.shopping_preferences") == []


def test_a_saved_country_overrides_a_query_parameter(monkeypatch: pytest.MonkeyPatch) -> None:
    # §34: the shopping region comes from the account, so a stale client cannot
    # silently move the user's feed to another country.
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "from public.shopping_preferences",
                {
                    "country": "BD",
                    "currency": "BDT",
                    "budget_min_minor": None,
                    "budget_max_minor": None,
                    "sizes": [],
                    "favorite_categories": [],
                    "avoided_colors": [],
                    "modest_preference": False,
                    "personalization_enabled": True,
                    "hidden_merchant_ids": [],
                    "updated_at": datetime(2026, 8, 1, tzinfo=UTC),
                },
            ),
            ("fetch", "from public.products p", [_ROW]),
        ]
    )
    _wire(monkeypatch, conn)
    client.get("/v1/discover/products?country=US", headers=_auth())

    feed_args = conn.sql_calls("from public.products p")[0][2]
    assert "BD" in feed_args
    assert "US" not in feed_args


# ── facets (§11.2) ───────────────────────────────────────────────────────────


def test_facets_require_the_shopping_flag(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(False)])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/facets", headers=_auth()).status_code == 404


def test_facets_are_derived_only_from_servable_products(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The whole point: a size or colour that exists only on expired, unlicensed,
    # out-of-stock or un-shippable products must never be offered as a filter.
    conn = _Conn([_flag(), ("fetchrow", "array_agg(distinct p.category)", None)])
    _wire(monkeypatch, conn)
    client.get("/v1/discover/facets", headers=_auth())

    sql = conn.sql_calls("array_agg(distinct p.category)")[0][1]
    assert "public.product_is_servable(p)" in sql
    assert "m.approved" in sql


def test_facets_are_country_aware(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "array_agg(distinct p.category)", None)])
    _wire(monkeypatch, conn)
    client.get("/v1/discover/facets?country=BD", headers=_auth())

    args = conn.sql_calls("array_agg(distinct p.category)")[0][2]
    assert "BD" in args


def test_facets_return_canonical_values_with_separate_labels(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # §37.2: the client localizes, so the value it filters on must not be the
    # text a human reads.
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "array_agg(distinct p.category)",
                {
                    "categories": ["evening_wear", "tops"],
                    "sizes": ["M", "L"],
                    "colors": ["black"],
                    "merchants": ["Atelier Noir|22222222-2222-2222-2222-222222222222"],
                    "min_price": 1000,
                    "max_price": 500000,
                    "currency_count": 1,
                    "currency": "BDT",
                    "try_on_available": True,
                    "discount_available": False,
                },
            ),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/facets", headers=_auth()).json()

    assert body["categories"][0] == {
        "value": "evening_wear",
        "label": "Evening Wear",
        "count": 0,
    }
    assert body["merchants"][0]["value"] == "22222222-2222-2222-2222-222222222222"
    assert body["merchants"][0]["label"] == "Atelier Noir"
    assert body["min_price"] == {"amount_minor": 1000, "currency": "BDT"}
    assert body["try_on_available"] is True
    assert body["discount_available"] is False


def test_facets_drop_price_bounds_when_a_region_mixes_currencies(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Comparing yen to taka without conversion is meaningless, so no bounds is
    # the honest answer.
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "array_agg(distinct p.category)",
                {
                    "categories": ["tops"],
                    "sizes": [],
                    "colors": [],
                    "merchants": [],
                    "min_price": 1000,
                    "max_price": 500000,
                    "currency_count": 3,
                    "currency": "BDT",
                    "try_on_available": False,
                    "discount_available": False,
                },
            ),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/facets", headers=_auth()).json()

    assert body["min_price"] is None
    assert body["max_price"] is None


def test_empty_facets_are_a_valid_answer(monkeypatch: pytest.MonkeyPatch) -> None:
    # A region with no catalog has no facets; the client falls back to its
    # curated list rather than showing an empty sheet (§24).
    conn = _Conn([_flag(), ("fetchrow", "array_agg(distinct p.category)", None)])
    _wire(monkeypatch, conn)
    resp = client.get("/v1/discover/facets", headers=_auth())

    assert resp.status_code == 200
    assert resp.json()["categories"] == []


def test_facet_labels_humanize_unknown_values() -> None:
    # A category this build has never seen still renders readably.
    assert facet_label("evening_wear") == "Evening Wear"
    assert facet_label("tops") == "Tops"
    assert facet_label("some_future_category") == "Some Future Category"


# ── cache-key inputs (§34) ───────────────────────────────────────────────────


def test_the_page_echoes_the_resolved_region_and_profile_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The app keys its offline cache on these; without them a cold start could
    # never match the key a page was written under.
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "from public.shopping_preferences",
                {
                    "country": "BD",
                    "currency": "BDT",
                    "budget_min_minor": None,
                    "budget_max_minor": None,
                    "sizes": [],
                    "favorite_categories": [],
                    "avoided_colors": [],
                    "modest_preference": False,
                    "personalization_enabled": True,
                    "hidden_merchant_ids": [],
                    "updated_at": datetime(2026, 8, 1, tzinfo=UTC),
                },
            ),
            ("fetch", "from public.products p", [_ROW]),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get("/v1/discover/products", headers=_auth()).json()

    assert body["country"] == "BD"
    assert body["currency"] == "BDT"
    assert body["profile_version"] == int(datetime(2026, 8, 1, tzinfo=UTC).timestamp())


def test_profile_version_is_zero_without_a_preferences_row(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn([_flag(), ("fetch", "from public.products p", [_ROW])])
    _wire(monkeypatch, conn)
    assert client.get("/v1/discover/products", headers=_auth()).json()["profile_version"] == 0


# ── shipping availability travels with the product ──────────────────────────


def test_a_product_reports_whether_shipping_is_known(monkeypatch: pytest.MonkeyPatch) -> None:
    # The client must not have to infer this from an empty array — "empty" is
    # exactly the ambiguity 0064 removed, and re-deriving it on the client would
    # put the bug back on the other side of the wire.
    conn = _Conn([_flag(), ("fetch", "from public.products", [dict(_ROW)])])
    _wire(monkeypatch, conn)
    r = client.get("/v1/discover/products", headers=_auth())
    assert r.status_code == 200
    assert r.json()["items"][0]["shipping_availability"] == "known"


def test_an_unknown_shipping_product_says_so(monkeypatch: pytest.MonkeyPatch) -> None:
    row = dict(_ROW)
    row["shipping_availability"] = "unknown"
    conn = _Conn([_flag(), ("fetch", "from public.products", [row])])
    _wire(monkeypatch, conn)
    r = client.get("/v1/discover/products", headers=_auth())
    assert r.status_code == 200
    product = r.json()["items"][0]
    assert product["shipping_availability"] == "unknown"
    # Still a normal, shoppable product — unknown delivery is a caveat, not a
    # suppression. Hiding it is what made the affiliate catalog empty.
    assert product["id"] == _ROW["id"]


# ── try-on eligibility is the DATABASE's answer, not the column's ────────────


def test_the_feed_asks_product_tryon_ready_for_eligibility() -> None:
    """The column alone is one of three conditions, and the API served it raw.

    `product_tryon_ready` (0065) also demands licensed image rights and a usable
    image, because feeding a picture to a paid generative render is a stronger
    permission than showing it beside an affiliate link. Serving the bare column
    let the two disagree in the expensive direction: a row still marked `ready`
    after its rights were downgraded would have drawn a TRY ON pill, and the app
    would have sent that image to the provider.
    """
    from app.routers.v1.discover import _PRODUCT_COLUMNS

    columns = " ".join(_PRODUCT_COLUMNS.split())
    assert "public.product_tryon_ready(p) then 'ready'" in columns
    assert "as try_on_status" in columns
    # `pending` is preserved as itself — "not yet" is not the same as "no".
    assert "p.try_on_status = 'pending' then 'pending'" in columns
    # And the bare column is no longer selected on its own.
    assert "p.try_on_status," not in columns


def test_an_ineligible_product_is_still_shown_just_not_tryable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The two gates stay separate (0065). A product nobody cleared for AI is a
    perfectly good thing to browse and buy — it simply carries no TRY ON."""
    row = dict(_ROW)
    row["try_on_status"] = "unsupported"
    conn = _Conn([_flag(), ("fetch", "from public.products", [row])])
    _wire(monkeypatch, conn)
    r = client.get("/v1/discover/products", headers=_auth())
    assert r.status_code == 200
    product = r.json()["items"][0]
    assert product["id"] == _ROW["id"], "display rights and AI rights are not the same gate"
    assert product["try_on_status"] == "unsupported"


def test_the_facets_try_on_chip_uses_the_same_gate() -> None:
    """A filter that is offered must be answerable. Deriving the chip from the
    bare column would advertise `Try-On Ready` for a catalog whose products the
    feed then serializes as `unsupported`."""
    import inspect

    import app.routers.v1.discover as discover_mod

    source = " ".join(inspect.getsource(discover_mod.facets).split())
    assert "bool_or(public.product_tryon_ready(p)) as try_on_available" in source


# ── ISSUE 4: a display preference must never empty the catalog ───────────────
#
# `shopping_preferences.currency` used to become `p.currency = $n`, a HARD
# filter. Nothing in the app writes that preference yet, so the defect was
# dormant rather than absent — the moment the settings screen shipped, a shopper
# who chose BDT would have been served an empty Discover against a USD catalog,
# with `region_empty=false` and no other explanation attached.


def test_currency_preference_is_not_a_hard_filter() -> None:
    where, params = build_where(CatalogFilters(currency="BDT"), None)
    assert "p.currency" not in where, (
        "a preferred display currency must not decide whether the catalog exists"
    )
    assert "BDT" not in params


def test_currency_does_not_change_the_candidate_set() -> None:
    # The whole point: two accounts differing ONLY in preferred currency get the
    # same products out of the same catalog.
    plain, plain_params = build_where(CatalogFilters(country="BD"), None)
    with_currency, currency_params = build_where(
        CatalogFilters(country="BD", currency="BDT"), None
    )
    assert plain == with_currency
    assert plain_params == currency_params


def test_currency_is_still_normalized_and_echoed() -> None:
    # It remains a real preference — parsed, validated and returned on the page
    # (and part of the offline cache key). It simply stops being a WHERE clause.
    assert normalize_currency("bdt") == "BDT"
    assert normalize_currency("nonsense") is None


def test_genuine_eligibility_filters_are_untouched() -> None:
    # Demoting currency must not weaken anything that is a real constraint.
    where, _ = build_where(CatalogFilters(country="BD", try_on_ready=True), None)
    assert "public.product_is_servable(p)" in where
    assert "m.approved" in where
    assert "public.product_ships_to(" in where
    assert "public.product_tryon_ready(p)" in where


# ── ISSUE 4: an empty section must be able to say why ────────────────────────


def test_stages_are_named_and_ordered() -> None:
    stages, _ = build_stages(CatalogFilters(country="BD"), None, hidden_merchant_ids=["m"])
    assert [s.name for s in stages] == [
        STAGE_PRODUCT_STATE,
        STAGE_REGION,
        STAGE_PREFERENCES,
        STAGE_FILTERS,
    ]


def test_stages_compose_exactly_the_page_where_clause() -> None:
    # The funnel is only trustworthy if it counts what the page query filtered
    # on. Building them from one source is what guarantees that.
    filters = CatalogFilters(country="BD", category="dresses", try_on_ready=True)
    stages, stage_params = build_stages(filters, None, hidden_merchant_ids=["m1"])
    where, where_params = build_where(filters, None, hidden_merchant_ids=["m1"])
    assert " and ".join(s.clause for s in stages) == where
    assert stage_params == where_params


def test_an_empty_stage_still_holds_its_place() -> None:
    stages, _ = build_stages(CatalogFilters(), None)
    by_name = {s.name: s.clause for s in stages}
    assert by_name[STAGE_PREFERENCES] == "true"
    assert by_name[STAGE_FILTERS] == "true"


def test_funnel_sql_is_cumulative() -> None:
    stages, _ = build_stages(CatalogFilters(country="BD"), None)
    sql = build_funnel_sql(stages)
    assert "count(*) as catalog_candidates" in sql
    for stage in stages:
        assert f"as {stage.name}" in sql
    # Each column applies every earlier stage too, so the counts only ever fall.
    region_column = sql.split(f"as {STAGE_REGION}")[0]
    assert "public.product_is_servable(p)" in region_column
    assert sql.count("public.product_is_servable(p)") >= len(stages)


def test_funnel_sql_is_one_round_trip() -> None:
    stages, _ = build_stages(CatalogFilters(), None)
    sql = build_funnel_sql(stages)
    assert sql.lower().count("select") == 1
    assert sql.lower().count(" from ") == 1
