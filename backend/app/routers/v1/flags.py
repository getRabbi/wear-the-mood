"""Feature flags (CLAUDE.md §16).

A read-only view of the service-role `feature_flags` table so the app can gate
features for gradual rollout. Every new feature ships behind its own flag, OFF by
default; a flag missing from the response is treated as OFF by the client. This
endpoint never writes — flags are toggled directly in the table (or an admin
tool later).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.flags import FlagsResponse

router = APIRouter(tags=["flags"])


@router.get("/flags", response_model=FlagsResponse)
async def get_flags(
    user: CurrentUser = Depends(get_current_user),
) -> FlagsResponse:
    """All feature flags and whether each is enabled. Authenticated (the app
    fetches these once signed in); per-user `rollout` targeting can layer on
    later without changing this contract."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch("select key, enabled from public.feature_flags")
    return FlagsResponse(flags={r["key"]: r["enabled"] for r in rows})
