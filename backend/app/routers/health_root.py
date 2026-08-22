"""Root liveness/readiness probes (blueprint §4.6).

Mounted at ROOT (not ``/v1``) so platform health checks hit ``/healthz`` and
``/readyz`` directly. The legacy ``/v1/health`` stays for backward compatibility.
"""

from __future__ import annotations

from fastapi import APIRouter, Response

from app import __version__
from app.core.config import get_settings
from app.core.db import get_pool, ping
from app.core.schema_ledger import evaluate_capabilities, schema_summary

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
    # SCHEMA CAPABILITY, not just reachability (the 0071 lesson). A dyno whose
    # database is missing a migration this build depends on is not ready, and
    # answering 200 because a `select 1` succeeded is precisely how build 28
    # went out over a database with no `cutout_temp` job type and nothing
    # anywhere said a word. Best-effort: a probe that itself errors must not
    # take a healthy dyno out of rotation, so it degrades to "unknown".
    schema: dict[str, object] = {"ready": None, "error": "not_checked"}
    if db_ok:
        try:
            async with get_pool().acquire() as conn:
                schema = schema_summary(await evaluate_capabilities(conn))
        except Exception as exc:  # noqa: BLE001
            schema = {"ready": None, "error": type(exc).__name__}
    schema_ok = schema.get("ready") is not False
    if not db_ok or not schema_ok:
        response.status_code = 503
    return {
        "status": "ready" if (db_ok and schema_ok) else "not_ready",
        "db": db_ok,
        "schema": schema,
        "environment": settings.environment,
        "version": __version__,
        "commit": settings.git_sha or None,
        # Operator-visible local-first state (local BG §2.3). "ready" alone was never
        # enough: a deploy that dropped LOCAL_CUTOUT_UPLOAD_ENABLED answered 200 here
        # while every device silently reverted to the BiRefNet worker. One of
        # enabled | gate_off | emergency_disabled | storage_unavailable.
        "local_cutout": settings.local_cutout_health,
    }
