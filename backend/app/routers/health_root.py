"""Root liveness/readiness probes (blueprint §4.6).

Mounted at ROOT (not ``/v1``) so platform health checks hit ``/healthz`` and
``/readyz`` directly. The legacy ``/v1/health`` stays for backward compatibility.
"""

from __future__ import annotations

from fastapi import APIRouter, Response

from app import __version__
from app.core.config import get_settings
from app.core.db import ping

router = APIRouter(tags=["health"])


@router.get("/healthz")
async def healthz() -> dict[str, str]:
    """Liveness: the process is alive. No DB, no external calls, fast (§4.6)."""
    return {"status": "ok"}


@router.get("/readyz")
async def readyz(response: Response) -> dict[str, object]:
    """Readiness: DB pool initialized + a lightweight ping; reports non-secret build
    metadata. Returns 503 when not ready (§4.6)."""
    settings = get_settings()
    try:
        db_ok = await ping()
    except Exception:
        db_ok = False
    if not db_ok:
        response.status_code = 503
    return {
        "status": "ready" if db_ok else "not_ready",
        "db": db_ok,
        "environment": settings.environment,
        "version": __version__,
        "commit": settings.git_sha or None,
    }
