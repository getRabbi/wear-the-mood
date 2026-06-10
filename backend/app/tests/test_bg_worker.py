"""Wardrobe enrichment worker — unit (fakes) + live DB checks."""

from __future__ import annotations

import asyncio
import importlib

import pytest

import app.workers.bg_worker as bg_worker
from app.core.config import get_settings
from app.services.llm.base import GarmentTags
from app.workers.bg_worker import _DONE_UPDATE, claim_next_item, process_item

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


class _FakeTagger:
    name = "stub"

    def __init__(self, *, result: GarmentTags | None = None, raises: bool = False) -> None:
        self._result = result or GarmentTags()
        self._raises = raises

    async def tag(self, image: bytes, media_type: str) -> GarmentTags:
        if self._raises:
            raise RuntimeError("tagging boom")
        return self._result


def _wire(monkeypatch, *, tagger: _FakeTagger, download_ok: bool = True) -> None:
    monkeypatch.setattr(bg_worker, "get_background_remover", lambda: _FakeRemover())
    monkeypatch.setattr(bg_worker, "get_garment_tagger", lambda: tagger)

    async def download(url: str) -> bytes:
        if not download_ok:
            raise RuntimeError("download failed")
        return b"orig"

    async def upload(user_id: str, png: bytes) -> str:
        return f"https://cdn.test/{user_id}/cutout.png"

    monkeypatch.setattr(bg_worker, "download_image", download)
    monkeypatch.setattr(bg_worker, "upload_cutout", upload)


def test_worker_imports() -> None:
    importlib.import_module("app.workers.bg_worker")


def test_process_item_sets_done_with_cutout_and_tags(monkeypatch) -> None:
    conn = _FakeConn()
    tags = GarmentTags(
        category="Tops", color="white", tags=["white", "tee"],
        input_tokens=100, output_tokens=20,
    )
    _wire(monkeypatch, tagger=_FakeTagger(result=tags))

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'done'" in joined
    assert joined.count("ai_usage_log") == 2  # bg + tagging both logged (§14)
    done = next(args for sql, args in conn.executed if "'done'" in sql)
    assert done[1] == "https://cdn.test/22222222-2222-2222-2222-222222222222/cutout.png"
    assert done[2] == "Tops"  # category
    assert done[6] == ["white", "tee"]  # tags


def test_process_item_tagging_failure_still_finishes(monkeypatch) -> None:
    conn = _FakeConn()
    _wire(monkeypatch, tagger=_FakeTagger(raises=True))

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'done'" in joined  # cutout still saved
    done = next(args for sql, args in conn.executed if "'done'" in sql)
    assert done[2] is None  # no category written
    assert done[6] == []  # no tags written


def test_process_item_bg_failure_marks_failed(monkeypatch) -> None:
    conn = _FakeConn()
    _wire(monkeypatch, tagger=_FakeTagger(), download_ok=False)

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'failed'" in joined
    assert "cutout_status = 'done'" not in joined


# ── live DB checks (skip without a DSN) ──────────────────────────────────────


async def _connect():
    import asyncpg

    return await asyncpg.connect(
        dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
    )


def test_claim_runs_live_and_rolls_back() -> None:
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
        _DONE_UPDATE,
        "insert into public.ai_usage_log "
        "(user_id, provider, task, input_tokens, output_tokens, images, "
        "estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9)",
    ]

    async def run() -> None:
        conn = await _connect()
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
