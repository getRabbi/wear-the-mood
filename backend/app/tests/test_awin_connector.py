"""The Awin connector: listing, credentials, feed reading and the row adapter.

These are the tests that would have caught the two things the LIVE account
contradicted — the listing is CSV rather than JSON, and membership status reads
`Not Joined` rather than "Joined" — so they are written against the real
response shapes, not against the documentation.

The security assertions here are not decoration. A leaked Data Feed API key is
somebody else's catalogue budget spent on our account, and the key travels in a
URL *path*, which is exactly the kind of string that ends up in an exception
message, a log line and an admin error field at the same time.
"""

from __future__ import annotations

import gzip
import io
import os

import httpx
import pytest

from app.services.catalog.networks.awin import (
    ADULT_CONTENT,
    FEED_COLUMNS,
    AwinClient,
    AwinCredentialsMissing,
    AwinDiscovery,
    AwinFeed,
    AwinMultiFeedSource,
    read_feed,
    redact,
)
from app.services.catalog.networks.awin_adapter import awin_row_to_canonical, feed_provenance

KEY = "test-secret-key-0000"

# A verbatim-shaped slice of the live listing: the header Awin actually sends,
# one joined advertiser and one that is merely listed.
LISTING_CSV = (
    "Advertiser ID,Advertiser Name,Membership Status,Feed ID,Feed Name,Language,"
    "Vertical,Primary Region,Last Imported,Last Checked,No of products,URL\n"
    "880044,AliExpress PL,active,90001,Men's Clothing,en,Retail,PL,"
    "2026-08-01 04:15:00,2026-08-01 06:00:00,1180,"
    "https://productdata.awin.com/datafeed/download/apikey/" + KEY + "/fid/90001/\n"
    "9999,Some Other Shop,Not Joined,90003,Everything,en,Retail,UK,"
    "2026-07-30 04:15:00,2026-08-01 06:00:00,52000,"
    "https://productdata.awin.com/datafeed/download/apikey/" + KEY + "/fid/90003/\n"
)

FEED_HEADER = ",".join(FEED_COLUMNS)
FEED_ROW = (
    "45008267948,1005001463675745,Juya DIY Costume Jewelry,,,"  # ids, name, desc, brand
    "Jewelry Accessories,,,5.51,7.20,USD,"  # merchant_category, category_name, id, prices
    "https://ae01.alicdn.com/kf/a.jpg,https://images.awin.com/b.jpg,"
    "https://www.awin1.com/pclick.php?p=45008267948&a=770000&m=880044,"
    "https://www.aliexpress.com/item/1005001463675745.html,"
    "880044,AliExpress PL,90002,0,,,,"
)


@pytest.fixture(autouse=True)
def _credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AWIN_PUBLISHER_ID", "770000")
    monkeypatch.setenv("AWIN_DATA_FEED_API_KEY", KEY)


