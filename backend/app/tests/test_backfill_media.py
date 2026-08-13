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


# ---------------------------------------------------------------------------
# Missing-thumbnail backfill.
#
# For objects already on R2 whose upload path never asked for a thumbnail — the
# AI-enhanced cover and the try-on result. The ORIGINAL is the thing that must
# survive untouched: its object_key is what `wardrobe_items.cover_image_url` and
# `tryon_results.result_image_url` store, so re-keying it would orphan the row
# the backfill exists to repair.
# ---------------------------------------------------------------------------


class _ThumbProvider:
    """Fake provider for the thumbnail-only path."""

    def __init__(self, head_size: int = 512, fail_put: bool = False) -> None:
        self._head_size = head_size
        self._fail_put = fail_put
        self.thumbnail_puts: list[tuple] = []
        self.puts: list[tuple] = []

    async def view_url(self, *, object_key, visibility) -> str:
        return f"https://r2/{object_key}?sig=1"

    async def put(self, *a, **kw):  # pragma: no cover - must never be called
        self.puts.append((a, kw))
        raise AssertionError("the original must never be re-uploaded")

    async def put_thumbnail_for(self, data, *, object_key, visibility) -> str:
        if self._fail_put:
            raise RuntimeError("upload exploded")
        self.thumbnail_puts.append((object_key, visibility, len(data)))
        prefix = object_key.rsplit("/", 1)[0]
        return f"{prefix}/thumb/new.webp"

    async def head(self, *, object_key, visibility) -> int:
        return self._head_size


def _thumb_row(thumbnail_key=None, role: str = "result") -> dict:
    return {
        "id": "a1",
        "owner_kind": "tryon_result",
        "role": role,
        "visibility": "private",
        "object_key": "u1/result/look.png",
        "thumbnail_key": thumbnail_key,
    }


def _wire_download(monkeypatch, data: bytes = b"abc") -> None:
    async def dl(url):
        return data

    monkeypatch.setattr(backfill, "download_image", dl)


def test_add_thumbnail_writes_beside_the_original_and_records_it(monkeypatch) -> None:
    _wire_download(monkeypatch)
    conn, prov = _Conn(), _ThumbProvider()

    assert asyncio.run(backfill.add_thumbnail_row(conn, prov, _thumb_row())) == "added"

    # The original was read, never re-written.
    assert prov.puts == []
    assert prov.thumbnail_puts == [("u1/result/look.png", "private", 3)]
    # ...and only the thumbnail_key column was touched.
    sql, args = conn.executed[0]
    assert "set thumbnail_key" in sql
    assert "object_key" not in sql.split("where")[0].replace("set thumbnail_key", "")
    assert args[1] == "u1/result/thumb/new.webp"
    assert "thumbnail_key is null" in sql  # concurrent writer wins


def test_add_thumbnail_is_idempotent(monkeypatch) -> None:
    _wire_download(monkeypatch)
    conn, prov = _Conn(), _ThumbProvider()
    row = _thumb_row(thumbnail_key="u1/result/thumb/already.webp")

    assert asyncio.run(backfill.add_thumbnail_row(conn, prov, row)) == "skipped"
    assert prov.thumbnail_puts == []
    assert conn.executed == []


def test_add_thumbnail_download_failure_records_nothing(monkeypatch) -> None:
    async def boom(url):
        raise RuntimeError("404")

    monkeypatch.setattr(backfill, "download_image", boom)
    conn, prov = _Conn(), _ThumbProvider()

    assert asyncio.run(backfill.add_thumbnail_row(conn, prov, _thumb_row())) == "failed"
    assert conn.executed == []  # the row is left exactly as it was


def test_add_thumbnail_upload_failure_records_nothing(monkeypatch) -> None:
    _wire_download(monkeypatch)
    conn, prov = _Conn(), _ThumbProvider(fail_put=True)

    assert asyncio.run(backfill.add_thumbnail_row(conn, prov, _thumb_row())) == "failed"
    assert conn.executed == []


def test_add_thumbnail_verify_failure_records_nothing(monkeypatch) -> None:
    # An unrecorded thumbnail is a harmless orphan; a recorded-but-absent one is
    # a broken card. head() returning 0 must stop the write.
    _wire_download(monkeypatch)
    conn, prov = _Conn(), _ThumbProvider(head_size=0)

    assert asyncio.run(backfill.add_thumbnail_row(conn, prov, _thumb_row())) == "failed"
    assert conn.executed == []


def test_masks_and_thumbnails_are_excluded_from_the_query() -> None:
    # A cutout mask is read at full resolution by the Erase/Restore editor and
    # is never drawn as a card, so a downscaled copy would be storage spent on
    # something nothing can use.
    assert "cutout_mask" in backfill._ROLE_EXCLUSION
    assert "thumbnail" in backfill._ROLE_EXCLUSION
    assert backfill._ROLE_EXCLUSION.startswith("role not in (")
