"""Idempotency-Key store + credit-spend SQL — live DB checks.

These hit the real Supabase schema and so SKIP when CONNECTION_STRING is unset
(e.g. in CI), mirroring test_db.py. Every test runs inside a transaction that is
rolled back, so nothing is persisted. `idempotency_keys` has no FK on user_id,
which lets the round-trip use synthetic UUIDs.
"""

from __future__ import annotations

import asyncio
import uuid

import pytest

from app.core import idempotency as idem
from app.core.config import get_settings


def _dsn() -> str:
    return get_settings().connection_string


async def _connect():
    import asyncpg

    return await asyncpg.connect(dsn=_dsn(), statement_cache_size=0, ssl="require")


def test_idempotency_roundtrip_live() -> None:
    if not _dsn():
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        conn = await _connect()
        try:
            tr = conn.transaction()
            await tr.start()
            try:
                key, user_id, endpoint = str(uuid.uuid4()), str(uuid.uuid4()), "POST /v1/tryon"

                # Unknown key -> nothing stored yet.
                assert await idem.get_stored_response(conn, key, user_id, endpoint) is None

                # First reserve wins; the retry sees it already reserved.
                assert await idem.reserve_key(conn, key, user_id, endpoint) is True
                assert await idem.reserve_key(conn, key, user_id, endpoint) is False

                # Reserved-but-unfinished still has no stored response.
                assert await idem.get_stored_response(conn, key, user_id, endpoint) is None

                # After storing, the same key replays the exact response.
                await idem.store_response(conn, key, user_id, endpoint, 202, {"job_id": "abc"})
                stored = await idem.get_stored_response(conn, key, user_id, endpoint)
                assert stored is not None
                assert stored.status_code == 202
                assert stored.response == {"job_id": "abc"}

                # Same key, different user must not read another user's response.
                other = str(uuid.uuid4())
                assert await idem.get_stored_response(conn, key, other, endpoint) is None
            finally:
                await tr.rollback()
        finally:
            await conn.close()

    asyncio.run(run())


def test_credit_spend_sql_valid_live() -> None:
    """Validate the spend statements against the live schema without mutating —
    a server-side prepare type-checks tables/columns/casts."""
    if not _dsn():
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "insert into public.credits (user_id) values ($1::uuid) on conflict (user_id) do nothing",
        "select balance, daily_free_used, daily_reset_on, current_date as today "
        "from public.credits where user_id = $1::uuid for update",
        "update public.credits set balance=$2, daily_free_used=$3, daily_reset_on=$4 "
        "where user_id=$1::uuid",
    ]

    async def run() -> None:
        conn = await _connect()
        try:
            for s in stmts:
                await conn.prepare(s)  # raises if columns/types/casts don't check
        finally:
            await conn.close()

    asyncio.run(run())
