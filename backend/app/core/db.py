"""Async Postgres access via asyncpg (CLAUDE.md §7 — transactional money-paths).

The backend connects with the service-role CONNECTION_STRING (bypasses RLS), so
every query MUST be scoped by the JWT-derived user_id. RLS remains defense-in-
depth for the app's direct Supabase access.
"""

from __future__ import annotations

import asyncpg

from app.core.config import get_settings

_pool: asyncpg.Pool | None = None


async def init_db() -> bool:
    """Create the connection pool if CONNECTION_STRING is set. Returns True when
    the pool was created, False when skipped (no DSN) so the app/tests still run.
    """
    global _pool
    if _pool is not None:
        return True

    dsn = get_settings().connection_string
    if not dsn:
        return False

    _pool = await asyncpg.create_pool(
        dsn=dsn,
        min_size=1,
        max_size=10,
        # Required for Supabase's transaction pooler (pgbouncer) — no server-side
        # prepared statements.
        statement_cache_size=0,
        ssl="require",
    )
    return True


async def close_db() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("Database pool is not initialized (call init_db()).")
    return _pool


async def ping() -> bool:
    """Lightweight connectivity check."""
    async with get_pool().acquire() as conn:
        return await conn.fetchval("select 1") == 1
