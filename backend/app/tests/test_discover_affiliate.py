"""Product Details, similar products and the affiliate redirect (§12, §18, §38).

The redirect is the highest-risk surface in Discover: an outbound link the app
opens without question is an open redirect, and an open redirect on a shopping
app is a phishing relay. So the destination rules are tested as pure functions —
every rejection by name — and then again through the route, because a rule that
is enforced in a helper nobody calls is not enforced.
"""

from __future__ import annotations

import time
from datetime import UTC, datetime

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.discover.affiliate import (
    AffiliateError,
    MerchantRedirect,
    host_is_allowed,
    normalize_domain,
    resolve_destination,
)

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)

PRODUCT_ID = "11111111-1111-1111-1111-111111111111"
MERCHANT_ID = "22222222-2222-2222-2222-222222222222"


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
        # unstubbed rate-limit check must ALLOW. Defaulting to None here would
        # make every route in this file 429 for reasons unrelated to the test.
        if "app_rate_limit" in flat:
            return True
        return "UPDATE 0" if method == "execute" else None

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()

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


_PRODUCT_ROW = {
    "id": PRODUCT_ID,
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
    # Derived by the query alongside the row; a hand-curated product can
    # speak to its own delivery, a network one answers "unknown".
    "shipping_availability": "known",
    "sponsored": False,
    "last_synced_at": datetime(2026, 8, 5, tzinfo=UTC),
    "created_at": datetime(2026, 8, 5, tzinfo=UTC),
    "merchant_id": MERCHANT_ID,
    "merchant_name": "Studio Label",
    "merchant_logo": None,
}


def _detail_row(**overrides: object) -> dict:
    row = {
        **_PRODUCT_ROW,
        "servable": True,
        "merchant_approved": True,
        "country_availability": ["BD", "US"],
        "country_eligibility": "listed",
        "shipping_countries": ["BD"],
        "stale": False,
        "has_affiliate_ref": True,
        "has_allowed_domains": True,
        "affiliate_status": "ok",
    }
    row.update(overrides)
    return row


def _click_row(**overrides: object) -> dict:
    row = {
        "id": PRODUCT_ID,
        "affiliate_ref": "sku-123",
        "merchant_id": MERCHANT_ID,
        "servable": True,
        "merchant_name": "Studio Label",
        "merchant_logo": None,
        "merchant_approved": True,
        "allowed_domains": ["shop.example.test"],
        "url_template": "https://shop.example.test/p/{ref}",
        "affiliate_tag": "wtm-secret-tag",
        "tag_param": "aff",
        "affiliate_status": "ok",
    }
    row.update(overrides)
    return row


# ── destination validation: the pure rules ───────────────────────────────────

_ALLOWED = MerchantRedirect(
    allowed_domains=("shop.example.test",),
    url_template="https://shop.example.test/p/{ref}",
    affiliate_tag="tag-1",
)


def test_a_templated_ref_lands_on_the_configured_host() -> None:
    url, host = resolve_destination("sku-123", _ALLOWED)
    assert url.startswith("https://shop.example.test/p/sku-123")
    assert host == "shop.example.test"
    assert "tag=tag-1" in url


@pytest.mark.parametrize(
    "ref",
    [
        # Each of these is an attempt to leave the merchant's host using only
        # the one field a compromised or sloppy product feed controls.
        "https://evil.test/phish",
        "//evil.test/phish",
        "../../evil.test",
        "x?next=https://evil.test",
        "x#@evil.test",
        "x&redirect=https://evil.test",
    ],
)
def test_a_hostile_ref_cannot_move_the_host(ref: str) -> None:
    """The ref is percent-encoded into the template, so it can only ever widen
    the path. This is the single most important property in the module."""
    try:
        url, host = resolve_destination(ref, _ALLOWED)
    except AffiliateError:
        return  # refusing outright is also a correct answer
    assert host == "shop.example.test"
    assert "evil.test" not in url.split("?")[0].split("//")[1].split("/")[0]
    assert url.startswith("https://shop.example.test/")


@pytest.mark.parametrize(
    "template",
    [
        "javascript:alert(1){ref}",
        "data:text/html,{ref}",
        "http://shop.example.test/p/{ref}",
        "file:///etc/passwd{ref}",
        "wtm://open/{ref}",
    ],
)
def test_only_https_destinations_are_produced(template: str) -> None:
    config = MerchantRedirect(allowed_domains=("shop.example.test",), url_template=template)
    with pytest.raises(AffiliateError):
        resolve_destination("sku", config)


