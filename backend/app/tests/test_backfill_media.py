"""Verified backfill logic (INFRA_UPGRADE 1C): copy → verify → flip, idempotent,
reversible, and never flips a row that fails verification."""

from __future__ import annotations

import asyncio

import app.services.media.backfill as backfill
from app.services.media.base import StoredObject


class _Conn:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []

    async def execute(self, sql: str, *args: object):
        self.executed.append((sql, args))
        return "UPDATE 1"


class _Provider:
    """Fake StorageProvider: put() returns a StoredObject; head() returns a size."""

    def __init__(self, head_size: int) -> None:
        self._head_size = head_size
        self.puts: list[tuple] = []

    async def put(self, data, *, visibility, prefix, content_type, make_thumbnail=False):
        self.puts.append((visibility, prefix, make_thumbnail))
        return StoredObject(
            object_key=f"{prefix}/obj.jpg",
            bucket="b",
            visibility=visibility,
            content_hash="hash",
            public_url="https://cdn/x" if visibility == "public" else None,
            thumbnail_key=f"{prefix}/thumb.webp" if make_thumbnail else None,
        )

    async def head(self, *, object_key, visibility) -> int:
        return self._head_size


def _row(sp: str = "legacy", role: str = "original", vis: str = "private") -> dict:
    return {
        "id": "a1",
        "owner_kind": "wardrobe_item",
        "role": role,
        "visibility": vis,
        "storage_provider": sp,
        "legacy_url": "https://old/x.jpg",
        "user_id": "u1",
    }


def _wire(monkeypatch, data: bytes = b"abc") -> None:
    async def rv(**kw):
        return "https://fetch/x.jpg"

    async def dl(url):
        return data

    monkeypatch.setattr(backfill, "resolve_view_url", rv)
    monkeypatch.setattr(backfill, "download_image", dl)


def test_migrate_row_copies_verifies_and_flips(monkeypatch) -> None:
    _wire(monkeypatch, b"abc")
    conn, prov = _Conn(), _Provider(head_size=3)  # head size == len(b"abc")
    assert asyncio.run(backfill.migrate_row(conn, prov, _row())) == "migrated"
    assert any("update public.media_assets" in sql for sql, _ in conn.executed)


def test_migrate_row_skips_already_migrated(monkeypatch) -> None:
    _wire(monkeypatch)
    conn, prov = _Conn(), _Provider(3)
    assert asyncio.run(backfill.migrate_row(conn, prov, _row(sp="r2"))) == "skipped"
    assert conn.executed == []  # resumable: untouched


def test_migrate_row_size_mismatch_does_not_flip(monkeypatch) -> None:
    _wire(monkeypatch, b"abc")
    conn, prov = _Conn(), _Provider(head_size=999)  # != len(b"abc")
    assert asyncio.run(backfill.migrate_row(conn, prov, _row())) == "failed"
    assert conn.executed == []  # row stays legacy


def test_migrate_row_download_failure_does_not_flip(monkeypatch) -> None:
    async def rv(**kw):
        return "https://fetch/x.jpg"

    async def dl(url):
        raise RuntimeError("boom")

    monkeypatch.setattr(backfill, "resolve_view_url", rv)
    monkeypatch.setattr(backfill, "download_image", dl)
    conn, prov = _Conn(), _Provider(3)
    assert asyncio.run(backfill.migrate_row(conn, prov, _row())) == "failed"
    assert conn.executed == []


def test_thumbnail_role_does_not_generate_a_thumbnail(monkeypatch) -> None:
    _wire(monkeypatch, b"abcd")
    conn, prov = _Conn(), _Provider(head_size=4)
    assert asyncio.run(backfill.migrate_row(conn, prov, _row(role="thumbnail"))) == "migrated"
    assert prov.puts[0][2] is False  # make_thumbnail=False for the 'thumbnail' role


def test_rollback_returns_count() -> None:
    class _C:
        async def execute(self, sql: str, *a: object) -> str:
            return "UPDATE 7"

    assert asyncio.run(backfill.rollback(_C())) == 7
