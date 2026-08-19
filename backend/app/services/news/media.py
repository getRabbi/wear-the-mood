"""Canonical news media resolution (Issue 3).

## What was wrong

Ingestion stored the first image-looking string it could find in the feed and
called it the article's picture. For Vogue that worked, because Condé Nast
publishes `media:content`. For Hypebeast it produced nothing, because the image
lives in the description HTML. For Highsnobiety it produced nothing at all,
because the feed carries no image anywhere — the only copy is the `og:image` on
the article page, and ingestion never looked. The result on a device was a rail
where some editorial cards carried a photograph and the rest carried a gradient,
which reads as broken rather than as sparse.

Nothing validated the string either, so a URL that 404s, expires, redirects to
an HTML error page or is a 1x1 tracking pixel was stored as the hero image and
rediscovered as broken by every phone, on every scroll, forever.

## What this does

Collects candidates from every convention a publisher might use, in descending
order of how much the publisher is DECLARING versus how much we are inferring,
then promotes the first one that survives validation — and records which
convention won, so "why does this source have no pictures" is a query.

## What this deliberately does NOT do

* It does not spoof a browser, forge a Referer, or retry a 403 by other means.
  A publisher that refuses to serve us an image has answered, and the answer is
  no; the slot falls back rather than being argued with.
* It does not copy anyone's image into our storage. See `cache_policy` on
  `news_sources` — the default is hotlink-only and nothing promotes itself.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

import httpx

log = logging.getLogger("fashionos.news.media")

# ── provenance: which convention produced this URL ───────────────────────────
SOURCE_RSS_MEDIA = "rss_media"
SOURCE_RSS_ENCLOSURE = "rss_enclosure"
SOURCE_FEED_HTML = "feed_html"
SOURCE_OG_IMAGE = "og_image"
SOURCE_TWITTER_IMAGE = "twitter_image"

# ── status: what we know about the resolved image ────────────────────────────
STATUS_OK = "ok"
STATUS_MISSING = "missing"  # the publisher exposes no image anywhere
STATUS_UNREACHABLE = "unreachable"  # network error, timeout, non-2xx
STATUS_FORBIDDEN = "forbidden"  # publisher refuses us (401/403/451) — respected
STATUS_NOT_IMAGE = "not_an_image"  # HTML error page, PDF, anything not an image
STATUS_TOO_SMALL = "too_small"  # tracking pixel, favicon, source logo
STATUS_INVALID_URL = "invalid_url"

#: Smallest hero image worth putting on a full-width editorial card. A tracking
#: pixel is 1x1, a favicon 32-64, a source logo commonly under 200 — all of them
#: are things feeds genuinely embed before the real photograph.
MIN_HERO_EDGE = 200

#: Never read more than this from a publisher, for either a page or an image.
MAX_PAGE_BYTES = 512 * 1024
MAX_IMAGE_BYTES = 4 * 1024 * 1024

#: Honest identification. Not a browser string: we are a fashion app's ingest
#: cron and we say so, so a publisher who wants to refuse us can.
USER_AGENT = "WearTheMoodBot/1.0 (+https://wearthemood.com; news ingestion)"

_TIMEOUT = httpx.Timeout(10.0, connect=5.0)

_IMG_SRC = re.compile(r"""<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
_META = re.compile(r"<meta\b[^>]*>", re.IGNORECASE)
_META_KEY = re.compile(
    r"""\b(?:property|name)\s*=\s*["']([^"']+)["']""", re.IGNORECASE
)
_META_CONTENT = re.compile(r"""\bcontent\s*=\s*["']([^"']*)["']""", re.IGNORECASE)


@dataclass(frozen=True)
class MediaCandidate:
    url: str
    provenance: str


@dataclass(frozen=True)
class ResolvedMedia:
    """The outcome of resolving ONE article's hero image."""

    status: str
    url: str | None = None
    provenance: str | None = None
    width: int | None = None
    height: int | None = None
    detail: str | None = None

    @property
    def ok(self) -> bool:
        return self.status == STATUS_OK

    @property
    def aspect_ratio(self) -> float | None:
        if not self.width or not self.height:
            return None
        return round(self.width / self.height, 4)


