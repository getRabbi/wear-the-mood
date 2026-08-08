"""Newsroom hardening: canonical URLs, the publish gate, and backoff.

The point of these is the dedup key. Everything else in the newsroom degrades
gracefully; a canonical URL that is wrong either merges two different stories
into one row or fills the feed with the same headline.
"""

from __future__ import annotations

import pytest

from app.services.news.canonical import canonical_url, display_url
from app.services.news.pipeline import _backoff_minutes, initial_status

ARTICLE = "https://www.example.com/fashion/story"


# ── canonical identity ──────────────────────────────────────────────────────


def test_the_same_article_under_tracking_tags_is_one_key() -> None:
    # This is the duplicate the 0007 url index cannot see: one story, four URLs.
    variants = [
        ARTICLE,
        ARTICLE + "?utm_source=twitter&utm_medium=social",
        ARTICLE + "#the-section",
        ARTICLE + "/",
        "http://www.example.com/fashion/story",
        "https://example.com/fashion/story",
        ARTICLE + "?fbclid=abc123",
    ]
    keys = {canonical_url(v) for v in variants}
    assert len(keys) == 1, keys
    assert keys.pop() == "https://example.com/fashion/story"


def test_a_meaningful_query_parameter_is_kept() -> None:
    # Dropping an unknown parameter could merge two genuinely different stories.
    assert canonical_url("https://example.com/a?id=123") == "https://example.com/a?id=123"


def test_query_parameter_order_does_not_change_the_key() -> None:
    a = canonical_url("https://example.com/a?b=2&a=1")
    b = canonical_url("https://example.com/a?a=1&b=2")
    assert a == b


@pytest.mark.parametrize(
    "bad",
    [
        None,
        "",
        "   ",
        "javascript:alert(1)",
        "data:text/html,<h1>x",
        "mailto:someone@example.com",
        "//example.com/protocol-relative",
        "/just/a/path",
        "not a url",
        "https://user:pw@example.com/a",  # credentials are never identity
        "ftp://example.com/a",
    ],
)
def test_anything_that_is_not_an_ordinary_web_url_has_no_canonical_form(bad: str | None) -> None:
    # Normalization is NOT validation: refusing is safer than "cleaning up" a
    # javascript: URL into something that renders as a link.
    assert canonical_url(bad) is None


def test_an_absurdly_long_url_is_refused() -> None:
    assert canonical_url("https://example.com/" + "a" * 4000) is None


def test_the_display_url_keeps_the_publishers_own_parameters() -> None:
    # Stripping these can break a paywall handoff — they are the publisher's to
    # keep. display_url only refuses what must never be rendered as a link.
    tagged = ARTICLE + "?utm_source=x"
    assert display_url(tagged) == tagged
    assert canonical_url(tagged) != tagged  # but the KEY drops them
    assert display_url("javascript:alert(1)") is None
    assert display_url("https://user:pw@example.com/a") is None


# ── the publish gate ────────────────────────────────────────────────────────


def test_an_untrusted_source_lands_in_review_not_live() -> None:
    # "Do not blindly auto-publish unknown sources", enforced in code: the
    # column defaults false, so a source added carelessly cannot publish itself.
    assert initial_status(False) == "review_required"


def test_only_an_explicitly_trusted_source_publishes_directly() -> None:
    assert initial_status(True) == "published"


# ── backoff ─────────────────────────────────────────────────────────────────


def test_source_backoff_grows_and_is_capped() -> None:
    assert _backoff_minutes(1) == 30
    assert _backoff_minutes(2) == 60
    assert _backoff_minutes(99) == 24 * 60


# ── summary bounding (found on live feeds) ──────────────────────────────────


def test_a_summary_is_bounded_at_ingest() -> None:
    # The models mostly return one or two sentences, but "mostly" is not a
    # guarantee, and the length of what we store IS our exposure on
    # "a summary, never the article".
    from app.services.news.pipeline import MAX_SUMMARY_CHARS, clamp_summary

    long_text = "word " * 500
    out = clamp_summary(long_text)
    assert len(out) <= MAX_SUMMARY_CHARS + 1  # +1 for the ellipsis
    assert out.endswith("…")


def test_a_short_summary_is_left_alone() -> None:
    from app.services.news.pipeline import clamp_summary

    assert clamp_summary("Two sentences. That is all.") == "Two sentences. That is all."


def test_clamping_normalises_whitespace() -> None:
    from app.services.news.pipeline import clamp_summary

    assert clamp_summary("  a\n\n b  ") == "a b"


def test_clamping_handles_nothing() -> None:
    from app.services.news.pipeline import clamp_summary

    assert clamp_summary(None) == ""


# ── unreadable feeds (found on a live dead host) ────────────────────────────


class _Parsed:
    def __init__(self, entries=None, bozo=0, status=None, exc=None):
        self.entries = entries or []
        self.bozo = bozo
        self.bozo_exception = exc
        if status is not None:
            self.status = status
        self.feed = {}


def test_strict_mode_raises_on_an_unreadable_feed() -> None:
    # A dead source used to report success with zero articles, so `health`,
    # `consecutive_failures` and the backoff all stayed green while nothing was
    # ingested — worse than an error, because nobody goes looking.
    from app.services.news.rss import NewsFetchError, RssFetcher

    f = RssFetcher(["https://x.test/rss"], strict=True)
    with pytest.raises(NewsFetchError):
        f._check("u", _Parsed(bozo=1, exc=OSError("dns")))


def test_strict_mode_raises_on_an_http_error() -> None:
    from app.services.news.rss import NewsFetchError, RssFetcher

    f = RssFetcher(["https://x.test/rss"], strict=True)
    with pytest.raises(NewsFetchError):
        f._check("u", _Parsed(status=404))


def test_a_feed_that_returned_entries_is_fine_even_if_bozo() -> None:
    # `bozo` is set for minor XML nits a publisher may carry for years while
    # still serving perfectly good entries.
    from app.services.news.rss import RssFetcher

    f = RssFetcher(["https://x.test/rss"], strict=True)
    f._check("u", _Parsed(entries=[{"title": "x"}], bozo=1, exc=ValueError("nit")))


def test_a_quiet_feed_is_allowed_to_be_quiet() -> None:
    from app.services.news.rss import RssFetcher

    f = RssFetcher(["https://x.test/rss"], strict=True)
    f._check("u", _Parsed(entries=[], bozo=0, status=200))


def test_the_legacy_multi_feed_path_still_skips_rather_than_raises() -> None:
    # The old env-driven path passes several URLs at once; there one bad feed
    # must not cost the others their articles.
    from app.services.news.rss import RssFetcher

    f = RssFetcher(["https://a.test/rss", "https://b.test/rss"])
    f._check("u", _Parsed(bozo=1, exc=OSError("dns")))  # no raise
