"""News ingestion (CLAUDE.md §1 pillar 5). Resolve a fetcher + summarizer by
config (stub by default), then fetch -> summarize -> upsert into news_items."""

from __future__ import annotations

import logging
from decimal import Decimal
from functools import lru_cache

import asyncpg

from app.core.config import get_settings
from app.services.llm.routing import provider_order
from app.services.news.base import (
    NewsArticle,
    NewsFetcher,
    NewsSummarizer,
    NewsSummary,
    fallback_summary,
)
from app.services.news.stub import StubFetcher, StubSummarizer

log = logging.getLogger("fashionos.news")

__all__ = [
    "NewsArticle",
    "NewsFetcher",
    "NewsSummarizer",
    "NewsSummary",
    "get_news_fetcher",
    "get_news_summarizer",
    "ingest",
]

# Upsert by url so re-runs refresh rather than duplicate (partial unique index,
# migration 0007). Only articles that carry a url reach this statement.
_UPSERT = """
    insert into public.news_items (title, summary, source, url, image_url, published_at)
    values ($1, $2, $3, $4, $5, $6)
    on conflict (url) where url is not null
    do update set title = excluded.title,
                  summary = excluded.summary,
                  source = excluded.source,
                  image_url = excluded.image_url,
                  published_at = excluded.published_at
"""

_USAGE = """
    insert into public.ai_usage_log
      (user_id, provider, model, task, input_tokens, output_tokens, images,
       estimated_usd, success)
    values (null, $1, $2, 'news_summary', $3, $4, 0, $5, true)
"""

# Rough Claude Haiku-class rates for cost visibility (§14); refine later.
_USD_PER_INPUT_TOK = Decimal("1") / Decimal("1000000")
_USD_PER_OUTPUT_TOK = Decimal("5") / Decimal("1000000")


@lru_cache
def get_news_fetcher() -> NewsFetcher:
    """RSS when NEWS_PROVIDER=rss and feeds are configured; stub otherwise so the
    ingest loop stays runnable without sources/feedparser (CLAUDE.md §1)."""
    settings = get_settings()
    if settings.news_provider == "rss" and settings.news_rss_feeds_list:
        try:
            from app.services.news.rss import RssFetcher

            return RssFetcher(settings.news_rss_feeds_list)
        except Exception as exc:  # missing feedparser -> stay runnable
            log.warning("RSS fetcher unavailable (%s); falling back to stub.", exc)
    return StubFetcher()


class _FallbackSummarizer(NewsSummarizer):
    """Try each backend in order (primary first, the other as fallback, §2.1)."""

    def __init__(self, backends: list[NewsSummarizer]) -> None:
        self._backends = backends
        self.name = "+".join(b.name for b in backends)

    async def summarize(self, title: str, content: str) -> NewsSummary:
        last: Exception | None = None
        for backend in self._backends:
            try:
                return await backend.summarize(title, content)
            except Exception as exc:
                last = exc
                log.warning("news summarizer %s failed: %s", backend.name, exc)
        raise last if last else RuntimeError("no summarizer backend")


@lru_cache
def get_news_summarizer() -> NewsSummarizer:
    """Claude Haiku and/or GPT by key + LLM_PRIMARY (the other is the automatic
    fallback, §2.1); stub (lead-of-text) when neither key is set."""
    settings = get_settings()
    backends: list[NewsSummarizer] = []
    for name in provider_order():
        if name == "anthropic":
            from app.services.news.anthropic_summarizer import AnthropicSummarizer

            backends.append(
                AnthropicSummarizer(settings.anthropic_api_key, settings.anthropic_model_news)
            )
        else:
            from app.services.news.openai_summarizer import OpenAISummarizer

            backends.append(OpenAISummarizer(settings.openai_api_key, settings.openai_model_chat))
    if not backends:
        return StubSummarizer()
    return backends[0] if len(backends) == 1 else _FallbackSummarizer(backends)


def _cost(summary: NewsSummary) -> Decimal:
    if summary.input_tokens is None:
        return Decimal("0")
    return (
        Decimal(summary.input_tokens) * _USD_PER_INPUT_TOK
        + Decimal(summary.output_tokens or 0) * _USD_PER_OUTPUT_TOK
    )


async def ingest(conn: asyncpg.Connection, fetcher: NewsFetcher, summarizer: NewsSummarizer) -> int:
    """Fetch -> summarize -> upsert. Returns the number of articles written.
    Summary failures fall back to the article's lead so one bad item — or a down
    LLM — never stops the run. Each real (non-stub) summary is logged (§14)."""
    articles = await fetcher.fetch()
    model = get_settings().anthropic_model_news
    saved = 0
    for a in articles:
        if not a.url:  # need a stable key to dedup on
            continue
        try:
            summary = await summarizer.summarize(a.title, a.content)
        except Exception as exc:  # resilience over a hard failure
            log.warning("summarize failed for %s: %s", a.url, exc)
            summary = NewsSummary(summary=fallback_summary(a.title, a.content))
        await conn.execute(
            _UPSERT, a.title, summary.summary, a.source, a.url, a.image_url, a.published_at
        )
        if summarizer.name != "stub" and summary.input_tokens is not None:
            await conn.execute(
                _USAGE,
                summarizer.name,
                model,
                summary.input_tokens,
                summary.output_tokens,
                _cost(summary),
            )
        saved += 1
    log.info("news ingest: %d articles upserted (%s/%s)", saved, fetcher.name, summarizer.name)
    return saved
