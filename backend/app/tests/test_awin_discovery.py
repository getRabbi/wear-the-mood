"""Network discovery, and the rule that decides when products may be retired.

Discovery's job is to find out what an account CAN reach and then do nothing
about it. The account this was built against lists 581 feeds across hundreds of
advertisers; a pass that enabled what it found would have imported several
hundred catalogues nobody chose. So most of what is asserted here is what
discovery does *not* do.

The database is faked rather than mocked away: the SQL is the behaviour. Whether
a merchant is created approved, and whether a discovery pass may overwrite an
operator's decision to run a feed, are both properties of the statement text.
"""

from __future__ import annotations

import asyncio
import re
from typing import Any

import pytest

from app.services.catalog.models import SyncOutcome
from app.services.catalog.networks.awin import AwinClient, AwinCredentialsMissing, AwinDiscovery
from app.services.catalog.networks.discovery import _slug, discover_awin
from app.services.catalog.sync import completed_status, may_reconcile

from .test_awin_connector import LISTING_CSV  # the live listing shape

KEY = "test-secret-key-0000"


@pytest.fixture(autouse=True)
def _credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AWIN_PUBLISHER_ID", "770000")
    monkeypatch.setenv("AWIN_DATA_FEED_API_KEY", KEY)


class FakeConn:
    """Enough asyncpg to run a discovery pass, and a transcript of the SQL."""

    def __init__(self, *, existing_merchant: str | None = None) -> None:
        self.sql: list[str] = []
        self.params: list[tuple[Any, ...]] = []
        self._existing = existing_merchant
        self._ids = 0

    def _record(self, query: str, args: tuple[Any, ...]) -> None:
        # Comments are stripped: these tests assert on what the statement DOES,
        # and a comment explaining a column is not the column being set.
        stripped = re.sub(r"--[^\n]*", "", query)
        self.sql.append(" ".join(stripped.split()))
        self.params.append(args)

    async def fetchval(self, query: str, *args: Any) -> Any:
        self._record(query, args)
        if "insert into public.network_discovery_runs" in query:
            return "run-1"
        if "select id from public.merchants" in query:
            return self._existing
        if "insert into public.merchants" in query:
            self._ids += 1
            return f"merchant-{self._ids}"
        if "update public.merchant_feeds f" in query:  # the removal sweep
            return 0
        return None

    async def fetchrow(self, query: str, *args: Any) -> Any:
        self._record(query, args)
        return {"inserted": True}

    async def execute(self, query: str, *args: Any) -> str:
        self._record(query, args)
        return "OK"

    def find(self, needle: str) -> list[str]:
        return [q for q in self.sql if needle in q]


def _listing() -> AwinDiscovery:
    """The parsed live listing: one joined advertiser, one not joined."""

    async def run() -> AwinDiscovery:
        import httpx

        async def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(200, text=LISTING_CSV)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
            return await AwinClient(client=http).discover()

    return asyncio.run(run())


def _discover(conn: FakeConn, discovery: AwinDiscovery | None = None) -> dict[str, Any]:
    return asyncio.run(
        discover_awin(conn, discovery=discovery if discovery is not None else _listing())
    )


# ── what discovery finds ────────────────────────────────────────────────────


def test_a_pass_records_what_it_saw() -> None:
    conn = FakeConn()
    result = _discover(conn)
    assert result["status"] == "success"
    # One accessible advertiser out of two listed — the other is Not Joined.
    assert result["advertisers_seen"] == 1
    assert result["advertisers_added"] == 1
    assert result["feeds_seen"] == 1
    assert result["feeds_added"] == 1


def test_an_advertiser_we_have_not_joined_is_never_written() -> None:
    conn = FakeConn()
    _discover(conn)
    written = " ".join(conn.find("insert into public.merchants"))
    flat = " ".join(str(p) for p in conn.params)
    assert "AliExpress PL" in flat
    assert "Some Other Shop" not in flat
    assert written  # the joined one WAS written


