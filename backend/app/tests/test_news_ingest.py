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


def test_stub_provider_selects_stub_fetcher(monkeypatch: pytest.MonkeyPatch) -> None:
    # Force stub explicitly: a real .env may set NEWS_PROVIDER=rss, which pydantic
    # reads from the file even after delenv — so assert the stub path hermetically.
    monkeypatch.setenv("NEWS_PROVIDER", "stub")
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
    monkeypatch.setenv("OPENAI_API_KEY", "")
    get_settings.cache_clear()
    get_news_summarizer.cache_clear()
    assert get_news_summarizer().name == "stub"


def test_real_key_routes_to_anthropic_summarizer(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-realish-key")
    monkeypatch.setenv("OPENAI_API_KEY", "")
    get_settings.cache_clear()
    get_news_summarizer.cache_clear()
    assert get_news_summarizer().name == "anthropic"


def test_openai_is_summarizer_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-real")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-real")
    monkeypatch.setenv("LLM_PRIMARY", "anthropic")
    get_settings.cache_clear()
    get_news_summarizer.cache_clear()
    assert get_news_summarizer().name == "anthropic+openai"


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


# ── where a feed actually puts its image ─────────────────────────────────────
#
# Discover shows editorial cards side by side, so an article with no picture is
# not a smaller card — it is an empty rectangle next to a full one, which reads
# as broken. The extractor used to understand ONE convention (`media:*`), which
# is why a Vogue card carried a photo and the Hypebeast card beside it did not.
# These pin each shape that a real feed in the founder's list actually uses.


class _Entry(dict):
    """feedparser entries are dict-like; that is the whole contract used here."""


def _article(**entry: object):
    from app.services.news.rss import RssFetcher

    return RssFetcher._to_article(_Entry(title="T", link="https://x/a", **entry), "Src")


def test_media_thumbnail_is_read() -> None:
    a = _article(media_thumbnail=[{"url": "https://cdn/x.jpg"}])
    assert a.image_url == "https://cdn/x.jpg"


def test_media_content_is_read_when_there_is_no_thumbnail() -> None:
    a = _article(media_content=[{"url": "https://cdn/y.jpg"}])
    assert a.image_url == "https://cdn/y.jpg"


def test_an_image_enclosure_is_read() -> None:
    """A declared enclosure beats guessing from HTML, so it is tried first."""
    a = _article(
        links=[
            {"type": "text/html", "href": "https://x/a"},
            {"type": "image/jpeg", "href": "https://cdn/enc.jpg"},
        ],
        summary='<p><img src="https://cdn/inline.jpg"></p>',
    )
    assert a.image_url == "https://cdn/enc.jpg"


def test_an_image_embedded_in_the_description_is_read() -> None:
    """The Hypebeast shape: no media tags at all, the photo is in the HTML.

    This is the case that shipped a blank card next to a full one.
    """
    a = _article(summary='<p>Lead</p><img src="https://cdn/inline.jpg" width="600">')
    assert a.image_url == "https://cdn/inline.jpg"


def test_a_data_uri_is_never_taken_as_the_image() -> None:
    """A `data:` blob is not something the client can load from a CDN, and a
    tracking pixel is not the article's picture."""
    a = _article(summary='<img src="data:image/gif;base64,R0lGOD">')
    assert a.image_url is None


def test_a_feed_with_no_image_anywhere_yields_none_rather_than_a_guess() -> None:
    """The Highsnobiety shape. Honest absence — the card shows its placeholder
    instead of a wrong picture. Getting one needs the article's og:image, which
    is a page fetch and a separate decision."""
    a = _article(summary="<p>Just words.</p>")
    assert a.image_url is None