def _transport(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


# ── credentials never escape ────────────────────────────────────────────────


def test_the_key_is_redacted_wherever_it_appears() -> None:
    url = f"https://productdata.awin.com/datafeed/download/apikey/{KEY}/fid/90001/"
    assert KEY not in redact(url)
    assert KEY not in redact(f"boom while fetching {url}")
    assert KEY not in redact(Exception(f"HTTP 500 for {url}"))


def test_redaction_survives_case_and_percent_encoding() -> None:
    # A key that has been through URL quoting no longer contains the literal, and
    # a naive `str.replace` would sail straight past it.
    assert KEY.upper() not in redact(f"/apikey/{KEY.upper()}/fid/1/")
    assert "%2F" not in redact("/apikey/abc%2Fdef/fid/1/")
    assert redact("/apikey/abc%2Fdef/fid/1/") == "/apikey/***REDACTED***/fid/1/"


def test_a_stale_url_from_another_environment_is_still_redacted() -> None:
    # The path pattern catches a key this process has never held — a URL read
    # back out of an old database row, say.
    other = "/apikey/somebody-elses-key/fid/9/"
    assert "somebody-elses-key" not in redact(f"failed: {other}")


def test_a_missing_key_is_a_named_error_not_a_broken_url() -> None:
    os.environ.pop("AWIN_DATA_FEED_API_KEY", None)
    client = AwinClient()
    assert client.configured is False
    with pytest.raises(AwinCredentialsMissing):
        client.feed_url("90001")


# ── the constructed download URL ────────────────────────────────────────────


def test_every_constructed_url_asks_for_adult_content_off() -> None:
    # Awin's own listing URLs arrive with adultcontent/1. We never use those.
    url = AwinClient().feed_url("90001")
    assert f"/adultcontent/{ADULT_CONTENT}/" in url
    assert "/adultcontent/1/" not in url
    assert ADULT_CONTENT == "0"


def test_the_url_carries_the_key_and_the_requested_columns() -> None:
    url = AwinClient().feed_url("90001", language="pl")
    assert f"/apikey/{KEY}/" in url  # authenticated server-side, never stored
    assert "/fid/90001/" in url
    assert "/language/pl/" in url
    assert "/compression/gzip/" in url
    assert "merchant_product_id" in url


def test_a_feed_id_cannot_smuggle_extra_url_segments() -> None:
    # A feed id is data from a third party. Quoting it means a malicious listing
    # cannot rewrite the request into a different endpoint.
    url = AwinClient().feed_url("90001/format/json/x")
    assert "/fid/90001%2Fformat%2Fjson%2Fx/" in url
    assert "/format/csv/" in url


# ── listing ─────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_the_listing_is_parsed_as_csv() -> None:
    # The live endpoint returns CSV, not JSON, whatever the docs imply.
    async def handler(request: httpx.Request) -> httpx.Response:
        assert "/datafeed/list/apikey/" in str(request.url)
        return httpx.Response(200, text=LISTING_CSV)

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert result.total_rows == 2
    assert {f.feed_id for f in result.feeds} == {"90001", "90003"}
    joined = next(f for f in result.feeds if f.feed_id == "90001")
    assert joined.advertiser_name == "AliExpress PL"
    assert joined.product_count == 1180
    assert joined.last_imported is not None


@pytest.mark.anyio
async def test_only_joined_advertisers_are_accessible() -> None:
    # The listing returns every advertiser on the network — hundreds we have no
    # agreement with. Importing one would be downloading a catalogue we are not
    # entitled to.
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text=LISTING_CSV)

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert [f.feed_id for f in result.accessible] == ["90001"]
    assert list(result.advertisers()) == ["880044"]


@pytest.mark.parametrize(
    ("status", "accessible"),
    [
        ("active", True),
        ("Active", True),
        ("joined", True),
        ("Not Joined", False),
        ("pending", False),
        ("suspended", False),
        ("", False),
        ("some status awin invents in 2027", False),
    ],
)
def test_membership_status_fails_closed(status: str, accessible: bool) -> None:
    feed = AwinFeed(
        advertiser_id="1",
        advertiser_name="x",
        feed_id="2",
        feed_name="f",
        language=None,
        region=None,
        vertical=None,
        membership_status=status,
        product_count=None,
        last_imported=None,
        last_checked=None,
    )
    assert feed.is_accessible is accessible


def test_a_listing_row_without_ids_is_reported_not_guessed() -> None:
    result = AwinDiscovery()
    assert result.accessible == []
    assert result.advertisers() == {}
    # A discovery nobody has populated has read nothing, so it certainly has not
    # read everything. The default must be the safe one.
    assert result.complete is False


# ── the listing's own completeness ──────────────────────────────────────────
#
# Same contract as a feed download. `complete` is what makes "this feed was not
# in the listing" mean "the advertiser withdrew it".


@pytest.mark.anyio
async def test_a_clean_listing_is_complete() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text=LISTING_CSV)

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert result.complete is True
    assert result.errors == []


@pytest.mark.anyio
async def test_a_body_shorter_than_content_length_is_not_complete() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            content=LISTING_CSV.encode(),
            headers={"content-length": str(len(LISTING_CSV) + 5000)},
        )

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert result.complete is False
    assert result.feeds == []  # nothing is trusted from a truncated document
    assert "truncated" in result.errors[0]


