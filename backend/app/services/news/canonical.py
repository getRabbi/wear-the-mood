"""Canonical URL normalization — the de-duplication key for news items.

A feed will hand out the same article many times under different URLs: with
`utm_*` campaign tags, with `?ref=` on a syndicated copy, with a `#section`
fragment, over http on one run and https on the next. The `url` unique index
from migration 0007 cannot see that those are one story, so a re-run creates
near-duplicates and the Newsroom fills with the same headline.

This produces a stable key from a URL, and `news_items.canonical_url` carries
it. `news_items.url` keeps whatever the feed actually said, because that is
where a reader should be sent.

SAFETY. This is normalization, not validation, and the two are deliberately
separate: anything that is not an ordinary absolute http(s) web URL returns
None rather than a "cleaned up" version. A `javascript:` or `data:` URL has no
canonical form worth computing, and quietly rewriting one into something that
looks safe is how it ends up rendered as a link.
"""

from __future__ import annotations

from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

# Tracking parameters carry no meaning for identity — the same article with and
# without them is the same article. Stripped by exact name; anything unknown is
# KEPT, because a query parameter can be load-bearing (`?id=123`) and dropping
# one would merge two genuinely different stories into one row.
_TRACKING_PREFIXES = ("utm_", "mc_", "pk_", "hsa_", "_hs")
_TRACKING_EXACT = frozenset(
    {
        "ref",
        "ref_src",
        "referrer",
        "source",
        "cmpid",
        "campaign",
        "fbclid",
        "gclid",
        "dclid",
        "gbraid",
        "wbraid",
        "msclkid",
        "igshid",
        "twclid",
        "yclid",
        "spm",
        "cmp",
        "ito",
        "at_medium",
        "at_campaign",
    }
)

# Ports that add nothing: an explicit :80/:443 is the same address as none.
_DEFAULT_PORTS = {"http": 80, "https": 443}

MAX_URL_LENGTH = 2048


def _is_tracking(key: str) -> bool:
    lowered = key.lower()
    return lowered in _TRACKING_EXACT or lowered.startswith(_TRACKING_PREFIXES)


def canonical_url(raw: str | None) -> str | None:
    """A stable identity key for `raw`, or None if it is not a usable web URL.

    None means "do not ingest this": without a key there is nothing to dedup on,
    and an item that cannot be deduped will be created again on every run.
    """
    if not raw or not isinstance(raw, str):
        return None
    candidate = raw.strip()
    if not candidate or len(candidate) > MAX_URL_LENGTH:
        return None

    try:
        parts = urlsplit(candidate)
    except ValueError:
        return None

    # Absolute http(s) only. Scheme-relative, mailto:, javascript:, data: and
    # bare paths all have no canonical form worth inventing.
    scheme = parts.scheme.lower()
    if scheme not in ("http", "https"):
        return None
    if not parts.hostname:
        return None
    # Credentials in a URL are never part of an article's identity, and echoing
    # them back into a stored row would persist somebody's secret.
    if parts.username or parts.password:
        return None

    host = parts.hostname.lower()
    # `www.` is a display choice, not a different publication.
    if host.startswith("www."):
        host = host[4:]

    netloc = host
    if parts.port and parts.port != _DEFAULT_PORTS.get(scheme):
        netloc = f"{host}:{parts.port}"

    # https is the canonical form of a site served on both. Two runs that
    # disagree about the scheme must not produce two rows.
    scheme = "https"

    path = parts.path or "/"
    # A trailing slash is not a different article — except at the root, where
    # removing it leaves an empty path.
    if len(path) > 1 and path.endswith("/"):
        path = path.rstrip("/") or "/"

    kept = [
        (k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if not _is_tracking(k)
    ]
    # Sorted so parameter order cannot produce two keys for one article.
    query = urlencode(sorted(kept), doseq=True)

    # The fragment is a position within a page, never a different page.
    return urlunsplit((scheme, netloc, path, query, ""))


def display_url(raw: str | None) -> str | None:
    """The URL a reader is actually sent to, or None if it is not safe to link.

    Deliberately NOT the canonical form: tracking parameters a publisher put
    there are theirs to keep, and stripping them can break a paywall handoff.
    This only refuses what must never be rendered as a link.
    """
    if not raw or not isinstance(raw, str):
        return None
    candidate = raw.strip()
    if not candidate or len(candidate) > MAX_URL_LENGTH:
        return None
    try:
        parts = urlsplit(candidate)
    except ValueError:
        return None
    if parts.scheme.lower() not in ("http", "https") or not parts.hostname:
        return None
    if parts.username or parts.password:
        return None
    return candidate
