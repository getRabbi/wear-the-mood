"""Server-side feature-flag checks (CLAUDE.md §16).

The /v1/flags router exposes flags to the app; this reads a SINGLE flag for backend
gating — e.g. the AI kill-switch that halts expensive try-on spend (§14). An absent
row falls back to ``default`` (so flags only need a row when you want to flip them).
"""

from __future__ import annotations

import asyncpg


async def flag_enabled(conn: asyncpg.Connection, key: str, *, default: bool) -> bool:
    """Whether feature flag ``key`` is enabled. Returns ``default`` if no row exists."""
    enabled = await conn.fetchval("select enabled from public.feature_flags where key = $1", key)
    return default if enabled is None else bool(enabled)
