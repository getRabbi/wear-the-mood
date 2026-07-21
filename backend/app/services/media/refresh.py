"""Refresh an expiring first-party media URL to a fresh one (CLAUDE.md §8, §11).

ROOT CAUSE it fixes: the mobile app loads the closet (and body gallery) and holds
the resulting **signed** URLs — an R2 presigned GET (`…r2.cloudflarestorage.com/
<private_bucket>/<key>?X-Amz-Expires=3600…`) or a Supabase signed URL
(`…/storage/v1/object/sign/<bucket>/<path>?token=…`). Both expire after
`r2_signed_url_ttl` (1 h). If the user assembles an outfit and submits a try-on
after the URL has expired, the FIRST server that fetches it — OpenAI moderation at
submit, then FASHN in the worker — gets "could not download file" and the whole
render fails with "That image couldn't be read."

The object itself never moved, only its short-lived signature aged. So at submit
AND at worker time we re-mint a FRESH URL from the SAME object key/path using our
own trusted credentials. Public CDN URLs and third-party URLs (sample garments,
studio models on the CDN) never expire and pass straight through. Any parse/sign
failure passes the original URL through unchanged — freshening must never itself
break a try-on.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from urllib.parse import unquote, urlsplit

from app.core.config import get_settings
from app.services.media import get_storage_provider
from app.services.storage import create_signed_url

log = logging.getLogger("fashionos.media.refresh")


@dataclass(frozen=True)
class _Refreshable:
    """A first-party expiring URL decoded to what we need to re-sign it."""

    scheme: str  # "r2_private" | "supabase_sign"
    bucket: str
    object_key: str


def classify_url(url: str, *, private_bucket: str) -> _Refreshable | None:
    """Pure (no I/O): decode an R2-private-presigned or Supabase-signed URL to its
    bucket + object key. Returns None for anything else (public CDN, third-party,
    non-URL) — those are passed through untouched. Unit-testable offline."""
    if not url or not url.startswith("http"):
        return None
    try:
        s = urlsplit(url)
    except ValueError:
        return None
    host = s.netloc.lower()
    path = s.path

    # R2 presigned GET over the S3 endpoint: https://<acct>.r2.cloudflarestorage.com/<bucket>/<key>
    if host.endswith(".r2.cloudflarestorage.com"):
        segs = path.lstrip("/").split("/", 1)
        if len(segs) == 2 and segs[0] == private_bucket and segs[1]:
            return _Refreshable("r2_private", private_bucket, unquote(segs[1]))
        return None  # public R2 bucket or an unrecognised layout → leave as-is

    # Supabase signed URL: <proj>.supabase.co/storage/v1/object/sign/<bucket>/<path>
    marker = "/storage/v1/object/sign/"
    if marker in path:
        after = path.split(marker, 1)[1]
        bucket, _, obj = after.partition("/")
        if bucket and obj:
            return _Refreshable("supabase_sign", bucket, unquote(obj))
    return None


async def freshen_media_url(url: str) -> str:
    """Return a FRESH signed URL for a first-party expiring URL, else the original.

    Never raises: any failure (parse, missing object, provider error) returns the
    input unchanged so the caller's existing validation/moderation still runs."""
    ref = classify_url(url, private_bucket=get_settings().active_private_bucket)
    if ref is None:
        return url
    try:
        if ref.scheme == "r2_private":
            return await get_storage_provider().view_url(
                object_key=ref.object_key, visibility="private"
            )
        return await create_signed_url(ref.bucket, ref.object_key)
    except Exception as exc:  # noqa: BLE001 - freshening is best-effort
        log.warning("freshen_media_url could not re-sign (%s); passing original through", exc)
        return url


async def freshen_all(urls: list[str]) -> list[str]:
    """Freshen a stack of URLs in order (small N: an outfit is ≤ a handful)."""
    return [await freshen_media_url(u) for u in urls]
