"""Live DB tests for the credit money-paths (Phase 2 · subsystem 2).

Skipped without a DSN. Every test runs inside a transaction that is ROLLED BACK,
so it never leaves residue. Validates against the real 0022 schema: the grant
primitive (idempotent, set/add/topup), the multi-bucket spend (free→plan→topup,
idempotent, insufficient), and RLS (an authenticated client cannot grant itself
credits — only the service role / owner can).
"""

from __future__ import annotations

import asyncio
import json
import uuid

import asyncpg
import pytest

from app.core.config import get_settings
from app.core.credits import InsufficientCreditsError, spend_credit


def _skip_if_no_dsn() -> str:
    dsn = get_settings().connection_string
    if not dsn:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")
    return dsn


async def _a_profile(conn: asyncpg.Connection) -> str | None:
    return await conn.fetchval("select id::text from public.profiles limit 1")


def test_grant_is_idempotent_and_targets_buckets() -> None:
    dsn = _skip_if_no_dsn()

    async def run() -> None:
        conn = await asyncpg.connect(dsn, statement_cache_size=0, ssl="require")
        try:
            uid = await _a_profile(conn)
            if uid is None:
                pytest.skip("no profiles on this DB")
            tx = conn.transaction()
            await tx.start()
            try:
                ref = f"test:{uuid.uuid4()}"
                r1 = await conn.fetchval(
                    "select public.app_grant_credits($1::uuid,75,'grant',$2,true,'plan')", uid, ref
                )
                r2 = await conn.fetchval(
                    "select public.app_grant_credits($1::uuid,75,'grant',$2,true,'plan')", uid, ref
                )
                assert r1 is True and r2 is False  # idempotent
                top_ref = f"test:{uuid.uuid4()}"
                before = await conn.fetchval(
                    "select topup_balance from public.credits where user_id=$1::uuid", uid
                )
                await conn.fetchval(
                    "select public.app_grant_credits($1::uuid,40,'topup',$2,false,'topup')",
                    uid,
                    top_ref,
                )
                row = await conn.fetchrow(
                    "select balance, topup_balance from public.credits where user_id=$1::uuid", uid
                )
                assert row["balance"] == 75  # set, not added
                assert row["topup_balance"] == before + 40  # topup added, plan untouched
            finally:
                await tx.rollback()
        finally:
            await conn.close()

    asyncio.run(run())


def test_spend_multibucket_idempotent_and_insufficient() -> None:
    dsn = _skip_if_no_dsn()

    async def run() -> None:
        conn = await asyncpg.connect(dsn, statement_cache_size=0, ssl="require")
        try:
            uid = await _a_profile(conn)
            if uid is None:
                pytest.skip("no profiles on this DB")
            # spend_credit records the per-bucket split in credit_transactions.meta
            # (migration 0023). Skip cleanly on a DB that predates it, the same way
            # the suite skips without a DSN — rather than a hard failure.
            has_meta = await conn.fetchval(
                "select 1 from information_schema.columns where table_schema='public' "
                "and table_name='credit_transactions' and column_name='meta'"
            )
            if not has_meta:
                pytest.skip("migration 0023 (credit_transactions.meta) not applied")
            tx = conn.transaction()
            await tx.start()
            try:
                # Known state: free exhausted, plan 10, topup 5.
                await conn.execute(
                    "insert into public.credits (user_id) values ($1::uuid) on conflict do nothing",
                    uid,
                )
                await conn.execute(
                    "update public.credits set balance=10, daily_free_used=999, topup_balance=5 "
                    "where user_id=$1::uuid",
                    uid,
                )
                job1 = str(uuid.uuid4())
                s1 = await spend_credit(conn, uid, cost=4, ref=job1)  # 4 from plan
                assert (s1.balance, s1.topup_balance) == (6, 5)
                s_dup = await spend_credit(conn, uid, cost=4, ref=job1)  # idempotent
                assert (s_dup.balance, s_dup.topup_balance) == (6, 5)
                job2 = str(uuid.uuid4())
                s2 = await spend_credit(conn, uid, cost=8, ref=job2)  # 6 plan + 2 topup
                assert (s2.balance, s2.topup_balance) == (0, 3)
                # Now only 3 left, an HD (4) can't be covered.
                with pytest.raises(InsufficientCreditsError):
                    await spend_credit(conn, uid, cost=4, ref=str(uuid.uuid4()))
            finally:
                await tx.rollback()
        finally:
            await conn.close()

    asyncio.run(run())


def test_rls_blocks_client_self_grant() -> None:
    dsn = _skip_if_no_dsn()

    async def run() -> None:
        conn = await asyncpg.connect(dsn, statement_cache_size=0, ssl="require")
        try:
            uid = await _a_profile(conn)
            if uid is None:
                pytest.skip("no profiles on this DB")
            tx = conn.transaction()
            await tx.start()
            try:
                # Impersonate an authenticated end-user (subject to RLS).
                await conn.execute("set local role authenticated")
                await conn.execute(
                    "select set_config('request.jwt.claims', $1, true)",
                    json.dumps({"sub": uid, "role": "authenticated"}),
                )
                # A client must NOT be able to grant itself credits.
                with pytest.raises(asyncpg.PostgresError):
                    await conn.execute(
                        "insert into public.credit_transactions (user_id, delta, reason, ref) "
                        "values ($1::uuid, 999, 'grant', $2)",
                        uid, f"hack:{uuid.uuid4()}",
                    )
            finally:
                await tx.rollback()
        finally:
            await conn.close()

    asyncio.run(run())