@pytest.mark.anyio
async def test_a_response_that_is_not_the_listing_is_not_complete() -> None:
    # An error page, a changed schema, an empty body: every feed would look
    # absent, which is exactly the conclusion that must never be drawn.
    for body in ["<html><body>Service Unavailable</body></html>", "", "a,b,c\n1,2,3\n"]:

        async def handler(_: httpx.Request, body: str = body) -> httpx.Response:
            return httpx.Response(200, text=body)

        async with _transport(handler) as http:
            result = await AwinClient(client=http).discover()

        assert result.complete is False, body[:20]
        assert result.feeds == []
        assert any("header missing" in e for e in result.errors)


@pytest.mark.anyio
async def test_one_ragged_row_withholds_completeness_but_keeps_the_rest() -> None:
    # The good rows are still worth having — they update what we know. What is
    # withheld is only the right to conclude anything from an ABSENCE, because
    # the row we could not read may have been the feed we are about to retire.
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text=LISTING_CSV + "880044,Half A Row,active\n")

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert result.complete is False
    assert len(result.feeds) == 2  # the two whole rows survived
    assert result.errors


@pytest.mark.anyio
async def test_a_row_missing_its_ids_withholds_completeness() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            text=LISTING_CSV + ",Nameless,active,,,en,Retail,PL,,,0,\n",
        )

    async with _transport(handler) as http:
        result = await AwinClient(client=http).discover()

    assert result.complete is False
    assert len(result.feeds) == 2


# ── feed download ───────────────────────────────────────────────────────────


def _gzip(text: str) -> bytes:
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb") as fh:
        fh.write(text.encode("utf-8"))
    return buf.getvalue()


@pytest.mark.anyio
async def test_a_clean_gzip_feed_reads_completely() -> None:
    body = _gzip(f"{FEED_HEADER}\n{FEED_ROW}\n{FEED_ROW}\n")

    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        result = await read_feed(http, "https://x/apikey/k/fid/1/", "1")

    assert result.complete is True
    assert result.truncated is False
    assert len(result.rows) == 2
    assert result.rows[0]["merchant_product_id"] == "1005001463675745"


@pytest.mark.anyio
async def test_a_truncated_gzip_stream_is_never_reported_complete() -> None:
    # The single most important assertion in this file: `complete` is what
    # decides whether products we did not see may be retired.
    body = _gzip(f"{FEED_HEADER}\n{FEED_ROW}\n" * 3)[:-40]

    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        result = await read_feed(http, "https://x/apikey/k/fid/1/", "1")

    assert result.complete is False
    assert result.truncated is True
    assert result.error


@pytest.mark.anyio
async def test_an_http_error_is_incomplete_and_redacted() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(503)

    async with _transport(handler) as http:
        result = await read_feed(http, f"https://x/apikey/{KEY}/fid/1/", "1")

    assert result.complete is False
    assert result.rows == []
    assert KEY not in (result.error or "")


@pytest.mark.anyio
async def test_corrupt_bytes_do_not_raise_out_of_the_reader() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"this is not gzip at all")

    async with _transport(handler) as http:
        result = await read_feed(http, "https://x/apikey/k/fid/1/", "1")

    assert result.complete is False
    assert "gzip" in (result.error or "")


@pytest.mark.anyio
async def test_the_row_cap_marks_the_read_incomplete() -> None:
    body = _gzip(f"{FEED_HEADER}\n" + f"{FEED_ROW}\n" * 20)

    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        result = await read_feed(http, "https://x/apikey/k/fid/1/", "1", max_rows=5)

    assert result.complete is False
    assert result.truncated is True
    assert len(result.rows) == 5


@pytest.mark.anyio
async def test_a_malformed_row_is_skipped_without_failing_the_feed() -> None:
    # A bad row is the merchant's problem; we read every byte they sent, so the
    # feed IS complete and absence still means absence.
    body = _gzip(f'{FEED_HEADER}\n{FEED_ROW}\n"unterminated,,,\n{FEED_ROW}\n')

    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        result = await read_feed(http, "https://x/apikey/k/fid/1/", "1")

    assert result.complete is True
    assert len(result.rows) >= 2


# ── many feeds, one source ──────────────────────────────────────────────────


