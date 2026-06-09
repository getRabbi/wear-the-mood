"""Try-on worker — import + live DB checks (skip without CONNECTION_STRING)."""

from __future__ import annotations

import asyncio
import importlib

import pytest

from app.core.config import get_settings
from app.workers.tryon_worker import claim_next_job


def test_worker_imports() -> None:
    importlib.import_module("app.workers.worker")
    importlib.import_module("app.workers.tryon_worker")


async def _connect():
    import asyncpg

    return await asyncpg.connect(
        dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
    )


def test_claim_returns_none_when_empty_live() -> None:
    """No queued jobs yet -> claim is a no-op returning None. Rolled back so the
    claiming UPDATE can never affect real rows."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        conn = await _connect()
        try:
            tr = conn.transaction()
            await tr.start()
            try:
                assert await claim_next_job(conn) is None
            finally:
                await tr.rollback()
        finally:
            await conn.close()

    asyncio.run(run())


def test_worker_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "update public.tryon_jobs set status = 'failed', error = $2 where id = $1::uuid",
        "update public.tryon_jobs set status = 'done', error = null where id = $1::uuid",
        "insert into public.tryon_results (job_id, user_id, result_image_url) "
        "values ($1::uuid, $2::uuid, $3)",
        "insert into public.ai_usage_log "
        "(user_id, provider, task, images, estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, 'tryon', 1, $3, $4, $5)",
    ]

    async def run() -> None:
        conn = await _connect()
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