def test_credentials_in_the_host_are_refused() -> None:
    # `https://shop.example.test@evil.test/` renders as the merchant in a URL
    # bar and resolves to the attacker. Refused by name.
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://shop.example.test@evil.test/p/{ref}",
    )
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "userinfo"


def test_a_non_default_port_is_refused() -> None:
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://shop.example.test:8443/p/{ref}",
    )
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "port"


def test_a_host_outside_the_allow_list_is_refused() -> None:
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://other.test/p/{ref}",
    )
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "host_not_allowed"


def test_an_empty_allow_list_means_no_redirect_not_any_redirect() -> None:
    config = MerchantRedirect(allowed_domains=(), url_template="https://shop.example.test/{ref}")
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "no_allowed_domains"


def test_a_wildcard_allow_list_entry_does_not_allow_everything() -> None:
    # `*` in an allow-list would defeat the point of having one.
    config = MerchantRedirect(allowed_domains=("*",), url_template="https://evil.test/{ref}")
    with pytest.raises(AffiliateError):
        resolve_destination("sku", config)


def test_subdomains_are_allowed_but_lookalikes_are_not() -> None:
    assert host_is_allowed("uk.shop.example.test", ["shop.example.test"])
    assert host_is_allowed("shop.example.test", ["shop.example.test"])
    # A bare endswith would accept this. The dot anchor is what stops it.
    assert not host_is_allowed("notshop.example.test", ["shop.example.test"])
    assert not host_is_allowed("shop.example.test.evil.test", ["shop.example.test"])


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("https://Shop.Example.Test/", "shop.example.test"),
        ("shop.example.test/path", "shop.example.test"),
        (".shop.example.test", "shop.example.test"),
        ("shop.example.test:443", "shop.example.test"),
        ("*", ""),
        ("  ", ""),
    ],
)
def test_allow_list_entries_are_normalized(raw: str, expected: str) -> None:
    assert normalize_domain(raw) == expected


def test_an_absolute_ref_is_allowed_only_on_an_allow_listed_host() -> None:
    config = MerchantRedirect(allowed_domains=("shop.example.test",), affiliate_tag="t")
    url, host = resolve_destination("https://shop.example.test/product/9", config)
    assert host == "shop.example.test"
    assert "tag=t" in url

    with pytest.raises(AffiliateError):
        resolve_destination("https://evil.test/product/9", config)


def test_the_tag_replaces_rather_than_duplicates_an_existing_one() -> None:
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",), affiliate_tag="mine", tag_param="aff"
    )
    url, _ = resolve_destination("https://shop.example.test/p?aff=someone-else", config)
    assert url.count("aff=") == 1
    assert "aff=mine" in url
    assert "someone-else" not in url


def test_a_template_that_positions_the_tag_is_not_tagged_twice() -> None:
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://shop.example.test/{tag}/p/{ref}",
        affiliate_tag="tag-1",
    )
    url, _ = resolve_destination("sku", config)
    assert url == "https://shop.example.test/tag-1/p/sku"


@pytest.mark.parametrize("status", ["paused", "revoked", "missing"])
def test_a_merchant_that_is_not_ok_earns_no_clicks(status: str) -> None:
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://shop.example.test/{ref}",
        status=status,
    )
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "merchant_status"


def test_a_missing_ref_is_refused_rather_than_guessed() -> None:
    for ref in (None, "", "   "):
        with pytest.raises(AffiliateError) as exc:
            resolve_destination(ref, _ALLOWED)
        assert exc.value.reason == "ref_missing"


def test_control_characters_are_refused() -> None:
    # Some clients strip these silently, which turns a validated string into a
    # different destination after validation.
    config = MerchantRedirect(
        allowed_domains=("shop.example.test",),
        url_template="https://shop.example.test/\n{ref}",
    )
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("sku", config)
    assert exc.value.reason == "url_charset"


def test_an_absurdly_long_destination_is_refused() -> None:
    config = MerchantRedirect(allowed_domains=("shop.example.test",))
    with pytest.raises(AffiliateError) as exc:
        resolve_destination("https://shop.example.test/" + "a" * 4000, config)
    assert exc.value.reason == "url_length"


# ── routes: auth and the flag ────────────────────────────────────────────────


def test_every_phase_4_route_requires_a_token() -> None:
    assert client.get(f"/v1/discover/products/{PRODUCT_ID}").status_code == 401
    assert client.get(f"/v1/discover/products/{PRODUCT_ID}/similar").status_code == 401
    assert client.post(f"/v1/discover/products/{PRODUCT_ID}/click").status_code == 401