class _FakeClient(AwinClient):
    def feed_url(self, feed_id: str, *, language: str = "en") -> str:
        return f"https://feeds.test/apikey/{KEY}/fid/{feed_id}/lang/{language}/"


def _feeds(*ids: str) -> list[dict[str, object]]:
    return [{"network_feed_id": i, "language": "en", "product_count": 10} for i in ids]


@pytest.mark.anyio
async def test_all_feeds_read_means_the_source_is_complete() -> None:
    body = _gzip(f"{FEED_HEADER}\n{FEED_ROW}\n")

    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        source = AwinMultiFeedSource(_FakeClient(), _feeds("1", "2", "3"), http=http)
        rows = await source.fetch("")

    assert len(rows) == 3
    assert source.complete is True
    assert source.feeds_completed == ["1", "2", "3"]
    assert source.feeds_failed == []
    assert source.source_count == 30


@pytest.mark.anyio
async def test_one_failing_feed_makes_the_whole_source_incomplete() -> None:
    # Twenty feeds succeeding and one timing out looks exactly like a merchant
    # delisting a category. It is not, and the difference is thousands of
    # products going dark.
    body = _gzip(f"{FEED_HEADER}\n{FEED_ROW}\n")

    async def handler(request: httpx.Request) -> httpx.Response:
        if "/fid/2/" in str(request.url):
            raise httpx.TimeoutException("timed out")
        return httpx.Response(200, content=body)

    async with _transport(handler) as http:
        source = AwinMultiFeedSource(_FakeClient(), _feeds("1", "2", "3"), http=http)
        rows = await source.fetch("")

    # The rows we DID read are still imported — they are real products.
    assert len(rows) == 2
    assert source.complete is False
    assert source.feeds_failed == ["2"]
    assert sorted(source.feeds_completed) == ["1", "3"]


@pytest.mark.anyio
async def test_no_enabled_feeds_is_not_a_complete_read() -> None:
    # Otherwise "nothing enabled" would read as "the merchant sells nothing"
    # and retire the entire catalogue.
    source = AwinMultiFeedSource(_FakeClient(), [])
    assert await source.fetch("") == []
    assert source.complete is False


@pytest.mark.anyio
async def test_feed_errors_never_contain_the_key() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(500)

    async with _transport(handler) as http:
        source = AwinMultiFeedSource(_FakeClient(), _feeds("1"), http=http)
        await source.fetch("")

    assert source.errors
    for entry in source.errors:
        assert KEY not in entry["error"]


# ── row adapter ─────────────────────────────────────────────────────────────

LIVE_ROW = {
    "aw_product_id": "45008267948",
    "merchant_product_id": "1005001463675745",
    "product_name": "Juya DIY Costume Jewelry",
    "description": "",
    "brand_name": "",
    "merchant_category": "Jewelry Accessories",
    "category_name": "",
    "search_price": "5.51",
    "product_price_old": "7.20",
    "currency": "USD",
    "merchant_image_url": "https://ae01.alicdn.com/kf/a.jpg",
    "aw_image_url": "https://images.awin.com/b.jpg",
    "aw_deep_link": "https://www.awin1.com/pclick.php?p=45008267948&a=770000&m=880044",
    "merchant_deep_link": "https://www.aliexpress.com/item/1005001463675745.html",
    "data_feed_id": "90002",
    "merchant_id": "880044",
    "stock_quantity": "0",
}


def test_identity_is_the_retailers_own_product_id() -> None:
    # `aw_product_id` is Awin's per-feed surrogate: using it would make the same
    # jacket a different product in the Men's feed and the Outerwear feed.
    assert awin_row_to_canonical(LIVE_ROW)["external_id"] == "1005001463675745"


def test_awins_surrogate_id_is_the_fallback_not_the_default() -> None:
    row = {**LIVE_ROW, "merchant_product_id": ""}
    assert awin_row_to_canonical(row)["external_id"] == "45008267948"


def test_stock_is_unknown_rather_than_invented() -> None:
    # 92% of live rows send stock_quantity 0 while being plainly purchasable, so
    # the column is a default, not inventory. Believing it would hide the
    # catalogue behind product_is_servable().
    assert awin_row_to_canonical(LIVE_ROW)["stock_status"] == "unknown"
    assert awin_row_to_canonical({**LIVE_ROW, "stock_quantity": "500"})["stock_status"] == "unknown"


