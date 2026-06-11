"""Taste graph / Style DNA (CLAUDE.md §24) — centroid + like-signal recording."""

from __future__ import annotations

import asyncio

import pytest

from app.core.config import get_settings
from app.services.taste import record_like_signal, taste_centroid


class _FakeConn:
    """Minimal asyncpg.Connection stand-in for the no-DB unit tests."""

    def __init__(self, *, fetchval=None, execute_error: Exception | None = None) -> None:
        self._fetchval = fetchval
        self._execute_error = execute_error

    async def fetchval(self, *args, **kwargs):
        return self._fetchval

    async def execute(self, *args, **kwargs):
        if self._execute_error is not None:
            raise self._execute_error
        return "INSERT 0 1"


# ── centroid ─────────────────────────────────────────────────────────────────


def test_taste_centroid_passes_through_literal() -> None:
    conn = _FakeConn(fetchval="[0.1,0.2,0.3]")
    assert asyncio.run(taste_centroid(conn, "u1")) == "[0.1,0.2,0.3]"


def test_taste_centroid_none_without_signals() -> None:
    conn = _FakeConn(fetchval=None)
    assert asyncio.run(taste_centroid(conn, "u1")) is None


# ── like signal is best-effort ───────────────────────────────────────────────


def test_record_like_signal_swallows_db_errors() -> None:
    # A taste-signal failure must never bubble up and break the like that fired it.
    conn = _FakeConn(execute_error=RuntimeError("db down"))
    asyncio.run(record_like_signal(conn, "u1", "p1"))  # must not raise


def test_record_like_signal_runs_when_ok() -> None:
    conn = _FakeConn()
    asyncio.run(record_like_signal(conn, "u1", "p1"))  # no error path


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_taste_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        # centroid over embedded taste signals
        "select avg(embedding)::text from public.taste_signals "
        "where user_id = $1::uuid and embedding is not null",
        # wardrobe items nearest the taste centroid (favorites)
        "select id::text as id from public.wardrobe_items "
        "where user_id = $1::uuid and embedding is not null "
        "order by embedding <=> $2::vector limit $3",
        # record a like signal carrying the post's outfit-item mean embedding
        "insert into public.taste_signals "
        "(user_id, signal_type, subject_type, subject_id, embedding) "
        "select $1::uuid, 'like', 'post', p.id, "
        "(select avg(w.embedding) from public.wardrobe_items w "
        "where w.id = any(o.item_ids) and w.embedding is not null) "
        "from public.posts p left join public.outfits o on o.id = p.outfit_id "
        "where p.id = $2::uuid",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
