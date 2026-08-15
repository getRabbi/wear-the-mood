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


class _SignProvider(R2StorageProvider):
    def __init__(self) -> None:
        self._base_url = ""
        self._ttl = 900
        self._private_bucket = "priv"

    async def view_url(self, *, object_key, visibility, public_url=None) -> str:
        return f"r2signed://{object_key}"

    async def presign_get_many(self, object_keys: list[str]) -> dict[str, str]:
        return {k: f"r2signed://{k}" for k in object_keys}


class _Conn:
    """Ledger stub: an R2 hit optionally carrying a thumbnail_key.

    Returns `object_key` too — the resolver signs the row's REAL key, which
    after a migration is not the path it was asked about.
    """

    def __init__(
        self,
        is_r2: bool,
        thumbnail_key: str | None = None,
        object_key: str | None = None,
    ) -> None:
        self._r2 = is_r2
        self._thumbnail_key = thumbnail_key
        self._object_key = object_key

    async def fetchrow(self, sql: str, *a: object):
        if not self._r2:
            return None
        return {
            # None → the resolver falls back to the requested path, which is the
            # un-migrated case where they are the same thing.
            "object_key": self._object_key,
            "thumbnail_key": self._thumbnail_key,
        }


def test_resolve_private_path_r2_legacy_and_passthrough(monkeypatch) -> None:

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
    out = asyncio.run(tryon_mod._resolve_garment_refs(_Conn(rows, None), "u", body))
    assert [r.image_url for r in out] == ["signed://u/cutout/x.png"]
    # The owned item's ID rides along, which is what lets the planner read the
    # row and resolve a real garment role instead of asking the provider.
    assert [r.wardrobe_item_id for r in out] == [str(item_id)]
    assert [r.legacy for r in out] == [False]

    # Legacy: no asset → fall back to the wardrobe column url.
    out2 = asyncio.run(
        tryon_mod._resolve_garment_refs(_Conn([], "https://legacy/g.jpg"), "u", body)
    )
    assert [r.image_url for r in out2] == ["https://legacy/g.jpg"]
    assert [r.wardrobe_item_id for r in out2] == [str(item_id)]


# ── gated worker write path records a media_assets row ──────────────────────


class _RecordingConn:
    """Captures execute() + fetchval() so we can assert the media_assets write."""

    def __init__(self) -> None:
        self.execute_sql: list[str] = []
        self.fetchval_sql: list[str] = []

    async def execute(self, sql: str, *args: object) -> None:
        self.execute_sql.append(sql)

    async def fetch(self, sql: str, *args: object) -> list:
        return []  # no existing media_assets → resolve/replace take the insert path

    async def fetchval(self, sql: str, *args: object):
        self.fetchval_sql.append(sql)
        return "media-asset-id"

    def transaction(self):
        return _NoopTxn()


class _NoopTxn:
    async def __aenter__(self) -> _NoopTxn:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False


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

        async def remove(self, image: bytes):
            from app.services.bg.base import BackgroundRemovalResult

            return BackgroundRemovalResult(
                cutout_png=b"cutout", mask_png=None, width=10, height=10, model="stub"
            )

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

    # The item is marked done and the cutout asset is recorded via the idempotent
    # replacement helper (insert path, since no active row exists yet).
    done = " ".join(conn.execute_sql)
    assert "cutout_status = 'done'" in done
    assert any("insert into public.media_assets" in s for s in conn.fetchval_sql)


def test_resolve_private_rendition_signs_the_thumbnail_too(monkeypatch) -> None:
    """The AI-enhanced cover case.

    A cover that resolves to ONE url forces every card to draw the full
    generated composition. When the ledger has a thumbnail, both come back
    signed from the same pass.
    """
    monkeypatch.setattr(repo, "get_storage_provider", lambda: _SignProvider())
    out = asyncio.run(
        repo.resolve_private_rendition(
            _Conn(True, "u/enhance/thumb/x.webp"), "u/enhance/x.png", "tryon-results"
        )
    )
    assert out.url == "r2signed://u/enhance/x.png"
    assert out.thumb_url == "r2signed://u/enhance/thumb/x.webp"