def test_shopping_off_serves_no_details_and_no_clicks(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(False)])
    _wire(monkeypatch, conn)
    assert client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).status_code == 404
    assert (
        client.post(
            f"/v1/discover/products/{PRODUCT_ID}/click",
            headers={**_auth(), "Idempotency-Key": "k1"},
        ).status_code
        == 404
    )
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


# ── product details ──────────────────────────────────────────────────────────


def test_details_revalidate_price_stock_and_variants(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _detail_row()),
            (
                "fetch",
                "from public.product_variants",
                [
                    {
                        "id": "33333333-3333-3333-3333-333333333333",
                        "product_id": PRODUCT_ID,
                        "color": "black",
                        "size": "M",
                        "price_minor": 349900,
                        "original_price_minor": None,
                        "stock_status": "low_stock",
                        "available": True,
                        "currency": "BDT",
                    }
                ],
            ),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).json()

    assert body["product"]["price"] == {"amount_minor": 349900, "currency": "BDT"}
    assert body["servable"] is True
    assert body["stale"] is False
    assert body["server_time"]
    # Variant-level availability, because "has size M" and "size M is in stock"
    # are different claims (§12.16).
    assert body["product"]["variants"][0]["size"] == "M"
    assert body["product"]["variants"][0]["stock_status"] == "low_stock"


def test_delivery_region_is_the_intersection_of_product_and_merchant(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", _detail_row())])
    _wire(monkeypatch, conn)
    body = client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).json()
    # Listed for BD and US; the merchant only ships to BD.
    assert body["delivery_countries"] == ["BD"]


def test_a_sold_out_product_still_opens_and_says_so(monkeypatch: pytest.MonkeyPatch) -> None:
    # 404 would read as a broken link and would strand the user with no
    # explanation and no alternatives (§11.3, §24).
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "from public.products p",
                _detail_row(servable=False, stock_status="out_of_stock"),
            ),
        ]
    )
    _wire(monkeypatch, conn)
    resp = client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth())
    assert resp.status_code == 200
    assert resp.json()["servable"] is False
    assert resp.json()["shoppable"] is False


def test_a_stale_source_is_reported_not_hidden(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", _detail_row(stale=True))])
    _wire(monkeypatch, conn)
    assert (
        client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).json()["stale"] is True
    )


def test_details_never_carry_an_affiliate_destination(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", _detail_row())])
    _wire(monkeypatch, conn)
    raw = client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).text
    # `shoppable` says whether a click can succeed; nothing says where it goes.
    assert "affiliate_ref" not in raw
    assert "shop.example.test" not in raw

    detail_sql = conn.sql_calls("from public.products p")[0][1]
    # The SQL may ASK whether a ref exists, but must never select its value.
    assert "p.affiliate_ref is not null" in detail_sql
    assert "select p.affiliate_ref" not in detail_sql


def test_a_malformed_product_id_is_a_404_not_a_500(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.get("/v1/discover/products/not-a-uuid", headers=_auth())
    assert resp.status_code == 404
    assert conn.sql_calls("from public.products p") == []


def test_an_unknown_product_is_a_404(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", None)])
    _wire(monkeypatch, conn)
    assert client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).status_code == 404


def test_try_on_completed_is_read_from_behaviour_not_from_the_client(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _detail_row()),
            ("fetchval", "from public.product_interactions", 1),
        ]
    )
    _wire(monkeypatch, conn)
    body = client.get(f"/v1/discover/products/{PRODUCT_ID}", headers=_auth()).json()
    assert body["try_on_completed"] is True
    sql = conn.sql_calls("from public.product_interactions")[0][1]
    assert "event_type = 'try_on'" in sql


# ── similar products ─────────────────────────────────────────────────────────


def test_similar_applies_the_same_suppression_rules_as_the_feed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(
        [
            _flag(),
            (
                "fetchrow",
                "select category, merchant_id from public.products",
                {"category": "dresses", "merchant_id": MERCHANT_ID},
            ),
            ("fetch", "from public.products p", [_PRODUCT_ROW]),
        ]
    )
    _wire(monkeypatch, conn)
    resp = client.get(f"/v1/discover/products/{PRODUCT_ID}/similar", headers=_auth())
    assert resp.status_code == 200

    sql = conn.sql_calls("from public.products p")[0][1]
    # An alternative that is out of stock, expired or un-shippable is not an
    # alternative — so "similar" runs through product_is_servable too.
    assert "public.product_is_servable(p)" in sql
    assert "m.approved" in sql
    # And never suggests the product the user is already looking at.
    assert "p.id <>" in sql


