"""News ingestion interfaces (CLAUDE.md §1 pillar 5, §2.1).

Fetching (RSS/API) and summarization go behind these so the cron never hardcodes
a source or a provider. Stubs are the default everywhere; the real RSS fetcher
(feedparser) and Claude Haiku summarizer are selected by env once the founder
picks sources — the whole ingest loop is testable now.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime

from pydantic import BaseModel


class NewsArticle(BaseModel):
    """A raw fetched article, before summarization."""

    title: str
    url: str | None = None
    source: str | None = None
    image_url: str | None = None
    published_at: datetime | None = None
    content: str = ""  # raw text/snippet to summarize


class NewsSummary(BaseModel):
    """A short editorial summary, with token usage for cost logging (§14)."""

    summary: str
    input_tokens: int | None = None
    output_tokens: int | None = None


class NewsFetcher(ABC):
    name: str

    @abstractmethod
    async def fetch(self) -> list[NewsArticle]:
        """Return the latest articles from the configured sources, or raise."""
        raise NotImplementedError


class NewsSummarizer(ABC):
    name: str

    @abstractmethod
    async def summarize(self, title: str, content: str) -> NewsSummary:
        """Return a 1-2 sentence summary of an article, or raise."""
        raise NotImplementedError


def fallback_summary(title: str, content: str, *, limit: int = 280) -> str:
    """Deterministic non-LLM summary: the cleaned lead of the content (or the
    title). Used by the stub and as a safety net when the LLM call fails."""
    text = " ".join((content or "").split()).strip()
    if not text:
        return title.strip()
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0].rstrip(",.;:") + "…"


__all__ = [
    "NewsArticle",
    "NewsFetcher",
    "NewsSummarizer",
    "NewsSummary",
    "fallback_summary",
]