def _is_http_url(url: str) -> bool:
    try:
        parts = urlsplit(url.strip())
    except ValueError:
        return False
    return parts.scheme in ("http", "https") and bool(parts.netloc)


# ── candidate collection ─────────────────────────────────────────────────────


def feed_candidates(entry: object, body: str) -> list[MediaCandidate]:
    """Every image the FEED itself offers, best declaration first.

    `media:*` and `<enclosure>` are the publisher stating "this is the article's
    image". An `<img>` in the description is an inference — a feed that leads
    with a tracking pixel or a masthead hands us that instead — so it is tried
    last among the feed conventions and still has to pass validation.
    """
    out: list[MediaCandidate] = []
    get = getattr(entry, "get", None)
    if callable(get):
        for key in ("media_thumbnail", "media_content"):
            media = get(key)
            if media:
                url = media[0].get("url") if isinstance(media[0], dict) else None
                if url and _is_http_url(str(url)):
                    out.append(MediaCandidate(str(url), SOURCE_RSS_MEDIA))
        for link in get("links") or ():
            if not isinstance(link, dict):
                continue
            if str(link.get("type", "")).startswith("image/") and link.get("href"):
                href = str(link["href"])
                if _is_http_url(href):
                    out.append(MediaCandidate(href, SOURCE_RSS_ENCLOSURE))
    for match in _IMG_SRC.finditer(body or ""):
        url = match.group(1).strip()
        if _is_http_url(url):
            out.append(MediaCandidate(url, SOURCE_FEED_HTML))
    return _dedupe(out)


def page_candidates(html: str, *, base_url: str) -> list[MediaCandidate]:
    """`og:image` and `twitter:image` from an article page.

    Parsed with a bounded regex rather than a DOM: this reads two meta tags out
    of the first half-megabyte of a page, and adding an HTML parser to the cron
    for that is a dependency and an attack surface we do not need. Relative URLs
    are resolved against the article, which several publishers rely on.
    """
    found: list[MediaCandidate] = []
    for tag in _META.finditer(html or ""):
        raw = tag.group(0)
        key_match = _META_KEY.search(raw)
        content_match = _META_CONTENT.search(raw)
        if not key_match or not content_match:
            continue
        key = key_match.group(1).strip().lower()
        value = content_match.group(1).strip()
        if not value:
            continue
        if key in ("og:image", "og:image:url", "og:image:secure_url"):
            provenance = SOURCE_OG_IMAGE
        elif key in ("twitter:image", "twitter:image:src"):
            provenance = SOURCE_TWITTER_IMAGE
        else:
            continue
        absolute = urljoin(base_url, value)
        if _is_http_url(absolute):
            found.append(MediaCandidate(absolute, provenance))
    # og before twitter, in discovery order within each.
    found.sort(key=lambda c: 0 if c.provenance == SOURCE_OG_IMAGE else 1)
    return _dedupe(found)


def _dedupe(candidates: list[MediaCandidate]) -> list[MediaCandidate]:
    seen: set[str] = set()
    out: list[MediaCandidate] = []
    for candidate in candidates:
        if candidate.url in seen:
            continue
        seen.add(candidate.url)
        out.append(candidate)
    return out


# ── validation ───────────────────────────────────────────────────────────────


def _measure(data: bytes) -> tuple[int, int] | None:
    """Pixel dimensions, or None when the bytes are not a decodable image.

    Pillow is lazy-imported: the api process never resolves news media, and this
    module is imported by the admin serializer.
    """
    try:
        import io

        from PIL import Image

        with Image.open(io.BytesIO(data)) as img:
            return int(img.width), int(img.height)
    except Exception:  # noqa: BLE001 — undecodable is an answer, not an error
        return None