def test_similar_on_an_unknown_product_is_a_404(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchrow", "select category, merchant_id from public.products", None)])
    _wire(monkeypatch, conn)
    assert (
        client.get(f"/v1/discover/products/{PRODUCT_ID}/similar", headers=_auth()).status_code
        == 404
    )


# ── the outbound click ───────────────────────────────────────────────────────


def _click(conn: _Conn, key: str = "idem-1") -> object:
    return client.post(
        f"/v1/discover/products/{PRODUCT_ID}/click",
        json={"feed_placement": "product_details", "tracking_token": f"p:{PRODUCT_ID}"},
        headers={**_auth(), "Idempotency-Key": key},
    )


def test_a_click_returns_a_validated_destination_and_records_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _click_row()),
            ("execute", "insert into public.idempotency_keys", "INSERT 0 1"),
            ("fetchval", "insert into public.affiliate_clicks", "44444444-4444-4444-4444-444444"),
        ]
    )
    _wire(monkeypatch, conn)
    resp = _click(conn)
    assert resp.status_code == 200

    body = resp.json()
    assert body["url"].startswith("https://shop.example.test/p/sku-123")
    assert "aff=wtm-secret-tag" in body["url"]
    assert body["merchant"]["name"] == "Studio Label"
    assert body["click_id"]

    # A shop click is also a positive ranking signal (§19.3).
    assert conn.sql_calls("insert into public.product_interactions")


def test_a_click_stores_the_reference_and_host_not_the_tagged_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The tag identifies the account that gets paid. It belongs in the URL the
    user opens and nowhere else — not in a row, not in a log (§40)."""
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _click_row()),
            ("execute", "insert into public.idempotency_keys", "INSERT 0 1"),
            ("fetchval", "insert into public.affiliate_clicks", "44444444-4444-4444-4444-444444"),
        ]
    )
    _wire(monkeypatch, conn)
    _click(conn)

    _, sql, args = conn.sql_calls("insert into public.affiliate_clicks")[0]
    assert "destination_ref" in sql and "destination_host" in sql
    assert "sku-123" in args
    assert "shop.example.test" in args
    assert not any("wtm-secret-tag" in str(a) for a in args)


def test_a_click_without_an_idempotency_key_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.post(f"/v1/discover/products/{PRODUCT_ID}/click", headers=_auth())
    assert resp.status_code == 400
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


def test_a_retried_click_replays_instead_of_logging_a_second_one(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A duplicate click inflates the click-through rate the funnel is judged on.
    stored = {
        "status_code": 200,
        "response": {
            "click_id": "c1",
            "url": "https://shop.example.test/p/sku-123?aff=wtm-secret-tag",
            "merchant": {"id": MERCHANT_ID, "name": "Studio Label", "logo_url": None},
            "try_on_completed": False,
        },
    }
    conn = _Conn([_flag(), ("fetchrow", "from public.idempotency_keys", stored)])
    _wire(monkeypatch, conn)
    resp = _click(conn)

    assert resp.status_code == 200
    assert resp.json()["click_id"] == "c1"
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


def test_a_click_on_a_product_that_is_gone_is_a_404_not_a_broken_browser_tab(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", _click_row(servable=False))])
    _wire(monkeypatch, conn)
    resp = _click(conn)
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


@pytest.mark.parametrize(
    "overrides",
    [
        {"allowed_domains": []},
        {"url_template": None},
        {"url_template": "https://evil.test/p/{ref}"},
        {"affiliate_status": "missing"},
        {"affiliate_ref": None},
    ],
)
def test_a_destination_that_fails_validation_is_a_502_with_no_click_logged(
    monkeypatch: pytest.MonkeyPatch, overrides: dict
) -> None:
    """Distinct from "gone": the app keeps Product Details open and offers a
    retry for this, and shows alternatives for the other (§24)."""
    conn = _Conn([_flag(), ("fetchrow", "from public.products p", _click_row(**overrides))])
    _wire(monkeypatch, conn)
    resp = _click(conn)

    assert resp.status_code == 502
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"
    # No destination, and nothing that hints at one.
    assert "evil.test" not in resp.text
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


def test_a_click_row_carries_placement_and_derived_try_on_state(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _click_row()),
            ("fetchval", "from public.product_interactions", 1),
            ("execute", "insert into public.idempotency_keys", "INSERT 0 1"),
            ("fetchval", "insert into public.affiliate_clicks", "44444444-4444-4444-4444-444444"),
        ]
    )
    _wire(monkeypatch, conn)
    body = _click(conn).json()

    assert body["try_on_completed"] is True
    _, _, args = conn.sql_calls("insert into public.affiliate_clicks")[0]
    assert "product_details" in args
    # Positional, because the point is that the DERIVED value reached the row
    # rather than merely the response: args[7] is try_on_completed.
    assert args[7] is True


def test_a_click_from_a_try_on_result_is_accepted_and_kept_distinct(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`tryon_result` is a real placement, not a typo the API rejects.

    The try-on-to-shop rate is the whole reason the shopping try-on exists, and
    it cannot be measured if a click from a render looks the same as one from a
    product page. A 422 here would break the result screen's Shop button in
    production while every unit test still passed.
    """
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _click_row()),
            ("execute", "insert into public.idempotency_keys", "INSERT 0 1"),
            ("fetchval", "insert into public.affiliate_clicks", "44444444-4444-4444-4444-444444"),
        ]
    )
    _wire(monkeypatch, conn)
    resp = client.post(
        f"/v1/discover/products/{PRODUCT_ID}/click",
        json={"feed_placement": "tryon_result"},
        headers={**_auth(), "Idempotency-Key": "idem-tryon"},
    )
    assert resp.status_code == 200

    _, _, args = conn.sql_calls("insert into public.affiliate_clicks")[0]
    assert "tryon_result" in args


