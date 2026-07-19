"""resolve_images (batched per-record read resolution) + the gated worker write
path that records media_assets rows (INFRA_UPGRADE Phase 1B · COMMIT 3)."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import app.services.media.repo as repo
import app.workers.bg_worker as bg_worker
from app.services.media.base import StoredObject
from app.services.media.r2 import R2StorageProvider


class _FakeProvider(R2StorageProvider):
    """R2 provider subclass with no network — signs by prefixing 'signed://'."""

    def __init__(self) -> None:  # no super().__init__ — avoid needing settings
        self._base_url = "https://cdn.example.com"

    async def presign_get_many(self, object_keys: list[str]) -> dict[str, str]:
        return {k: f"signed://{k}" for k in object_keys}


class _FakeFetchConn:
    """Returns canned media_assets rows from .fetch(); used by resolve_images."""

    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows

    async def fetch(self, sql: str, *args: object) -> list[dict]:
        return self._rows


def _resolve(rows, monkeypatch, owner_kind="wardrobe_item", roles=("original", "cutout")):
    monkeypatch.setattr(repo, "get_storage_provider", lambda: _FakeProvider())
    return asyncio.run(repo.resolve_images(_FakeFetchConn(rows), owner_kind, ["o1"], roles))


def test_resolve_r2_public_uses_cdn_url(monkeypatch) -> None:
    rows = [
        {
            "owner_id": "o1",
            "role": "original",
            "storage_provider": "r2",
            "visibility": "public",
            "object_key": "o1/post/x.jpg",
            "thumbnail_key": "o1/post/thumb/x.webp",
            "public_url": "https://cdn.example.com/o1/post/x.jpg",
            "legacy_url": None,
        }
    ]
    out = _resolve(rows, monkeypatch)
    img = out[("o1", "original")]
    assert img.url == "https://cdn.example.com/o1/post/x.jpg"
    assert img.thumb_url == "https://cdn.example.com/o1/post/thumb/x.webp"


def test_resolve_r2_private_batch_signs(monkeypatch) -> None:
    rows = [
        {
            "owner_id": "o1",
            "role": "cutout",
            "storage_provider": "r2",
            "visibility": "private",
            "object_key": "o1/cutout/x.png",
            "thumbnail_key": "o1/cutout/thumb/x.webp",
            "public_url": None,
            "legacy_url": None,
        }
    ]
    out = _resolve(rows, monkeypatch)
    img = out[("o1", "cutout")]
    assert img.url == "signed://o1/cutout/x.png"
    assert img.thumb_url == "signed://o1/cutout/thumb/x.webp"


def test_resolve_legacy_http_passthrough(monkeypatch) -> None:
    # Wardrobe is classified private but its legacy URL is a public Supabase URL
    # mid-migration → served as-is, no signing (INFRA point A).
    rows = [
        {
            "owner_id": "o1",
            "role": "original",
            "storage_provider": "legacy",
            "visibility": "private",
            "object_key": None,
            "thumbnail_key": None,
            "public_url": None,
            "legacy_url": "https://supabase/public/wardrobe/o1/x.jpg",
        }
    ]
    out = _resolve(rows, monkeypatch)
    assert out[("o1", "original")].url == "https://supabase/public/wardrobe/o1/x.jpg"
    assert out[("o1", "original")].thumb_url is None


def test_resolve_empty_owner_ids_is_noop(monkeypatch) -> None:
    monkeypatch.setattr(repo, "get_storage_provider", lambda: _FakeProvider())
    out = asyncio.run(repo.resolve_images(_FakeFetchConn([]), "wardrobe_item", [], ("original",)))
    assert out == {}


# ── resolve_private_path (selfie display: R2 signed, else Supabase signed) ───


def test_resolve_private_path_r2_legacy_and_passthrough(monkeypatch) -> None:
    class _SignProvider(R2StorageProvider):
        def __init__(self) -> None:
            self._base_url = ""
            self._ttl = 900
            self._private_bucket = "priv"

        async def view_url(self, *, object_key, visibility, public_url=None) -> str:
            return f"r2signed://{object_key}"

    class _Conn:
        def __init__(self, is_r2: bool) -> None:
            self._r2 = is_r2

        async def fetchval(self, sql: str, *a: object):
            return 1 if self._r2 else None

    # http url + None pass through unchanged.
    assert (
        asyncio.run(repo.resolve_private_path(_Conn(False), "https://x/a.jpg", "avatars"))
        == "https://x/a.jpg"
    )
    assert asyncio.run(repo.resolve_private_path(_Conn(False), None, "avatars")) is None

    # R2 object (media_assets hit) → R2 signed.
    monkeypatch.setattr(repo, "get_storage_provider", lambda: _SignProvider())
    assert (
        asyncio.run(repo.resolve_private_path(_Conn(True), "u/avatar/x.jpg", "avatars"))
        == "r2signed://u/avatar/x.jpg"
    )

    # Legacy Supabase path → Supabase signed.
    async def fake_sign(bucket: str, path: str, expires_in: int = 3600) -> str:
        return f"sb://{bucket}/{path}"

    monkeypatch.setattr(repo, "create_signed_url", fake_sign)
    assert (
        asyncio.run(repo.resolve_private_path(_Conn(False), "u/avatar.jpg", "avatars"))
        == "sb://avatars/u/avatar.jpg"
    )


# ── try-on garment resolution (R2 signed url, else legacy column) ────────────


def test_tryon_garment_resolves_r2_then_legacy(monkeypatch) -> None:
    import uuid as _uuid

    import app.routers.v1.tryon as tryon_mod
    from app.models.tryon import TryOnRequest

    monkeypatch.setattr(repo, "get_storage_provider", lambda: _FakeProvider())
    item_id = _uuid.uuid4()
    body = TryOnRequest(person_image_url="p", wardrobe_item_id=item_id)

    class _Conn:
        def __init__(self, rows: list, fetchval: str | None) -> None:
            self._rows = rows
            self._fv = fetchval

        async def fetch(self, sql: str, *a: object) -> list:
            return self._rows

        async def fetchval(self, sql: str, *a: object) -> str | None:
            return self._fv

    # R2: a private cutout asset → the garment is handed to the provider as a
    # freshly signed url, never a bare object_key.
    rows = [
        {
            "owner_id": str(item_id),
            "role": "cutout",
            "storage_provider": "r2",
            "visibility": "private",
            "object_key": "u/cutout/x.png",
            "thumbnail_key": None,
            "public_url": None,
            "legacy_url": None,
        }
    ]
    out = asyncio.run(tryon_mod._resolve_garment_stack(_Conn(rows, None), "u", body))
    assert out == ["signed://u/cutout/x.png"]

    # Legacy: no asset → fall back to the wardrobe column url.
    out2 = asyncio.run(
        tryon_mod._resolve_garment_stack(_Conn([], "https://legacy/g.jpg"), "u", body)
    )
    assert out2 == ["https://legacy/g.jpg"]


# ── gated worker write path records a media_assets row ──────────────────────


class _RecordingConn:
    """Captures execute() + fetchval() so we can assert the media_assets insert."""

    def __init__(self) -> None:
        self.execute_sql: list[str] = []
        self.fetchval_sql: list[str] = []

    async def execute(self, sql: str, *args: object) -> None:
        self.execute_sql.append(sql)

    async def fetch(self, sql: str, *args: object) -> list:
        return []  # no existing media_assets → original resolves to image_url

    async def fetchval(self, sql: str, *args: object):
        self.fetchval_sql.append(sql)
        return "media-asset-id"


def test_bg_worker_r2_records_cutout_asset(monkeypatch) -> None:
    item = {
        "id": "11111111-1111-1111-1111-111111111111",
        "user_id": "22222222-2222-2222-2222-222222222222",
        "image_url": "https://example.test/orig.jpg",
        "title": "White tee",
        "category": None,
    }

    # Force the r2 write path.
    monkeypatch.setattr(bg_worker, "get_settings", lambda: SimpleNamespace(r2_writes_enabled=True))

    class _Remover:
        name = "stub"

        async def remove(self, image: bytes) -> bytes:
            return b"cutout"

    class _Tagger:
        name = "stub"

        async def tag(self, image: bytes, media_type: str):
            from app.services.llm.base import GarmentTags

            return GarmentTags()

    class _Embedder:
        name = "stub"

    stored = StoredObject(
        object_key="22222222-2222-2222-2222-222222222222/cutout/abc.png",
        bucket="priv",
        visibility="private",
        content_hash="hash",
        public_url=None,
        thumbnail_key="22222222-2222-2222-2222-222222222222/cutout/thumb/abc.webp",
    )

    class _Provider:
        async def put(self, *a, **k) -> StoredObject:
            return stored

    async def _download(url: str) -> bytes:
        return b"orig"

    monkeypatch.setattr(bg_worker, "get_background_remover", lambda: _Remover())
    monkeypatch.setattr(bg_worker, "get_garment_tagger", lambda: _Tagger())
    monkeypatch.setattr(bg_worker, "get_embedder", lambda: _Embedder())
    monkeypatch.setattr(bg_worker, "get_storage_provider", lambda: _Provider())
    monkeypatch.setattr(bg_worker, "download_image", _download)

    conn = _RecordingConn()
    asyncio.run(bg_worker.process_item(conn, item))

    # The cutout column got the object_key, and a media_assets row was inserted.
    done = " ".join(conn.execute_sql)
    assert "cutout_status = 'done'" in done
    assert any("insert into public.media_assets" in s for s in conn.fetchval_sql)
