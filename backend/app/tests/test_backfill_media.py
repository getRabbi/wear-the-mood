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


# ---------------------------------------------------------------------------
# Enrolling pre-R2 AI covers onto the ledger.
#
# A cover written before `r2_writes_enabled` has no media_assets row AT ALL —
# `_record_generated` only inserts one on the R2 branch. So `migrate` reports
# zero and is answering the wrong question. Enrolment adds the missing ROW (not
# an object) in exactly the state `migrate_row` consumes.
# ---------------------------------------------------------------------------


class _EnrolConn:
    """Fetch stub: the covers query, then the per-row existence re-check."""

    def __init__(self, rows: list[dict], existing: set[str] | None = None) -> None:
        self._rows = rows
        self._existing = existing or set()
        self.inserted: list[dict] = []

    async def fetch(self, sql: str, *args: object):
        return self._rows

    async def fetchval(self, sql: str, *args: object):
        return 1 if args and args[0] in self._existing else None


def _cover(path: str, gen_id: str | None = "g1", gen_type: str = "enhanced_item") -> dict:
    return {"path": path, "user_id": "u1", "gen_id": gen_id, "gen_type": gen_type}


def _capture_inserts(monkeypatch, conn: _EnrolConn) -> None:
    async def fake_insert(_conn, **kw):
        conn.inserted.append(kw)
        return "asset-id"

    monkeypatch.setattr(backfill, "insert_asset", fake_insert)


def test_enrol_records_a_legacy_row_and_no_object(monkeypatch) -> None:
    conn = _EnrolConn([_cover("u1/enhanced/a.png")])
    _capture_inserts(monkeypatch, conn)

    counts = asyncio.run(backfill.enrol_unledgered_covers(conn))

    assert counts == {"enrolled": 1, "skipped": 0, "unresolvable": 0}
    row = conn.inserted[0]
    # LEGACY, pointing at the object where it already lives — nothing copied.
    assert row["storage_provider"] == "legacy"
    assert row["legacy_url"] == "u1/enhanced/a.png"
    # No R2 key of any kind is claimed — the bytes have not moved.
    assert row.get("object_key") is None
    assert row.get("thumbnail_key") is None
    assert row.get("public_url") is None
    # Ownership mirrors _record_generated exactly.
    assert row["owner_kind"] == backfill.COVER_OWNER_KIND == "generated_image"
    assert row["owner_id"] == "g1"
    assert row["role"] == "enhanced_item"
    assert row["visibility"] == "private"


def test_enrol_is_idempotent(monkeypatch) -> None:
    # A path already on the ledger is skipped, so a rerun after a partial
    # failure resumes instead of duplicating.
    conn = _EnrolConn([_cover("u1/enhanced/a.png")], existing={"u1/enhanced/a.png"})
    _capture_inserts(monkeypatch, conn)

    counts = asyncio.run(backfill.enrol_unledgered_covers(conn))

    assert counts == {"enrolled": 0, "skipped": 1, "unresolvable": 0}
    assert conn.inserted == []


def test_enrol_leaves_a_cover_with_no_generated_image_alone(monkeypatch) -> None:
    # No generated_images row means no honest owner id. Filing it under an
    # invented one would be worse than leaving it.
    conn = _EnrolConn([_cover("u1/enhanced/orphan.png", gen_id=None)])
    _capture_inserts(monkeypatch, conn)

    counts = asyncio.run(backfill.enrol_unledgered_covers(conn))

    assert counts == {"enrolled": 0, "skipped": 0, "unresolvable": 1}
    assert conn.inserted == []


def test_enrol_handles_two_covers_sharing_one_generated_image(monkeypatch) -> None:
    # The re-check runs per row, so the second one sees the first's insert.
    conn = _EnrolConn([_cover("u1/enhanced/a.png"), _cover("u1/enhanced/b.png")])
    _capture_inserts(monkeypatch, conn)

    counts = asyncio.run(backfill.enrol_unledgered_covers(conn))

    assert counts["enrolled"] == 2
    assert {r["legacy_url"] for r in conn.inserted} == {
        "u1/enhanced/a.png",
        "u1/enhanced/b.png",
    }


def test_enrolled_covers_are_migratable_by_the_existing_flow(monkeypatch) -> None:
    """The point of enrolment: `migrate_row` can now consume the row, and it
    generates a thumbnail because the role is not 'thumbnail'."""
    _wire(monkeypatch)
    conn, prov = _Conn(), _Provider(head_size=3)
    row = {
        "id": "a1",
        "owner_kind": backfill.COVER_OWNER_KIND,
        "role": "enhanced_item",
        "visibility": "private",
        "storage_provider": "legacy",
        "legacy_url": "u1/enhanced/a.png",
        "user_id": "u1",
    }

    assert asyncio.run(backfill.migrate_row(conn, prov, row)) == "migrated"
    assert prov.puts[0][2] is True, "a cover must get a thumbnail on migration"


def test_the_legacy_bucket_for_a_cover_is_mapped() -> None:
    # Without this the migration cannot FETCH the cover: resolve_view_url maps
    # (owner_kind, role) -> private Supabase bucket, and an unmapped pair
    # returns the bare path, which is not downloadable.
    from app.services.media.legacy import LEGACY_PRIVATE_BUCKET

    assert LEGACY_PRIVATE_BUCKET[("generated_image", "enhanced_item")] == "tryon-results"
    assert LEGACY_PRIVATE_BUCKET[("tryon_result", "result")] == "tryon-results"


class _ResultEnrolConn:
    """Fetch stub for the try-on enrolment query + its per-row re-check."""

    def __init__(self, rows: list[dict], existing: set[str] | None = None) -> None:
        self._rows = rows
        self._existing = existing or set()
        self.inserted: list[dict] = []

    async def fetch(self, sql: str, *args: object):
        return self._rows

    async def fetchval(self, sql: str, *args: object):
        return 1 if len(args) > 1 and args[1] in self._existing else None


def test_enrol_tryon_result_records_a_legacy_row(monkeypatch) -> None:
    conn = _ResultEnrolConn([{"id": "r1", "user_id": "u1", "path": "u1/result/a.png"}])

    async def fake_insert(_conn, **kw):
        conn.inserted.append(kw)
        return "asset-id"

    monkeypatch.setattr(backfill, "insert_asset", fake_insert)
    counts = asyncio.run(backfill.enrol_unledgered_tryon_results(conn))

    assert counts == {"enrolled": 1, "skipped": 0, "unresolvable": 0}
    row = conn.inserted[0]
    assert row["owner_kind"] == backfill.RESULT_OWNER_KIND == "tryon_result"
    assert row["role"] == backfill.RESULT_ROLE == "result"
    assert row["owner_id"] == "r1"
    assert row["storage_provider"] == "legacy"
    assert row["legacy_url"] == "u1/result/a.png"
    assert row.get("object_key") is None


def test_enrol_tryon_result_is_idempotent(monkeypatch) -> None:
    conn = _ResultEnrolConn(
        [{"id": "r1", "user_id": "u1", "path": "u1/result/a.png"}], existing={"r1"}
    )

    async def fake_insert(_conn, **kw):  # pragma: no cover - must not run
        raise AssertionError("already on the ledger; must not insert again")

    monkeypatch.setattr(backfill, "insert_asset", fake_insert)
    counts = asyncio.run(backfill.enrol_unledgered_tryon_results(conn))

    assert counts == {"enrolled": 0, "skipped": 1, "unresolvable": 0}