def test_resolve_private_rendition_without_a_thumbnail(monkeypatch) -> None:
    # Pre-backfill rows. The full object still resolves; the card falls back to
    # it rather than showing nothing.
    monkeypatch.setattr(repo, "get_storage_provider", lambda: _SignProvider())
    out = asyncio.run(
        repo.resolve_private_rendition(_Conn(True), "u/enhance/x.png", "tryon-results")
    )
    assert out.url == "r2signed://u/enhance/x.png"
    assert out.thumb_url is None


def test_resolve_private_rendition_legacy_has_no_thumbnail(monkeypatch) -> None:
    # A legacy Supabase object never had a thumbnail sibling to sign.
    async def fake_sign(bucket: str, path: str, expires_in: int = 3600) -> str:
        return f"sb://{bucket}/{path}"

    monkeypatch.setattr(repo, "create_signed_url", fake_sign)
    out = asyncio.run(repo.resolve_private_rendition(_Conn(False), "u/cover.png", "tryon-results"))
    assert out.url == "sb://tryon-results/u/cover.png"
    assert out.thumb_url is None


def test_migrated_cover_resolves_to_r2_and_its_thumbnail(monkeypatch) -> None:
    """The pointer column is never rewritten by `migrate`, so the ref stays the
    old Supabase path while the bytes live on R2. `follow_migrated` is what
    finds the row by `legacy_url` and serves the REAL object key + thumbnail."""

    class _MigratedConn:
        async def fetchrow(self, sql: str, *a: object):
            path, follow = a[0], a[1]
            # Mirrors the real predicate: only reachable when following legacy.
            if not follow or path != "u1/enhanced/old.png":
                return None
            return {
                "object_key": "u1/generated_image/new.png",
                "thumbnail_key": "u1/generated_image/thumb/new.webp",
            }

    monkeypatch.setattr(repo, "get_storage_provider", lambda: _SignProvider())
    out = asyncio.run(
        repo.resolve_private_rendition(
            _MigratedConn(), "u1/enhanced/old.png", "tryon-results", follow_migrated=True
        )
    )
    # The signed URL is for the NEW key, not the stale path.
    assert out.url == "r2signed://u1/generated_image/new.png"
    assert out.thumb_url == "r2signed://u1/generated_image/thumb/new.webp"


def test_follow_migrated_is_off_by_default(monkeypatch) -> None:
    """Unrelated media (avatars, profile pics, try-on photos) keep the exact
    behaviour they had — they resolve by object_key only."""

    seen: dict[str, object] = {}

    class _RecordingConn:
        async def fetchrow(self, sql: str, *a: object):
            seen["follow"] = a[1]
            return None

    async def fake_sign(bucket: str, path: str, expires_in: int = 3600) -> str:
        return f"sb://{bucket}/{path}"

    monkeypatch.setattr(repo, "create_signed_url", fake_sign)
    out = asyncio.run(repo.resolve_private_path(_RecordingConn(), "u1/avatar.jpg", "avatars"))

    assert seen["follow"] is False
    assert out == "sb://avatars/u1/avatar.jpg"


def test_a_rolled_back_cover_falls_back_to_supabase(monkeypatch) -> None:
    """`--rollback` flips storage_provider to 'legacy'. The match requires 'r2',
    so resolution returns to the Supabase object on its own — no code change and
    no stale R2 URL."""

    class _RolledBackConn:
        async def fetchrow(self, sql: str, *a: object):
            return None  # the r2 predicate no longer matches

    async def fake_sign(bucket: str, path: str, expires_in: int = 3600) -> str:
        return f"sb://{bucket}/{path}"

    monkeypatch.setattr(repo, "create_signed_url", fake_sign)
    out = asyncio.run(
        repo.resolve_private_rendition(
            _RolledBackConn(), "u1/enhanced/old.png", "tryon-results", follow_migrated=True
        )
    )
    assert out.url == "sb://tryon-results/u1/enhanced/old.png"
    assert out.thumb_url is None