def test_a_discovered_merchant_is_created_unapproved() -> None:
    # `approved` is what makes a merchant's products visible and what lets its
    # feed sync at all. Finding a programme is not choosing to sell it.
    conn = FakeConn()
    _discover(conn)
    insert = conn.find("insert into public.merchants")[0]
    assert re.search(r"values\s*\(\$1,\s*\$2,\s*false", insert), insert


def test_a_discovered_feed_is_created_disabled() -> None:
    conn = FakeConn()
    _discover(conn)
    insert = conn.find("insert into public.merchant_feeds")[0]
    assert "false,now(),null" in insert.replace(" ", ""), insert


def test_the_sync_config_is_created_with_everything_off() -> None:
    conn = FakeConn()
    _discover(conn)
    cfg = conn.find("insert into public.merchant_feed_config")[0]
    assert "null, 'csv', false" in cfg  # no feed_url, and not enabled
    assert "'unknown'" in cfg  # image rights are not assumed to be granted


def test_no_feed_url_is_ever_persisted() -> None:
    # The authenticated URL is rebuilt in the backend per download. If it is not
    # in the database, no admin read, audit snapshot or backup can leak it.
    conn = FakeConn()
    _discover(conn)
    flat = " ".join(str(p) for p in conn.params)
    assert KEY not in flat
    assert "productdata.awin.com/datafeed/download" not in flat


def test_rediscovery_never_overrides_an_operators_feed_decision() -> None:
    # The single most dangerous thing a nightly job could do here is switch on a
    # feed somebody deliberately switched off — or off, one they switched on.
    conn = FakeConn()
    _discover(conn)
    upsert = conn.find("insert into public.merchant_feeds")[0]
    conflict = upsert.split("do update set", 1)[1]
    assert "enabled" not in conflict, conflict
    assert "removed_at = null" in conflict  # a feed that came back is back


def test_an_existing_merchant_is_updated_not_duplicated() -> None:
    conn = FakeConn(existing_merchant="merchant-existing")
    result = _discover(conn)
    assert result["advertisers_added"] == 0
    assert conn.find("insert into public.merchants") == []
    assert conn.find("update public.merchants")


def test_a_withdrawn_feed_is_marked_never_deleted() -> None:
    # Its products still exist, and a feed that returns next week should return
    # to the same row with its enabled flag intact.
    conn = FakeConn()
    _discover(conn)
    sweep = conn.find("update public.merchant_feeds f")[0]
    assert "removed_at = now()" in sweep
    assert "enabled = false" in sweep
    assert "delete" not in sweep.lower()


def test_a_discovered_merchant_can_actually_be_clicked_through() -> None:
    # The redirect service refuses any host the merchant has not declared, so a
    # merchant discovered with an empty allow-list would import thousands of
    # products that all fail with `no_allowed_domains`.
    conn = FakeConn()
    _discover(conn)
    insert = conn.find("insert into public.merchants")[0]
    assert "allowed_domains" in insert
    flat = " ".join(str(p) for p in conn.params)
    assert "awin1.com" in flat
    cfg = conn.find("insert into public.merchant_affiliate_config")
    assert cfg and "'ok'" in cfg[0]


def test_no_affiliate_tag_is_appended_to_an_already_tracked_link() -> None:
    # An Awin deep link arrives carrying the publisher id. Appending a second
    # tag sends two conflicting values, and some networks resolve that by
    # paying neither.
    conn = FakeConn()
    _discover(conn)
    cfg = conn.find("insert into public.merchant_affiliate_config")[0]
    assert "values ($1, null, null, 'ok')" in cfg
    assert "do nothing" in cfg  # a hand-configured merchant outranks discovery


def test_rediscovery_adds_the_click_host_without_removing_operator_domains() -> None:
    conn = FakeConn(existing_merchant="merchant-existing")
    _discover(conn)
    update = conn.find("update public.merchants")[0]
    assert "unnest(allowed_domains ||" in update, update


def test_the_click_host_is_stated_in_exactly_one_place() -> None:
    # The whole "a second Awin merchant needs no code change" claim rests on
    # this: nothing downstream hardcodes an advertiser, a feed id or a domain.
    from app.services.catalog.networks import discovery as module

    assert module.NETWORK_CLICK_HOSTS == ("awin1.com", "www.awin1.com")
    source = __import__("pathlib").Path(module.__file__).read_text(encoding="utf-8")
    assert source.count('"awin1.com"') == 0  # imported, never re-typed