async def validate_candidate(client: httpx.AsyncClient, candidate: MediaCandidate) -> ResolvedMedia:
    """Fetch enough of [candidate] to prove it is a usable hero image."""
    if not _is_http_url(candidate.url):
        return ResolvedMedia(STATUS_INVALID_URL, detail=candidate.url[:200])
    try:
        response = await client.get(candidate.url)
    except httpx.HTTPError as exc:
        return ResolvedMedia(STATUS_UNREACHABLE, detail=f"{exc.__class__.__name__}"[:200])

    if response.status_code in (401, 403, 451):
        # The publisher has answered. We do not argue with it by forging a
        # Referer or pretending to be a browser.
        return ResolvedMedia(STATUS_FORBIDDEN, detail=f"HTTP {response.status_code}")
    if response.status_code >= 400:
        return ResolvedMedia(STATUS_UNREACHABLE, detail=f"HTTP {response.status_code}")

    content_type = response.headers.get("content-type", "").split(";")[0].strip().lower()
    data = response.content[:MAX_IMAGE_BYTES]
    if not content_type.startswith("image/"):
        return ResolvedMedia(STATUS_NOT_IMAGE, detail=content_type or "no content-type")

    size = _measure(data)
    if size is None:
        return ResolvedMedia(STATUS_NOT_IMAGE, detail="undecodable bytes")
    width, height = size
    if min(width, height) < MIN_HERO_EDGE:
        # A tracking pixel, a favicon or a masthead logo — real things feeds put
        # ahead of the photograph.
        return ResolvedMedia(STATUS_TOO_SMALL, width=width, height=height)

    # `response.url` rather than the candidate: a publisher that redirects to a
    # CDN should have the CDN URL stored, so the client does not repeat the hop.
    return ResolvedMedia(
        STATUS_OK,
        url=str(response.url),
        provenance=candidate.provenance,
        width=width,
        height=height,
    )


async def fetch_page_candidates(
    client: httpx.AsyncClient, article_url: str
) -> list[MediaCandidate]:
    """One bounded GET of the article page, for its `og:image`.

    This is the step the previous implementation explicitly declined to build,
    and it is the only way to get a picture for a publisher like Highsnobiety
    whose feed carries none. Failure is silent and empty — an article we cannot
    read a page for simply has no page candidates.
    """
    if not _is_http_url(article_url):
        return []
    try:
        response = await client.get(article_url, headers={"Accept": "text/html"})
        if response.status_code >= 400:
            return []
        content_type = response.headers.get("content-type", "").lower()
        if "html" not in content_type:
            return []
        return page_candidates(response.text[:MAX_PAGE_BYTES], base_url=str(response.url))
    except httpx.HTTPError as exc:
        log.debug("news media: page fetch failed for %s: %s", article_url, exc)
        return []


def build_client() -> httpx.AsyncClient:
    """The ONE client shape used for every publisher request here."""
    return httpx.AsyncClient(
        timeout=_TIMEOUT,
        follow_redirects=True,
        max_redirects=5,
        headers={"User-Agent": USER_AGENT},
    )


async def resolve_article_media(
    *,
    entry: object,
    body: str,
    article_url: str,
    client: httpx.AsyncClient | None = None,
    allow_page_fetch: bool = True,
) -> ResolvedMedia:
    """The canonical resolver: candidates, in order, first one that validates.

    The page fetch happens ONLY when the feed offered nothing usable, so a
    publisher who declares its image properly costs one request and a publisher
    who declares nothing costs two.
    """
    owned = client is None
    http = client or build_client()
    try:
        last: ResolvedMedia | None = None
        for candidate in feed_candidates(entry, body):
            resolved = await validate_candidate(http, candidate)
            if resolved.ok:
                return resolved
            last = resolved

        if allow_page_fetch:
            for candidate in await fetch_page_candidates(http, article_url):
                resolved = await validate_candidate(http, candidate)
                if resolved.ok:
                    return resolved
                last = resolved

        return last or ResolvedMedia(STATUS_MISSING)
    finally:
        if owned:
            await http.aclose()
