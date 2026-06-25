"""Wardrobe enrichment worker — unit (fakes) + live DB checks."""

from __future__ import annotations

import asyncio
import importlib

import pytest

import app.workers.bg_worker as bg_worker
from app.core.config import get_settings
from app.services.llm.base import GarmentTags
from app.workers.bg_worker import (
    _DONE_CUTOUT_UPDATE,
    _TAGS_UPDATE,
    claim_next_item,
    process_item,
)

_ITEM = {
    "id": "11111111-1111-1111-1111-111111111111",
    "user_id": "22222222-2222-2222-2222-222222222222",
    "image_url": "https://example.test/orig.jpg",
    "title": "White tee",
    "category": None,
}


class _FakeConn:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []

    async def execute(self, sql: str, *args: object) -> None:
        self.executed.append((sql, args))

    async def fetch(self, sql: str, *args: object) -> list:
        # No media_assets rows in unit tests → resolve_images is a no-op and the
        # worker falls back to the legacy image_url.
        return []


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


class _FakeEmbedder:
    dimensions = 3

    def __init__(self, *, name: str = "stub", vector: list[float] | None = None) -> None:
        self.name = name
        self._vector = vector or [0.0, 0.0, 0.0]

    async def embed(self, text: str) -> list[float]:
        return self._vector


def _wire(
    monkeypatch,
    *,
    tagger: _FakeTagger,
    embedder: _FakeEmbedder | None = None,
    download_ok: bool = True,
) -> None:
    monkeypatch.setattr(bg_worker, "get_background_remover", lambda: _FakeRemover())
    monkeypatch.setattr(bg_worker, "get_garment_tagger", lambda: tagger)
    monkeypatch.setattr(bg_worker, "get_embedder", lambda: embedder or _FakeEmbedder())

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
        category="Tops",
        color="white",
        tags=["white", "tee"],
        input_tokens=100,
        output_tokens=20,
    )
    _wire(monkeypatch, tagger=_FakeTagger(result=tags))

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'done'" in joined
    assert joined.count("ai_usage_log") == 2  # bg + tagging (embedder is stub → skipped)
    # The cutout is persisted by the done update (id, cutout_url only)…
    done = next(args for sql, args in conn.executed if "cutout_status = 'done'" in sql)
    assert done[1] == "https://cdn.test/22222222-2222-2222-2222-222222222222/cutout.png"
    # …and the tags land in a SEPARATE gap-fill update that runs afterwards.
    tag_row = next(args for sql, args in conn.executed if "set category" in sql)
    assert tag_row[1] == "Tops"  # category
    assert tag_row[5] == ["white", "tee"]  # tags


def test_process_item_marks_done_before_tagging(monkeypatch) -> None:
    """BUG 1: the cutout must go live BEFORE the (slow) tagging step, so the closet
    card reveals it without waiting on the vision call."""
    conn = _FakeConn()
    _wire(monkeypatch, tagger=_FakeTagger(result=GarmentTags(category="Tops")))

    asyncio.run(process_item(conn, _ITEM))

    sqls = [sql for sql, _ in conn.executed]
    done_idx = next(i for i, s in enumerate(sqls) if "cutout_status = 'done'" in s)
    tags_idx = next(i for i, s in enumerate(sqls) if "set category" in s)
    assert done_idx < tags_idx


def test_process_item_embeds_with_real_embedder(monkeypatch) -> None:
    conn = _FakeConn()
    tags = GarmentTags(category="Tops", tags=["white", "tee"])
    _wire(
        monkeypatch,
        tagger=_FakeTagger(result=tags),
        embedder=_FakeEmbedder(name="openai", vector=[0.1, 0.2, 0.3]),
    )

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "set embedding = $2::vector" in joined
    assert joined.count("ai_usage_log") == 3  # bg + tagging + embedding
    embed = next(args for sql, args in conn.executed if "set embedding" in sql)
    assert embed[1] == "[0.1,0.2,0.3]"


def test_process_item_tagging_failure_still_finishes(monkeypatch) -> None:
    conn = _FakeConn()
    _wire(monkeypatch, tagger=_FakeTagger(raises=True))

    asyncio.run(process_item(conn, _ITEM))

    joined = " ".join(sql for sql, _ in conn.executed)
    assert "cutout_status = 'done'" in joined  # cutout still saved
    # Tagging failed → its gap-fill update never runs (attributes left untouched).
    assert not any("set category" in sql for sql, _ in conn.executed)


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
        _DONE_CUTOUT_UPDATE,
        _TAGS_UPDATE,
        "update public.wardrobe_items set embedding = $2::vector where id = $1::uuid",
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
