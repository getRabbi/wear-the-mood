"""RSS news fetcher (CLAUDE.md §1 pillar 5) — gated on the founder's source list.

Live fetching needs `feedparser` (BSD, commercial-OK) installed in the cron
service plus a configured feed list (NEWS_RSS_FEEDS). Until then the resolver
returns the stub, so importing this module never requires the package (the
import is lazy, inside fetch()).
"""

from __future__ import annotations

import logging
import re
from collections.abc import Sequence
from datetime import UTC, datetime

from app.services.news.base import NewsArticle, NewsFetcher

log = logging.getLogger("fashionos.news")


class NewsFetchError(RuntimeError):
    """A feed could not be read. Only raised in strict mode (see below)."""


# Where feeds ACTUALLY put the article image, in the order worth trying.
#
# This used to read `media:thumbnail` / `media:content` and nothing else, which
# is one of several conventions and not the most common one. The cost was
# visible on Discover: Vogue publishes `media:*` so its card carried a picture,
# while Hypebeast — which embeds the image in the description HTML — produced a
# blank card next to it. A rail of editorial cards where some are pictures and
# some are empty rectangles reads as broken rather than as sparse.
#
# Deliberately NOT a page fetch. Some feeds (Highsnobiety among them) carry no
# image anywhere in the XML, and the only way to get one is to fetch the article
# and read its `og:image`. That is a per-article HTTP request inside a cron, with
# its own timeout, failure and politeness questions, and it is a separate
# decision from reading what the feed already told us.
_IMG_SRC = re.compile(r"""<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']""", re.IGNORECASE)


def _first_media_url(entry: object) -> str | None:
    """`media:thumbnail` / `media:content` — the RSS-media convention."""
    get = entry.get
    for key in ("media_thumbnail", "media_content"):
        media = get(key)
        if media:
            url = media[0].get("url")
            if url:
                return str(url)
    return None


def _first_enclosure_url(entry: object) -> str | None:
    """An `<enclosure>` (or any link) whose type says it is an image.

    Checked before the HTML body because it is a declaration rather than an
    inference: the feed is telling us this IS the article's image.
    """
    for link in entry.get("links") or ():
        if str(link.get("type", "")).startswith("image/") and link.get("href"):
            return str(link["href"])
    return None


def _first_html_image(body: str) -> str | None:
    """The first `<img src>` in the description/content HTML.

    The loosest source and therefore the last one tried — a feed that embeds a
    tracking pixel or a source logo before the real photo would hand us that
    instead. Bounded to http(s) so a `data:` blob never becomes an image_url the
    client would try (and fail) to load from a CDN.
    """
    if not body:
        return None
    for match in _IMG_SRC.finditer(body):
        url = match.group(1).strip()
        if url.lower().startswith(("http://", "https://")):
            return url
    return None


def _entry_image(entry: object, body: str) -> str | None:
    """The article's image, from whichever convention this feed happens to use."""
    return _first_media_url(entry) or _first_enclosure_url(entry) or _first_html_image(body)


class RssFetcher(NewsFetcher):
    name = "rss"

    def __init__(self, feeds: Sequence[str], *, per_feed: int = 10, strict: bool = False) -> None:
        """`strict` decides what an unreadable feed MEANS, and it differs by caller.

        The legacy multi-feed path passes several URLs at once, and there one
        bad feed must not cost the others their articles — so it skips and
        continues, which is why this class swallowed everything.

        The per-source pipeline fetches exactly ONE feed, and there a failure is
        the run's outcome. Swallowing it there made a dead source report
        `success` with zero articles: `health`, `consecutive_failures` and the
        backoff all stayed green while nothing was being ingested, which is
        worse than an error because nobody goes looking.

        Note that `feedparser` does not raise on a failed fetch — it returns a
        result with `bozo` set and no entries — so catching exceptions was never
        enough on its own.
        """
        self._feeds = [f.strip() for f in feeds if f.strip()]
        self._per_feed = per_feed
        self._strict = strict

    def _check(self, url: str, parsed: object) -> None:
        """Raise when a feed produced nothing AND reported a problem.

        Deliberately requires BOTH. `bozo` is set for minor XML nits that a
        publisher may carry for years while still serving perfectly good
        entries, so bozo alone is not a failure. No entries alone is not one
        either — a quiet feed is allowed to be quiet.
        """
        if not self._strict:
            return
        entries = getattr(parsed, "entries", []) or []
        if entries:
            return
        status = getattr(parsed, "status", None)
        if isinstance(status, int) and status >= 400:
            raise NewsFetchError(f"feed returned HTTP {status}")
        if getattr(parsed, "bozo", 0):
            exc = getattr(parsed, "bozo_exception", None)
            raise NewsFetchError(f"feed unreadable: {exc.__class__.__name__}: {exc}"[:300])

    async def fetch(self) -> list[NewsArticle]:
        import feedparser  # lazy: only needed when RSS is actually enabled

        articles: list[NewsArticle] = []
        for url in self._feeds:
            try:
                parsed = feedparser.parse(url)
            except Exception as exc:  # one bad feed must not stop the rest
                log.warning("rss parse failed for %s: %s", url, exc)
                if self._strict:
                    raise NewsFetchError(f"feed unreadable: {exc}") from exc
                continue
            self._check(url, parsed)
            source = parsed.feed.get("title") if parsed.feed else None
            for entry in parsed.entries[: self._per_feed]:
                articles.append(self._to_article(entry, source))
        return articles

    @staticmethod
    def _to_article(entry: object, source: str | None) -> NewsArticle:
        get = entry.get  # feedparser entries are dict-like
        published = None
        struct = get("published_parsed") or get("updated_parsed")
        if struct is not None:
            published = datetime(*struct[:6], tzinfo=UTC)
        body = (get("summary") or get("description") or "").strip()
        return NewsArticle(
            title=(get("title") or "").strip(),
            url=get("link"),
            source=source,
            image_url=_entry_image(entry, body),
            published_at=published,
            content=body,
        )