# ── discovery never raises ──────────────────────────────────────────────────


def test_missing_credentials_are_a_skipped_run_not_a_crash() -> None:
    conn = FakeConn()

    class NoKey(AwinClient):
        async def discover(self) -> AwinDiscovery:
            raise AwinCredentialsMissing("AWIN_DATA_FEED_API_KEY is not set")

    result = asyncio.run(discover_awin(conn, client=NoKey()))
    assert result["status"] == "skipped"
    assert conn.find("update public.network_discovery_runs")  # the row is closed


def test_a_failure_closes_the_run_with_a_redacted_message() -> None:
    conn = FakeConn()

    class Boom(AwinClient):
        async def discover(self) -> AwinDiscovery:
            raise RuntimeError(f"HTTP 500 for https://x/apikey/{KEY}/fid/1/")

    result = asyncio.run(discover_awin(conn, client=Boom()))
    assert result["status"] == "failed"
    flat = " ".join(str(p) for p in conn.params)
    assert KEY not in flat
    assert "REDACTED" in flat


def test_an_empty_listing_is_a_success_that_changes_nothing() -> None:
    conn = FakeConn()
    result = _discover(conn, AwinDiscovery())
    assert result["status"] == "success"
    assert result["advertisers_seen"] == 0
    assert conn.find("insert into public.merchants") == []
    # And crucially: with nothing seen, nothing is swept away either.
    assert conn.find("update public.merchant_feeds f") == []


# ── slugs ───────────────────────────────────────────────────────────────────


def test_a_slug_is_stable_and_unique_per_advertiser() -> None:
    assert _slug("awin", "880044", "AliExpress PL") == "awin-880044-aliexpress-pl"
    # Two advertisers may legitimately share a display name; the id separates
    # them, so the slug cannot collide.
    assert _slug("awin", "1", "Shop") != _slug("awin", "2", "Shop")


@pytest.mark.parametrize("name", ["", "   ", "!!!", "Ünïcødé Shop ™"])
def test_a_slug_survives_any_advertiser_name(name: str) -> None:
    slug = _slug("awin", "7", name)
    assert re.fullmatch(r"[a-z0-9-]+", slug), slug
    assert slug.startswith("awin-7-")


# ── the retirement gate ─────────────────────────────────────────────────────


def _outcome(**kw: Any) -> SyncOutcome:
    outcome = SyncOutcome(run_id="r", status="running")
    for key, value in kw.items():
        setattr(outcome, key, value)
    return outcome


@pytest.mark.parametrize(
    ("complete", "may"),
    [(True, True), (False, False)],
)
def test_absence_only_means_absence_when_the_whole_source_was_read(
    complete: bool, may: bool
) -> None:
    assert may_reconcile(_outcome(source_complete=complete)) is may


def test_one_failed_feed_out_of_twenty_one_stops_all_retirement() -> None:
    # The live merchant has 21 feeds. Twenty succeeding and one timing out is
    # indistinguishable from a delisted category — except that it is not one.
    outcome = _outcome(
        source_complete=False,
        feeds_completed=[str(i) for i in range(20)],
        feeds_failed=["90001"],
    )
    assert may_reconcile(outcome) is False
    assert completed_status(outcome) == "partial"


def test_a_truncated_feed_stops_retirement_too() -> None:
    assert may_reconcile(_outcome(source_complete=False, truncated=True)) is False


@pytest.mark.parametrize(
    ("complete", "errors", "status"),
    [
        (True, [], "success"),
        (True, [{"e": "one bad row"}], "partial"),
        (False, [], "partial"),  # nothing failed to import, but we did not see it all
        (False, [{"e": "feed timed out"}], "partial"),
    ],
)
def test_an_incomplete_source_is_never_reported_as_a_clean_success(
    complete: bool, errors: list[dict[str, str]], status: str
) -> None:
    assert completed_status(_outcome(source_complete=complete, errors=errors)) == status
