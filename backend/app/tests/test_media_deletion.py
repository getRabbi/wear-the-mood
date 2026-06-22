"""Media deletion service (Phase 4A · A1). Mocked storage — no network."""

from __future__ import annotations

import asyncio

import app.services.media.deletion as deletion
from app.services.media.deletion import _legacy_target
from app.services.media.r2 import R2StorageProvider


class _FakeProvider(R2StorageProvider):
    def __init__(self) -> None:
        self.prefix_calls: list[tuple[str, str]] = []
        self.delete_calls: list[tuple] = []

    async def delete_prefix(self, *, prefix, visibility) -> int:
        self.prefix_calls.append((prefix, visibility))
        return 3

    async def delete(self, *, object_key, visibility, thumbnail_key=None) -> None:
        self.delete_calls.append((object_key, visibility, thumbnail_key))


class _Conn:
    def __init__(self, rows: list | None = None) -> None:
        self.rows = rows or []
        self.executed: list[str] = []

    async def execute(self, sql: str, *a: object) -> None:
        self.executed.append(sql)

    async def fetch(self, sql: str, *a: object) -> list:
        return self.rows


# ── _legacy_target (pure) ───────────────────────────────────────────────────
def test_legacy_target_public_url() -> None:
    assert _legacy_target(
        "wardrobe_item", "original",
        "https://x.supabase.co/storage/v1/object/public/wardrobe/u1/a.jpg",
    ) == ("wardrobe", "u1/a.jpg")


def test_legacy_target_public_url_strips_query() -> None:
    assert _legacy_target(
        "post", "post",
        "https://x/storage/v1/object/public/post-images/u1/p.jpg?token=z",
    ) == ("post-images", "u1/p.jpg")


def test_legacy_target_private_path_uses_bucket_map() -> None:
    assert _legacy_target("profile", "avatar", "u1/avatar.jpg") == ("avatars", "u1/avatar.jpg")
    assert _legacy_target("tryon_result", "result", "u1/result/x.png") == (
        "tryon-results", "u1/result/x.png",
    )


def test_legacy_target_unknown_returns_none() -> None:
    assert _legacy_target("post", "post", "https://other/whatever") is None
    assert _legacy_target("post", "post", None) is None


# ── delete_user_media (account erasure) ─────────────────────────────────────
def test_delete_user_media_hits_all_buckets(monkeypatch) -> None:
    prov = _FakeProvider()
    sb_calls: list[tuple[str, str]] = []

    async def fake_sb_delete_prefix(bucket: str, prefix: str) -> int:
        sb_calls.append((bucket, prefix))
        return 2

    monkeypatch.setattr(deletion, "get_storage_provider", lambda: prov)
    monkeypatch.setattr(deletion.storage, "delete_prefix", fake_sb_delete_prefix)
    conn = _Conn()

    counts = asyncio.run(deletion.delete_user_media(conn, "u1"))

    # both R2 buckets, by prefix "u1/"
    assert ("u1/", "public") in prov.prefix_calls
    assert ("u1/", "private") in prov.prefix_calls
    # all five Supabase buckets, by prefix "u1"
    assert {b for b, _ in sb_calls} == {
        "wardrobe", "avatars", "profile-pictures", "post-images", "tryon-results",
    }
    assert all(p == "u1" for _, p in sb_calls)
    # ledger rows dropped
    assert any("delete from public.media_assets" in s for s in conn.executed)
    assert counts["r2:public"] == 3 and counts["sb:wardrobe"] == 2


def test_delete_user_media_is_best_effort(monkeypatch) -> None:
    prov = _FakeProvider()

    async def flaky_delete_prefix(bucket: str, prefix: str) -> int:
        if bucket == "avatars":
            raise RuntimeError("boom")
        return 1

    monkeypatch.setattr(deletion, "get_storage_provider", lambda: prov)
    monkeypatch.setattr(deletion.storage, "delete_prefix", flaky_delete_prefix)
    conn = _Conn()

    counts = asyncio.run(deletion.delete_user_media(conn, "u1"))  # must not raise
    assert counts["sb:avatars"] == -1  # the failure is recorded
    assert counts["sb:wardrobe"] == 1  # others still ran
    assert any("delete from public.media_assets" in s for s in conn.executed)


# ── delete_owner_media (individual content) ─────────────────────────────────
def test_delete_owner_media_r2_and_legacy(monkeypatch) -> None:
    prov = _FakeProvider()
    sb_deletes: list[tuple[str, str]] = []

    async def fake_delete_object(bucket: str, path: str) -> None:
        sb_deletes.append((bucket, path))

    monkeypatch.setattr(deletion, "get_storage_provider", lambda: prov)
    monkeypatch.setattr(deletion.storage, "delete_object", fake_delete_object)
    rows = [
        {"id": "a1", "role": "original", "visibility": "private", "storage_provider": "r2",
         "object_key": "u1/wardrobe/x.jpg", "thumbnail_key": "u1/wardrobe/thumb/x.webp",
         "legacy_url": None},
        {"id": "a2", "role": "cutout", "visibility": "private", "storage_provider": "legacy",
         "object_key": None, "thumbnail_key": None,
         "legacy_url": "https://x/storage/v1/object/public/wardrobe/u1/c.png"},
    ]
    conn = _Conn(rows)

    acted = asyncio.run(deletion.delete_owner_media(conn, "wardrobe_item", "o1"))

    assert acted == 2
    assert prov.delete_calls == [("u1/wardrobe/x.jpg", "private", "u1/wardrobe/thumb/x.webp")]
    assert sb_deletes == [("wardrobe", "u1/c.png")]
    assert any("update public.media_assets set deleted_at" in s for s in conn.executed)
