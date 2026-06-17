"""Stub news fetcher + summarizer — the defaults until sources are picked.

Keep the whole ingest loop (fetch -> summarize -> upsert) runnable and testable
with no network, no feedparser, and no AI key, mirroring the stub-first try-on /
push providers.
"""

from __future__ import annotations

from datetime import UTC, datetime

from app.services.news.base import (
    NewsArticle,
    NewsFetcher,
    NewsSummarizer,
    NewsSummary,
    fallback_summary,
)


class StubFetcher(NewsFetcher):
    name = "stub"

    async def fetch(self) -> list[NewsArticle]:
        now = datetime(2026, 1, 1, tzinfo=UTC)
        return [
            NewsArticle(
                title="Quiet luxury keeps its grip on the season",
                url="https://example.com/fashion/quiet-luxury",
                source="Wear The Mood Wire",
                image_url=None,
                published_at=now,
                content="Designers leaned into understated tailoring and muted "
                "palettes again this season, signalling that quiet luxury is "
                "more than a passing trend.",
            ),
            NewsArticle(
                title="Sneaker drops to watch this month",
                url="https://example.com/fashion/sneaker-drops",
                source="Wear The Mood Wire",
                image_url=None,
                published_at=now,
                content="A run of limited sneaker releases lands this month, "
                "from retro runners to collaborations with emerging labels.",
            ),
        ]


class StubSummarizer(NewsSummarizer):
    name = "stub"

    async def summarize(self, title: str, content: str) -> NewsSummary:
        return NewsSummary(summary=fallback_summary(title, content))
