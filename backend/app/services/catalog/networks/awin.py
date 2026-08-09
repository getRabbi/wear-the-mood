"""Awin connector: account discovery, feed download, and the row adapter.

Built against the LIVE account rather than the documentation, and the live
account contradicted two reasonable assumptions:

* The feed-list endpoint returns **CSV**, not JSON.
* Membership status is ``active`` / ``Not Joined`` — not "Joined".

Both are handled as observed. Where this file states a fact about Awin's shape,
it was read off a real response.

CREDENTIALS. Awin's listing hands back a download URL with the API key embedded
in the URL PATH (``/apikey/<key>/``). That URL is never stored and never
returned: only the numeric feed id is persisted, and the authenticated URL is
rebuilt here, in the backend, per request. Every error string that could carry
one goes through :func:`redact` first — an exception is a log line, a Sentry
event and an admin error field, and a key that reaches any of those is leaked.

That discipline covers strings THIS codebase writes. It does not cover strings
written by libraries: httpx logs the full request URL at INFO, which under the
crons' ``basicConfig(level=INFO)`` printed the key straight into production logs.
Silencing that logger is therefore part of the credential handling, not a
logging preference — see the guard below.
"""

from __future__ import annotations

import csv
import io
import logging
import os
import zlib
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from urllib.parse import quote

import httpx

log = logging.getLogger("fashionos.catalog.awin")

# httpx logs "HTTP Request: GET <full url>" at INFO, and this API carries the key
# in the URL PATH — so the HTTP library re-emits, verbatim, the credential that
# redact() exists to keep out of logs. redact() can only cover strings this
# codebase writes; it never saw httpx's.
#
# The guard lives at import, next to the secret, rather than in each entrypoint:
# any process that can import this module can leak, and "remember to silence
# httpx in your cron too" is a rule that gets forgotten exactly once. WARNING
# still surfaces real transport failures.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

LIST_ENDPOINT = "https://productdata.awin.com/datafeed/list/apikey/{key}"
DOWNLOAD_ENDPOINT = "https://productdata.awin.com/datafeed/download"

# The columns we ask Awin for. A subset of what it offers, chosen because each
# one maps onto something the catalog actually stores; asking for more would
# only make the download bigger.
FEED_COLUMNS = (
    "aw_product_id",
    "merchant_product_id",
    "product_name",
    "description",
    "brand_name",
    "merchant_category",
    "category_name",
    "category_id",
    "search_price",
    "product_price_old",
    "currency",
    "merchant_image_url",
    "aw_image_url",
    "aw_deep_link",
    "merchant_deep_link",
    "merchant_id",
    "merchant_name",
    "data_feed_id",
    "stock_quantity",
    "language",
    "last_updated",
    "delivery_cost",
    "valid_to",
)

# Bounds. A network feed is somebody else's file and can be any size; the live
# account already exposes one with 154k rows.
FETCH_TIMEOUT_SECONDS = 300.0
MAX_COMPRESSED_BYTES = 256 * 1024 * 1024
MAX_DECOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024
MAX_ROWS_PER_FEED = 500_000
MAX_ERROR_SAMPLES = 20

# Adult content is requested OFF. Awin's own listing URLs arrive with
# `adultcontent/1`; we never use those URLs, and every URL we build sets 0.
ADULT_CONTENT = "0"


class AwinCredentialsMissing(RuntimeError):
    """No publisher id / API key in the environment. Discovery cannot run."""


class AwinFetchError(RuntimeError):
    """A listing or feed download failed. Message is already redacted."""


def _api_key() -> str:
    return (os.getenv("AWIN_DATA_FEED_API_KEY") or "").strip()


def redact(text: object) -> str:
    """Remove the API key from anything about to be emitted.

    Applied to every message that leaves this module — exceptions, log lines,
    run-history error fields. The key is also matched case-insensitively and in
    percent-encoded form, because a URL that has been through quoting no longer
    contains the literal.
    """
    value = str(text)
    key = _api_key()
    if key:
        for variant in {key, key.lower(), key.upper(), quote(key)}:
            if variant:
                value = value.replace(variant, "***REDACTED***")
    # Belt and braces: anything that looks like an apikey path segment goes,
    # even a key this process does not hold (a stale URL from a database row,
    # say, or another environment's).
    return _APIKEY_PATH.sub("/apikey/***REDACTED***", value)


import re  # noqa: E402 - used by redact above, kept close to it

_APIKEY_PATH = re.compile(r"/apikey/[^/\s\"']+", re.IGNORECASE)


