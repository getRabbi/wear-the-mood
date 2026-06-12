"""RSS news fetcher (CLAUDE.md §1 pillar 5) — gated on the founder's source list.

Live fetching needs `feedparser` (BSD, commercial-OK) installed in the cron
service plus a configured feed list (NEWS_RSS_FEEDS). Until then the resolver
returns the stub, so importing this module never requires the package (the
import is lazy, inside fetch()).
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from datetime import UTC, datetime

from app.services.news.base import NewsArticle, NewsFetcher

log = logging.getLogger("fashionos.news")


class RssFetcher(NewsFetcher):
    name = "rss"

    def __init__(self, feeds: Sequence[str], *, per_feed: int = 10) -> None:
        self._feeds = [f.strip() for f in feeds if f.strip()]
        self._per_feed = per_feed

    async def fetch(self) -> list[NewsArticle]:
        import feedparser  # lazy: only needed when RSS is actually enabled

        articles: list[NewsArticle] = []
        for url in self._feeds:
            try:
                parsed = feedparser.parse(url)
            except Exception as exc:  # one bad feed must not stop the rest
                log.warning("rss parse failed for %s: %s", url, exc)
                continue
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
        image = None
        media = get("media_thumbnail") or get("media_content")
        if media:
            image = media[0].get("url")
        return NewsArticle(
            title=(get("title") or "").strip(),
            url=get("link"),
            source=source,
            image_url=image,
            published_at=published,
            content=(get("summary") or get("description") or "").strip(),
        )