@pytest.mark.parametrize("placement", ["similar_products", "home_shop_your_mood"])
def test_the_new_product_surfaces_are_accepted_placements(
    monkeypatch: pytest.MonkeyPatch, placement: str
) -> None:
    """Every surface that can start a try-on must be able to name itself.

    Try On now lives on the product card everywhere a garment is shown, which
    put two surfaces on the wire that the vocabulary did not have words for.
    A 422 here would not break the button — the interaction write is
    fire-and-forget — it would silently drop the `try_on` signal, and that
    signal is what makes the server answer `try_on_completed` on a later
    click. The funnel would lose exactly the conversions it exists to count.
    """
    conn = _Conn(
        [
            _flag(),
            ("fetchrow", "from public.products p", _click_row()),
            ("execute", "insert into public.idempotency_keys", "INSERT 0 1"),
            ("fetchval", "insert into public.affiliate_clicks", "55555555-5555-5555-5555-555555"),
        ]
    )
    _wire(monkeypatch, conn)
    resp = client.post(
        f"/v1/discover/products/{PRODUCT_ID}/click",
        json={"feed_placement": placement},
        headers={**_auth(), "Idempotency-Key": f"idem-{placement}"},
    )
    assert resp.status_code == 200

    _, _, args = conn.sql_calls("insert into public.affiliate_clicks")[0]
    assert placement in args


def test_an_unknown_placement_is_still_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    # The placement vocabulary is typed on purpose: a free-text field would
    # quietly accumulate variants nobody can group by.
    conn = _Conn([_flag()])
    _wire(monkeypatch, conn)
    resp = client.post(
        f"/v1/discover/products/{PRODUCT_ID}/click",
        json={"feed_placement": "wherever"},
        headers={**_auth(), "Idempotency-Key": "idem-bad"},
    )
    assert resp.status_code == 422
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


def test_clicks_are_rate_limited(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchval", "app_rate_limit", False)])
    _wire(monkeypatch, conn)
    resp = _click(conn)

    assert resp.status_code == 429
    assert resp.json()["error"]["code"] == "RATE_LIMITED"
    assert conn.sql_calls("insert into public.affiliate_clicks") == []


def test_interaction_writes_are_rate_limited(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([_flag(), ("fetchval", "app_rate_limit", False)])
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/discover/interactions",
        json={"event_type": "impression", "product_id": PRODUCT_ID},
        headers=_auth(),
    )
    assert resp.status_code == 429
    assert conn.sql_calls("insert into public.product_interactions") == []


def test_search_is_rate_limited_but_browsing_is_not(monkeypatch: pytest.MonkeyPatch) -> None:
    # Throttling a scroll would be a bug; throttling free-text queries is the
    # point (§38).
    conn = _Conn([_flag(), ("fetchval", "app_rate_limit", False)])
    _wire(monkeypatch, conn)

    assert client.get("/v1/discover/products", headers=_auth()).status_code == 200
    limited = client.get("/v1/discover/products", params={"q": "dress"}, headers=_auth())
    assert limited.status_code == 429