@dataclass(frozen=True)
class AwinFeed:
    """One row of Awin's feed listing. No credentials — the URL is dropped."""

    advertiser_id: str
    advertiser_name: str
    feed_id: str
    feed_name: str
    language: str | None
    region: str | None
    vertical: str | None
    membership_status: str
    product_count: int | None
    last_imported: datetime | None
    last_checked: datetime | None

    @property
    def is_accessible(self) -> bool:
        """Whether this publisher account may actually download the feed.

        Observed values are ``active`` and ``Not Joined``; the listing returns
        every advertiser on the network, not only ours. Anything that is not
        recognisably active is treated as inaccessible, so a status Awin adds
        later fails closed rather than silently importing a programme we have
        not joined.
        """
        return self.membership_status.strip().lower() in {"active", "joined"}


# The listing columns absence reasoning depends on. If one of these is missing
# the response is not the document we think it is, and no conclusion may be
# drawn from a feed not appearing in it.
REQUIRED_LISTING_COLUMNS = ("Advertiser ID", "Feed ID", "Membership Status")


@dataclass
class AwinDiscovery:
    """The result of one listing read.

    `complete` carries the same meaning here as on a feed download, and for the
    same reason: it is the ONLY thing that makes "this feed was not in the
    listing" mean "the advertiser withdrew it" rather than "our request went
    wrong". A truncated body, a missing header, or a row we could not parse all
    leave it False.
    """

    feeds: list[AwinFeed] = field(default_factory=list)
    total_rows: int = 0
    errors: list[str] = field(default_factory=list)
    complete: bool = False

    @property
    def accessible(self) -> list[AwinFeed]:
        return [f for f in self.feeds if f.is_accessible]

    def advertisers(self) -> dict[str, list[AwinFeed]]:
        """Accessible feeds grouped by advertiser id."""
        out: dict[str, list[AwinFeed]] = {}
        for feed in self.accessible:
            out.setdefault(feed.advertiser_id, []).append(feed)
        return out


def _int(value: str | None) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _stamp(value: str | None) -> datetime | None:
    raw = (value or "").strip()
    if not raw:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    return None


