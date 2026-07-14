"""Public referral redirect (CLAUDE.md §24) — mounted at ROOT (not /v1), so the
canonical share URL is https://wearthemood.com/r/<CODE> (proxied to the API).

GET /r/<code> records the click (mints an opaque, single-use, time-limited
attribution token) and 302s to the Play listing carrying it as the install
`referrer`. Invalid/disabled codes land on the plain marketing page — never an
exception, never an open redirect. Rate limited per IP.
"""

from __future__ import annotations

from fastapi import APIRouter, Path, Request
from fastapi.responses import RedirectResponse

from app.core.db import get_pool
from app.core.rate_limit import client_ip, enforce_rate_limit
from app.services.referrals import resolve_redirect

router = APIRouter(tags=["referral-redirect"])


@router.get("/r/{code}")
async def referral_redirect(
    request: Request,
    code: str = Path(max_length=32),
) -> RedirectResponse:
    """Attribute the click and forward PLATFORM-AWARE: Android → Play listing
    (deferred-install token), iOS/other → the invite landing (visible code), and
    an unknown/disabled code → the plain landing page."""
    is_android = "android" in request.headers.get("user-agent", "").lower()
    async with get_pool().acquire() as conn:
        await enforce_rate_limit(
            conn, bucket=f"rredir:{client_ip(request)}", limit=60, window_seconds=3600
        )
        target = await resolve_redirect(conn, code, is_android=is_android)
    # 302 (temporary) so each open re-attributes; no-store so CDNs/Cloudflare
    # don't cache a per-user token; no-referrer to avoid leaking the code onward.
    response = RedirectResponse(url=target, status_code=302)
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response
