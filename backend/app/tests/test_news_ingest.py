"""News ingestion (CLAUDE.md §1 pillar 5) — fetch/summarize resolvers, the
ingest upsert loop, and live SQL schema."""

from __future__ import annotations

import asyncio

import pytest

from app.core.config import get_settings
from app.services.news import (
    get_news_fetcher,
    get_news_summarizer,
    ingest,
)
from app.services.news.base import NewsArticle, NewsFetcher, NewsSummarizer, fallback_summary
from app.services.news.stub import StubFetcher, StubSummarizer


@pytest.fixture(autouse=True)
def _clear_cache():
    get_news_fetcher.cache_clear()
    get_news_summarizer.cache_clear()
    get_settings.cache_clear()
    yield
    get_news_fetcher.cache_clear()
    get_news_summarizer.cache_clear()
    get_settings.cache_clear()


class _RecConn:
    """Records executed statements for the no-DB ingest tests."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple]] = []

    async def execute(self, sql: str, *args) -> None:
        self.calls.append((sql, args))


# ── fallback summary ─────────────────────────────────────────────────────────


def test_fallback_summary_uses_lead_then_title() -> None:
    assert fallback_summary("T", "Short body.") == "Short body."
    assert fallback_summary("Title only", "") == "Title only"
    long = "word " * 200
    out = fallback_summary("T", long)
    assert out.endswith("…") and len(out) <= 282


# ── stub providers ───────────────────────────────────────────────────────────


def test_stub_fetcher_returns_articles() -> None:
    articles = asyncio.run(StubFetcher().fetch())
    assert len(articles) >= 1
    assert all(a.url for a in articles)


def test_stub_summarizer_summarizes() -> None:
    s = asyncio.run(StubSummarizer().summarize("Title", "Some body text."))
    assert s.summary == "Some body text."
    assert s.input_tokens is None


# ── resolvers ────────────────────────────────────────────────────────────────


def test_default_fetcher_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NEWS_PROVIDER", raising=False)
    get_settings.cache_clear()
    get_news_fetcher.cache_clear()
    assert get_news_fetcher().name == "stub"


def test_rss_without_feeds_falls_back_to_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEWS_PROVIDER", "rss")
    monkeypatch.setenv("NEWS_RSS_FEEDS", "")
    get_settings.cache_clear()
    get_news_fetcher.cache_clear()
    assert get_news_fetcher().name == "stub"


def test_default_summarizer_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")
    get_settings.cache_clear()
    get_news_summarizer.cache_clear()
    assert get_news_summarizer().name == "stub"


def test_real_key_routes_to_anthropic_summarizer(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-realish-key")
    get_settings.cache_clear()
    get_news_summarizer.cache_clear()
    assert get_news_summarizer().name == "anthropic"


# ── ingest loop ──────────────────────────────────────────────────────────────


def test_ingest_upserts_each_article() -> None:
    conn = _RecConn()
    n = asyncio.run(ingest(conn, StubFetcher(), StubSummarizer()))
    assert n == 2
    assert len(conn.calls) == 2  # 2 upserts, no usage rows for the stub summarizer
    title, summary = conn.calls[0][1][0], conn.calls[0][1][1]
    assert title and summary


class _NullUrlFetcher(NewsFetcher):
    name = "nullurl"

    async def fetch(self) -> list[NewsArticle]:
        return [NewsArticle(title="No link", url=None, content="body")]


def test_ingest_skips_articles_without_url() -> None:
    conn = _RecConn()
    n = asyncio.run(ingest(conn, _NullUrlFetcher(), StubSummarizer()))
    assert n == 0
    assert conn.calls == []


class _BoomSummarizer(NewsSummarizer):
    name = "boom"

    async def summarize(self, title: str, content: str):
        raise RuntimeError("llm down")


def test_ingest_falls_back_when_summarizer_fails() -> None:
    conn = _RecConn()
    n = asyncio.run(ingest(conn, StubFetcher(), _BoomSummarizer()))
    assert n == 2  # still upserts using the lead-of-text fallback
    assert len(conn.calls) == 2  # fallback has no tokens -> no usage rows


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_news_ingest_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.services.news import _UPSERT, _USAGE

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in (_UPSERT, _USAGE):
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
