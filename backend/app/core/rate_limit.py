"""Lightweight DB-backed fixed-window rate limiting (CLAUDE.md §12).

The first server-side limiter — a generic bucket counter in ``public.rate_limits``
incremented atomically by the ``app_rate_limit`` SQL function (migration 0041).
Cross-worker safe because the counter lives in Postgres. Used for the public
referral redirect / token endpoints and the (stricter) authenticated claim.

Never raises on an internal counter error — a transient limiter failure must not
take down a public endpoint; it fails OPEN (allows the request) and is logged by
the caller if needed.
"""

from __future__ import annotations

import logging

import asyncpg
from fastapi import Request

from app.core.errors import ApiError
from app.models.common import ErrorCode

log = logging.getLogger("fashionos.rate_limit")


def client_ip(request: Request) -> str:
    """Best-effort client IP behind Cloudflare + Caddy, for rate-limit bucketing.
    Prefers CF-Connecting-IP, then the first X-Forwarded-For hop, then the peer."""
    cf = request.headers.get("cf-connecting-ip")
    if cf:
        return cf.strip()
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def enforce_rate_limit(
    conn: asyncpg.Connection, *, bucket: str, limit: int, window_seconds: int
) -> None:
    """Raise RATE_LIMITED (429) when [bucket] has exceeded [limit] hits in the
    current [window_seconds] window. Fails open on any limiter error."""
    try:
        allowed = await conn.fetchval(
            "select public.app_rate_limit($1, $2, $3)", bucket, limit, window_seconds
        )
    except Exception as exc:  # never let the limiter itself 500 a public route
        log.warning("rate limiter error for bucket prefix %s: %s", bucket.split(":")[0], exc)
        return
    if not allowed:
        raise ApiError(
            ErrorCode.RATE_LIMITED, "Too many requests. Please try again shortly.", 429
        )