class AwinClient:
    """Talks to Awin. The only place the API key is read or used."""

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self.publisher_id = (os.getenv("AWIN_PUBLISHER_ID") or "").strip()

    @property
    def configured(self) -> bool:
        return bool(self.publisher_id and _api_key())

    def _require(self) -> str:
        key = _api_key()
        if not key or not self.publisher_id:
            raise AwinCredentialsMissing(
                "AWIN_PUBLISHER_ID / AWIN_DATA_FEED_API_KEY are not set in this environment"
            )
        return key

    def feed_url(self, feed_id: str, *, language: str = "en") -> str:
        """The authenticated download URL. Built here, never stored.

        `adultcontent/0` on every URL we construct: Wear The Mood does not
        request adult catalogues, and Awin's own listing URLs come with 1.
        """
        key = self._require()
        columns = quote(",".join(FEED_COLUMNS), safe="")
        return (
            f"{DOWNLOAD_ENDPOINT}/apikey/{key}/fid/{quote(str(feed_id), safe='')}"
            f"/format/csv/language/{quote(language, safe='')}"
            f"/delimiter/%2C/compression/gzip/adultcontent/{ADULT_CONTENT}"
            f"/columns/{columns}/"
        )

    async def discover(self) -> AwinDiscovery:
        """Read the publisher's feed listing.

        Returns EVERY row, accessible or not, so the caller can report how many
        advertisers exist versus how many we may actually use. Filtering happens
        at :meth:`AwinDiscovery.accessible`.

        Sets `complete` only when the whole document arrived and every row of it
        parsed. Anything less and the caller must not treat a missing feed as a
        withdrawn one.
        """
        key = self._require()
        owned = self._client is None
        client = self._client or httpx.AsyncClient(
            timeout=FETCH_TIMEOUT_SECONDS, follow_redirects=True
        )
        try:
            response = await client.get(LIST_ENDPOINT.format(key=key))
            response.raise_for_status()
            body = response.content
            declared = response.headers.get("content-length")
            text = body.decode("utf-8", errors="replace")
        except httpx.HTTPStatusError as exc:
            raise AwinFetchError(
                redact(f"Awin feed list returned HTTP {exc.response.status_code}")
            ) from None
        except httpx.RequestError as exc:
            raise AwinFetchError(redact(f"Awin feed list unreachable: {exc!r}")) from None
        finally:
            if owned:
                await client.aclose()

        result = AwinDiscovery()

        # A body shorter than the server said it would send is a truncated
        # transfer. httpx usually raises on this; when it does not — a proxy
        # closing cleanly mid-response, say — the bytes still lie about what the
        # account holds, and this is where that is caught.
        if declared is not None:
            try:
                if len(body) != int(declared):
                    result.errors.append(f"listing truncated: {len(body)} of {int(declared)} bytes")
                    return result
            except ValueError:
                pass

        reader = csv.DictReader(io.StringIO(text))
        missing = [c for c in REQUIRED_LISTING_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            # Not the document we asked for: an error page, a changed schema, or
            # an empty body. Every feed would look absent, which is exactly the
            # conclusion that must never be drawn from a bad response.
            result.errors.append(f"listing header missing: {', '.join(missing)}")
            return result

        unreadable = 0
        try:
            rows = list(reader)
        except csv.Error as exc:
            result.errors.append(f"listing is not readable CSV: {exc}")
            return result

        for row in rows:
            result.total_rows += 1
            # A short row means the CSV is ragged — the file was cut, or quoting
            # went wrong somewhere above. Either way the rows around it are
            # suspect too.
            if row.get(None) is not None or any(v is None for v in row.values()):
                unreadable += 1
                if len(result.errors) < MAX_ERROR_SAMPLES:
                    result.errors.append("listing row does not match the header")
                continue
            advertiser_id = (row.get("Advertiser ID") or "").strip()
            feed_id = (row.get("Feed ID") or "").strip()
            if not advertiser_id or not feed_id:
                unreadable += 1
                if len(result.errors) < MAX_ERROR_SAMPLES:
                    result.errors.append("listing row without an advertiser or feed id")
                continue
            result.feeds.append(
                AwinFeed(
                    advertiser_id=advertiser_id,
                    advertiser_name=(row.get("Advertiser Name") or "").strip(),
                    feed_id=feed_id,
                    feed_name=(row.get("Feed Name") or "").strip(),
                    language=(row.get("Language") or "").strip() or None,
                    region=(row.get("Primary Region") or "").strip() or None,
                    vertical=(row.get("Vertical") or "").strip() or None,
                    membership_status=(row.get("Membership Status") or "").strip(),
                    product_count=_int(row.get("No of products")),
                    last_imported=_stamp(row.get("Last Imported")),
                    last_checked=_stamp(row.get("Last Checked")),
                )
            )

        # Complete means: the whole body arrived, the header was the one we
        # expect, and EVERY row parsed. One unreadable row is enough to withhold
        # the conclusion, because a row we could not read may well have been the
        # feed we are about to call withdrawn.
        result.complete = unreadable == 0
        return result


# ── feed download ───────────────────────────────────────────────────────────


@dataclass
class FeedReadResult:
    """One feed's download. `complete` is the load-bearing field."""

    feed_id: str
    rows: list[dict[str, Any]] = field(default_factory=list)
    complete: bool = False
    truncated: bool = False
    compressed_bytes: int = 0
    error: str | None = None


async def read_feed(
    client_or_none: httpx.AsyncClient | None,
    url: str,
    feed_id: str,
    *,
    max_rows: int = MAX_ROWS_PER_FEED,
) -> FeedReadResult:
    """Download, decompress and parse one gzip CSV feed.

    Streams the body so a large feed is not held twice in memory, and
    decompresses incrementally so a 150k-row file becomes rows as it arrives
    rather than one enormous string.

    `complete` is only True when the transfer finished, the gzip stream ended
    cleanly and no cap was hit. Every other path — HTTP error, timeout, byte
    cap, row cap, corrupt gzip, decode failure — leaves it False, because the
    caller uses it to decide whether products absent from this feed may be
    retired.
    """
    result = FeedReadResult(feed_id=feed_id)
    owned = client_or_none is None
    client = client_or_none or httpx.AsyncClient(
        timeout=FETCH_TIMEOUT_SECONDS, follow_redirects=True
    )
    # wbits=47 lets zlib auto-detect gzip vs zlib framing, so a merchant serving
    # deflate instead of gzip still reads.
    decompressor = zlib.decompressobj(47)
    pending = ""
    header: list[str] | None = None
    decompressed = 0

    try:
        async with client.stream("GET", url) as response:
            if response.status_code >= 400:
                result.error = redact(f"feed returned HTTP {response.status_code}")
                return result
            async for chunk in response.aiter_bytes():
                result.compressed_bytes += len(chunk)
                if result.compressed_bytes > MAX_COMPRESSED_BYTES:
                    result.truncated = True
                    result.error = "compressed byte cap reached"
                    return result
                try:
                    block = decompressor.decompress(chunk)
                except zlib.error as exc:
                    result.error = redact(f"gzip stream corrupt: {exc}")
                    return result
                if not block:
                    continue
                decompressed += len(block)
                if decompressed > MAX_DECOMPRESSED_BYTES:
                    result.truncated = True
                    result.error = "decompressed byte cap reached"
                    return result
                pending += block.decode("utf-8", errors="replace")
                # Keep the last partial line in the buffer; a chunk boundary
                # lands mid-row roughly always.
                lines = pending.split("\n")
                pending = lines.pop()
                header, stop = _consume(lines, header, result, max_rows)
                if stop:
                    return result

        # Whatever the stream had left.
        tail = decompressor.flush()
        if tail:
            pending += tail.decode("utf-8", errors="replace")
        if pending.strip():
            header, stop = _consume(pending.split("\n"), header, result, max_rows)
            if stop:
                return result

        if not decompressor.eof:
            # The gzip member never terminated: the connection ended early.
            result.error = "feed ended before the gzip stream completed"
            result.truncated = True
            return result

        result.complete = True
        return result

    except httpx.TimeoutException:
        result.error = "feed timed out"
        return result
    except httpx.RequestError as exc:
        result.error = redact(f"feed unreachable: {exc!r}")
        return result
    except Exception as exc:  # noqa: BLE001 - never let a feed crash a run
        result.error = redact(f"{exc.__class__.__name__}: {exc}")
        return result
    finally:
        if owned:
            await client.aclose()


def _consume(
    lines: list[str], header: list[str] | None, result: FeedReadResult, max_rows: int
) -> tuple[list[str] | None, bool]:
    """Parse buffered lines into rows. Returns (header, should_stop)."""
    for line in lines:
        if not line.strip():
            continue
        try:
            fields = next(csv.reader([line]))
        except csv.Error:
            # One malformed row is skipped, not fatal — but it does NOT make the
            # feed incomplete: we read the bytes, the merchant sent a bad row.
            if len(result.rows) < max_rows:
                continue
            continue
        if header is None:
            header = [f.strip() for f in fields]
            continue
        if len(result.rows) >= max_rows:
            result.truncated = True
            result.error = "row cap reached"
            return header, True
        # strict=False on purpose: a row with the wrong field count is a
        # malformed row, not a reason to abandon the feed. Missing trailing
        # fields simply become absent, and the normalizer refuses the row on
        # its own terms with a reason the run reports.
        result.rows.append(dict(zip(header, fields, strict=False)))
    return header, False


class AwinMultiFeedSource:
    """Every enabled feed for one merchant, read as a single source.

    Implements the catalog importer's source interface, so the existing
    `sync_merchant` consumes it without knowing Awin exists.

    The whole point of this class is the completeness contract. `sync_merchant`
    may only retire products it did not see if the ENTIRE merchant source was
    read — with 21 feeds, one timing out while the other 20 succeed would
    otherwise look exactly like the merchant delisting a category.
    """

    name = "awin"

    def __init__(
        self,
        client: AwinClient,
        feeds: list[dict[str, Any]],
        *,
        http: httpx.AsyncClient | None = None,
    ) -> None:
        self._client = client
        self._feeds = feeds
        self._http = http
        self.complete: bool = False
        self.truncated: bool = False
        self.feeds_completed: list[str] = []
        self.feeds_failed: list[str] = []
        self.errors: list[dict[str, str]] = []
        self.source_count: int | None = None

    async def fetch(self, url: str) -> list[dict[str, Any]]:  # noqa: ARG002 - interface
        rows: list[dict[str, Any]] = []
        declared = 0
        owned = self._http is None
        http = self._http or httpx.AsyncClient(timeout=FETCH_TIMEOUT_SECONDS, follow_redirects=True)
        try:
            for feed in self._feeds:
                feed_id = str(feed["network_feed_id"])
                language = (feed.get("language") or "en").strip().lower()[:2] or "en"
                if feed.get("product_count"):
                    declared += int(feed["product_count"])
                try:
                    url_for_feed = self._client.feed_url(feed_id, language=language)
                except AwinCredentialsMissing as exc:
                    self.feeds_failed.append(feed_id)
                    self.errors.append({"feed_id": feed_id, "error": redact(str(exc))})
                    continue

                read = await read_feed(http, url_for_feed, feed_id)
                if read.complete:
                    self.feeds_completed.append(feed_id)
                    rows.extend(read.rows)
                else:
                    # A partially-read feed's rows are still imported — they are
                    # real products and updating them is correct. What is NOT
                    # correct is concluding anything from their absence, and
                    # that is what `complete` guards.
                    self.feeds_failed.append(feed_id)
                    self.truncated = self.truncated or read.truncated
                    rows.extend(read.rows)
                    if len(self.errors) < MAX_ERROR_SAMPLES:
                        self.errors.append(
                            {"feed_id": feed_id, "error": read.error or "incomplete read"}
                        )
        finally:
            if owned:
                await http.aclose()

        self.source_count = declared or None
        # Complete means EVERY required feed was fully read, and at least one
        # was required. An empty feed list is not a complete read of a
        # merchant's catalogue; it is a merchant with nothing enabled.
        self.complete = bool(self._feeds) and not self.feeds_failed and not self.truncated
        return rows
