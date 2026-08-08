"""Feed adapters: how bytes become raw records.

One small interface so a new merchant network is a new class, not a change to
the writer. Nothing here interprets a record — that is `normalize` — and nothing
here touches the database.
"""

from __future__ import annotations

import csv
import io
import json
import logging
from typing import Any, Protocol

import httpx

log = logging.getLogger("fashionos.catalog.sources")

# A feed is somebody else's server. Both bounds are deliberate: the timeout
# stops one slow merchant from holding the cron open, and the size cap stops a
# runaway feed from being read into memory until the worker dies.
FETCH_TIMEOUT_SECONDS = 30.0
MAX_FEED_BYTES = 32 * 1024 * 1024
MAX_RECORDS = 20_000


class FeedFetchError(RuntimeError):
    """The feed could not be read. Counts as a run failure, with backoff."""


class FeedSource(Protocol):
    """Yields raw records for one merchant."""

    name: str

    async def fetch(self, url: str) -> list[dict[str, Any]]: ...


def _guard_size(content: bytes) -> None:
    if len(content) > MAX_FEED_BYTES:
        raise FeedFetchError(f"feed exceeds {MAX_FEED_BYTES} bytes")


async def _get(url: str, client: httpx.AsyncClient | None = None) -> bytes:
    owned = client is None
    client = client or httpx.AsyncClient(timeout=FETCH_TIMEOUT_SECONDS, follow_redirects=True)
    try:
        response = await client.get(url)
        response.raise_for_status()
        content = response.content
        _guard_size(content)
        return content
    except httpx.HTTPStatusError as exc:
        raise FeedFetchError(f"feed returned HTTP {exc.response.status_code}") from exc
    except httpx.RequestError as exc:
        raise FeedFetchError(f"feed unreachable: {exc.__class__.__name__}") from exc
    finally:
        if owned:
            await client.aclose()


class JsonFeedSource:
    """A JSON array, or an object with a `products` / `items` array."""

    name = "json"

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client

    async def fetch(self, url: str) -> list[dict[str, Any]]:
        content = await _get(url, self._client)
        try:
            parsed = json.loads(content)
        except json.JSONDecodeError as exc:
            raise FeedFetchError(f"feed is not valid JSON: {exc.msg}") from exc
        if isinstance(parsed, dict):
            for key in ("products", "items", "data"):
                if isinstance(parsed.get(key), list):
                    parsed = parsed[key]
                    break
        if not isinstance(parsed, list):
            raise FeedFetchError("feed JSON is not a list of products")
        return [r for r in parsed[:MAX_RECORDS] if isinstance(r, dict)]


class CsvFeedSource:
    """A header-row CSV. List columns accept `|`-separated values."""

    name = "csv"

    # Columns whose cells are lists rather than scalars.
    LIST_COLUMNS = ("image_urls", "images", "colors", "sizes", "country_availability")

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client

    async def fetch(self, url: str) -> list[dict[str, Any]]:
        content = await _get(url, self._client)
        try:
            text = content.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise FeedFetchError("feed is not UTF-8") from exc
        rows: list[dict[str, Any]] = []
        for row in csv.DictReader(io.StringIO(text)):
            record: dict[str, Any] = {}
            for key, value in row.items():
                if key is None:
                    continue
                key = key.strip()
                if key in self.LIST_COLUMNS:
                    record[key] = [p.strip() for p in (value or "").split("|") if p.strip()]
                else:
                    record[key] = (value or "").strip()
            rows.append(record)
            if len(rows) >= MAX_RECORDS:
                break
        return rows


class StaticFeedSource:
    """Records handed in directly. Used by tests and by dry-run validation."""

    name = "static"

    def __init__(self, records: list[dict[str, Any]]) -> None:
        self._records = records

    async def fetch(self, url: str) -> list[dict[str, Any]]:  # noqa: ARG002 - interface
        return list(self._records)


def get_source(feed_format: str, client: httpx.AsyncClient | None = None) -> FeedSource:
    """Adapter for a `merchant_feed_config.feed_format` code."""
    match (feed_format or "json").strip().lower():
        case "json":
            return JsonFeedSource(client)
        case "csv":
            return CsvFeedSource(client)
        case other:
            raise FeedFetchError(f"unsupported feed format: {other!r}")
