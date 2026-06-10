"""Background-removal worker — unit (fakes) + live DB checks."""

from __future__ import annotations

import asyncio
import importlib

import pytest

import app.workers.bg_worker as bg_worker
from app.core.config import get_settings
from app.workers.bg_worker import claim_next_item, process_item

_ITEM = {
    "id": "11111111-1111-1111-1111-111111111111",
    "user_id": "22222222-2222-2222-2222-222222222222",
    "image_url": "https://example.test/orig.jpg",
}


class _FakeConn:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []

    async def execute(self, sql: str, *args: object) -> None:
        self.executed.append((sql, args))


class _FakeRemover:
    name = "stub"

    async def remove(self, image: bytes) -> bytes:
        return b"cutout-" + image


def test_worker_imports() -> None:
    importlib.import_module("app.workers.bg_worker")


def test_process_item_success_sets_done_with_cutout(monkeypatch) -> None:
    conn = _FakeConn()
    monkeypatch.setattr(bg_worker, "get_background_remover", lambda: _FakeRemover())

    async def fake_download(url: str) -> bytes:
        return b"orig"

    async def fake_upload(user_id: str, png: bytes) -> str:
        assert png == b"cutout-orig"
        return f"https://cdn.test/{user_id}/cutout.png"

    monkeypatch.setattr(bg_worker, "download_image", fake_download)
    monkeypatch.setattr(bg_worker, "upload_cutout", fake_upload)

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'done'" in joined
    assert "ai_usage_log" in joined
    done = next(args for sql, args in conn.executed if "'done'" in sql)
    assert done[1] == "https://cdn.test/22222222-2222-2222-2222-222222222222/cutout.png"


def test_process_item_failure_marks_failed(monkeypatch) -> None:
    conn = _FakeConn()
    monkeypatch.setattr(bg_worker, "get_background_remover", lambda: _FakeRemover())

    async def boom(url: str) -> bytes:
        raise RuntimeError("download failed")

    monkeypatch.setattr(bg_worker, "download_image", boom)

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'failed'" in joined
    assert "ai_usage_log" in joined  # failure is still logged (§14)


# ── live DB checks (skip without a DSN) ──────────────────────────────────────


async def _connect():
    import asyncpg

    return await asyncpg.connect(
        dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
    )


def test_claim_runs_live_and_rolls_back() -> None:
    """Exercise the real claim UPDATE...returning, then roll back so any
    'processing' flip never persists."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        conn = await _connect()
        try:
            tr = conn.transaction()
            await tr.start()
            try:
                claimed = await claim_next_item(conn)
                assert claimed is None or "image_url" in claimed
            finally:
                await tr.rollback()
        finally:
            await conn.close()

    asyncio.run(run())


def test_bg_worker_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "update public.wardrobe_items set cutout_status = 'failed' where id = $1::uuid",
        "update public.wardrobe_items set cutout_status = 'done', cutout_url = $2, "
        "thumbnail_url = coalesce(thumbnail_url, $2) where id = $1::uuid",
        "insert into public.ai_usage_log "
        "(user_id, provider, task, images, estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, 'bg_removal', 1, $3, $4, $5)",
    ]

    async def run() -> None:
        conn = await _connect()
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