def test_nothing_the_feed_did_not_say_is_fabricated() -> None:
    canonical = awin_row_to_canonical(LIVE_ROW)
    assert canonical["country_availability"] == []
    assert canonical["sizes"] == []
    assert canonical["colors"] == []
    assert canonical["variants"] == []
    assert canonical["try_on_status"] == "unsupported"


def test_unknown_shipping_is_said_out_loud_not_left_to_an_empty_list() -> None:
    # An empty array on its own reads as "no restriction" and would let a
    # product with zero shipping evidence satisfy every country filter. The
    # explicit `unknown` is what stops that.
    canonical = awin_row_to_canonical(LIVE_ROW)
    assert canonical["country_availability"] == []
    assert canonical["country_eligibility"] == "unknown"


def test_the_programmes_region_is_not_treated_as_a_shipping_promise() -> None:
    # "The advertiser is Polish" is a fact about the advertiser. Nothing in the
    # adapter may turn it into a claim about where a parcel goes.
    for region in ("PL", "GB", "US"):
        canonical = awin_row_to_canonical({**LIVE_ROW, "region": region, "language": region})
        assert canonical["country_availability"] == []
        assert canonical["country_eligibility"] == "unknown"


def test_the_price_is_handed_over_as_a_decimal_string() -> None:
    # NOT converted here: 5.51 * 100 in binary float is 550.9999…, and the
    # existing mapping layer already does this correctly in Decimal.
    canonical = awin_row_to_canonical(LIVE_ROW)
    assert canonical["price_minor"] == "5.51"
    assert canonical["original_price_minor"] == "7.20"
    assert canonical["currency"] == "USD"


def test_currency_is_read_per_row() -> None:
    # One live feed carried both CNY and USD; a feed-level currency would have
    # mispriced 13% of it.
    assert awin_row_to_canonical({**LIVE_ROW, "currency": "CNY"})["currency"] == "CNY"


def test_the_tracked_link_is_preferred_and_the_retailer_link_is_the_fallback() -> None:
    assert "awin1.com" in awin_row_to_canonical(LIVE_ROW)["affiliate_ref"]
    without = awin_row_to_canonical({**LIVE_ROW, "aw_deep_link": ""})
    assert without["affiliate_ref"] == LIVE_ROW["merchant_deep_link"]


def test_the_retailers_own_image_wins_over_awins_cached_copy() -> None:
    assert awin_row_to_canonical(LIVE_ROW)["image_urls"] == ["https://ae01.alicdn.com/kf/a.jpg"]
    fallback = awin_row_to_canonical({**LIVE_ROW, "merchant_image_url": ""})
    assert fallback["image_urls"] == ["https://images.awin.com/b.jpg"]


def test_a_relative_or_junk_image_is_dropped_not_passed_on() -> None:
    row = {**LIVE_ROW, "merchant_image_url": "/kf/a.jpg", "aw_image_url": "javascript:alert(1)"}
    assert awin_row_to_canonical(row)["image_urls"] == []


def test_category_falls_back_when_the_feed_leaves_it_empty() -> None:
    # `category_name` was empty in one live feed and populated in another.
    assert awin_row_to_canonical(LIVE_ROW)["category"] == "Jewelry Accessories"
    named = awin_row_to_canonical({**LIVE_ROW, "category_name": "Necklaces"})
    assert named["category"] == "Necklaces"


def test_an_empty_row_is_refusable_rather_than_an_exception() -> None:
    # One unreadable row must not end a 150,000-row feed; it comes out missing
    # what the normalizer requires and is refused there, with a reason.
    canonical = awin_row_to_canonical({})
    assert canonical["external_id"] is None
    assert canonical["title"] is None


def test_provenance_keeps_only_non_secret_identifiers() -> None:
    assert feed_provenance(LIVE_ROW) == {
        "awin_product_id": "45008267948",
        "awin_feed_id": "90002",
        "awin_merchant_id": "880044",
    }
    assert feed_provenance({}) == {}
