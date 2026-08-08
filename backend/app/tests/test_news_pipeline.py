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
