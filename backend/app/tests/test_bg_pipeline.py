"""BiRefNet Lite mask pipeline + editable-mask persistence (§ BG upgrade).

rembg is never downloaded here: the model-routing tests mock ``new_session`` and
skip where rembg isn't installed (api/CI); the imaging + replacement tests are
pure Pillow / fakes.
"""

from __future__ import annotations

import asyncio
import io

import pytest
from PIL import Image

from app.core.config import PREFETCHABLE_BG_MODELS, SUPPORTED_BG_MODELS, Settings, get_settings
from app.services.bg import get_background_remover
from app.services.bg.base import BackgroundRemovalResult
from app.services.media.r2 import R2StorageProvider


@pytest.fixture(autouse=True)
def _clear_cache():
    get_background_remover.cache_clear()
    get_settings.cache_clear()
    yield
    get_background_remover.cache_clear()
    get_settings.cache_clear()


# ── result contract + model resolution (pure) ────────────────────────────────


def test_result_dataclass_is_frozen() -> None:
    from dataclasses import FrozenInstanceError

    r = BackgroundRemovalResult(cutout_png=b"c", mask_png=b"m", width=4, height=5, model="u2net")
    assert (r.cutout_png, r.mask_png, r.width, r.height, r.model) == (b"c", b"m", 4, 5, "u2net")
    with pytest.raises(FrozenInstanceError):
        r.width = 9  # type: ignore[misc]  # frozen


def test_background_model_resolution() -> None:
    # Default = current prod, unchanged by merely deploying.
    assert Settings(_env_file=None).background_model == "u2net"
    # Canonical knob switches the model.
    assert Settings(_env_file=None, bg_model="birefnet-general-lite").background_model == (
        "birefnet-general-lite"
    )
    # Legacy REMBG_MODEL honored ONLY while BG_MODEL is default (Azure image compat).
    assert Settings(_env_file=None, rembg_model="u2netp").background_model == "u2netp"
    # BG_MODEL wins over the legacy knob.
    assert (
        Settings(
            _env_file=None, bg_model="birefnet-general-lite", rembg_model="u2netp"
        ).background_model
        == "birefnet-general-lite"
    )


def test_prefetch_rejects_unsupported_model() -> None:
    # Validation fails (exit 2) BEFORE any rembg import / download — network-free.
    from app.scripts.prefetch_bg_model import main

    assert main(["--model", "not-a-real-model"]) == 2


def test_supported_model_sets() -> None:
    # The remover tolerates the legacy fast model (some Azure images bake it); the
    # prefetch script only downloads the two intended models.
    assert "u2netp" in SUPPORTED_BG_MODELS
    assert set(PREFETCHABLE_BG_MODELS) == {"u2net", "birefnet-general-lite"}
    assert set(PREFETCHABLE_BG_MODELS) <= SUPPORTED_BG_MODELS


# ── session lifecycle (mock rembg; skip where rembg absent) ───────────────────


def test_new_session_receives_configured_model_and_caches(monkeypatch) -> None:
    rembg = pytest.importorskip("rembg")
    calls: list[str] = []
    monkeypatch.setattr(rembg, "new_session", lambda name: calls.append(name) or object())
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    monkeypatch.setenv("BG_MODEL", "birefnet-general-lite")
    get_settings.cache_clear()
    get_background_remover.cache_clear()

    remover = get_background_remover()
    assert calls == ["birefnet-general-lite"]  # exactly the configured model
    assert remover.name == "rembg:birefnet-general-lite"
    # One session per process: the lru_cache returns the same instance, no reload.
    assert get_background_remover() is remover
    assert calls == ["birefnet-general-lite"]


def test_unsupported_model_raises(monkeypatch) -> None:
    rembg = pytest.importorskip("rembg")
    monkeypatch.setattr(rembg, "new_session", lambda name: object())
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    monkeypatch.setenv("BG_MODEL", "totally-made-up")
    get_settings.cache_clear()
    get_background_remover.cache_clear()
    with pytest.raises(ValueError):
        get_background_remover()


def test_v2_pipeline_preserves_soft_alpha_and_dims(monkeypatch) -> None:
    """With BG_MASK_PIPELINE_V2, the remover normalizes, requests a mask, keeps the
    soft alpha, composites, and returns cutout + mask at the source dimensions."""
    rembg = pytest.importorskip("rembg")
    monkeypatch.setattr(rembg, "new_session", lambda name: object())

    # A soft (mid-alpha) mask returned by the "model" at a DIFFERENT size — the
    # remover must resize it to the source and keep the intermediate value.
    def fake_remove(image, session=None, only_mask=False, **kw):
        assert only_mask is True
        assert kw.get("alpha_matting") is False
        assert kw.get("post_process_mask") is False
        return Image.new("L", (16, 12), 130)  # wrong size on purpose

    monkeypatch.setattr(rembg, "remove", fake_remove)
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    monkeypatch.setenv("BG_MODEL", "birefnet-general-lite")
    monkeypatch.setenv("BG_MASK_PIPELINE_V2", "true")
    get_settings.cache_clear()
    get_background_remover.cache_clear()

    src = io.BytesIO()
    Image.new("RGB", (40, 30), (10, 200, 10)).save(src, format="JPEG")
    result = asyncio.run(get_background_remover().remove(src.getvalue()))

    assert isinstance(result, BackgroundRemovalResult)
    assert (result.width, result.height) == (40, 30)
    assert result.mask_png is not None
    cutout = Image.open(io.BytesIO(result.cutout_png))
    assert cutout.mode == "RGBA" and cutout.size == (40, 30)
    # Soft alpha preserved (not hard-thresholded to 0/255).
    assert 100 < cutout.getpixel((20, 15))[3] < 160
    mask = Image.open(io.BytesIO(result.mask_png))
    assert mask.mode == "L" and mask.size == (40, 30)


def test_legacy_pipeline_returns_cutout_without_mask(monkeypatch) -> None:
    rembg = pytest.importorskip("rembg")
    monkeypatch.setattr(rembg, "new_session", lambda name: object())
    monkeypatch.setattr(rembg, "remove", lambda image, session=None, **kw: b"legacy-cutout")
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    monkeypatch.setenv("BG_MASK_PIPELINE_V2", "false")
    get_settings.cache_clear()
    get_background_remover.cache_clear()

    result = asyncio.run(get_background_remover().remove(b"orig"))
    assert result.cutout_png == b"legacy-cutout"
    assert result.mask_png is None  # rollback path persists no editable mask


# ── shared imaging helper ─────────────────────────────────────────────────────


def _jpeg(size=(40, 30), color=(200, 10, 10), exif_orientation: int | None = None) -> bytes:
    img = Image.new("RGB", size, color)
    buf = io.BytesIO()
    if exif_orientation is not None:
        exif = img.getexif()
        exif[0x0112] = exif_orientation
        img.save(buf, format="JPEG", exif=exif)
    else:
        img.save(buf, format="JPEG")
    return buf.getvalue()


def test_normalize_rejects_malformed_and_oversized() -> None:
    from app.services.bg import imaging

    with pytest.raises(imaging.ImageValidationError):
        imaging.normalize_source_image(b"not-an-image", max_edge=4096)
    with pytest.raises(imaging.ImageValidationError):
        imaging.normalize_source_image(_jpeg((40, 30)), max_edge=10)  # edge > cap


def test_normalize_applies_exif_transpose() -> None:
    from app.services.bg import imaging

    # Orientation 6 (90° CW) swaps the 40x30 source to 30x40 after transpose.
    norm = imaging.normalize_source_image(_jpeg((40, 30), exif_orientation=6), max_edge=4096)
    assert (norm.width, norm.height) == (30, 40)
    assert norm.image.mode == "RGB"


def test_coerce_model_mask_preserves_soft_alpha_and_matches_size() -> None:
    from app.services.bg import imaging

    coerced = imaging.coerce_model_mask(Image.new("L", (8, 8), 128), size=(40, 30))
    assert coerced.mode == "L" and coerced.size == (40, 30)
    assert coerced.getpixel((20, 15)) == 128  # intermediate value untouched


def test_sanitize_only_snaps_extremes() -> None:
    from app.services.bg import imaging

    src = Image.new("L", (4, 1))
    src.putdata([1, 128, 200, 254])
    sanitized = imaging.sanitize_soft_mask(src)
    out = [sanitized.getpixel((i, 0)) for i in range(4)]
    assert out == [0, 128, 200, 255]  # near-0 → 0, near-255 → 255, middles kept


def test_decode_uploaded_mask_extracts_alpha() -> None:
    from app.services.bg import imaging

    rgba = Image.new("RGBA", (40, 30), (0, 0, 0, 77))
    buf = io.BytesIO()
    rgba.save(buf, format="PNG")
    mask = imaging.decode_uploaded_mask(buf.getvalue(), max_edge=4096)
    assert mask.mode == "L" and mask.size == (40, 30)
    assert mask.getpixel((0, 0)) == 77


def test_decode_uploaded_mask_rejects_non_png() -> None:
    from app.services.bg import imaging

    with pytest.raises(imaging.ImageValidationError):
        imaging.decode_uploaded_mask(_jpeg((10, 10)), max_edge=4096)


# ── idempotent active-asset replacement (§9) ─────────────────────────────────


class _FakeTxn:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _ReplaceConn:
    """A conn stub for replace_cutout_assets: canned existing rows + captured SQL."""

    def __init__(self, existing_rows: list[dict], *, fail_on: str | None = None) -> None:
        self._existing = existing_rows
        self._fail_on = fail_on
        self.execute_sql: list[str] = []
        self.inserted = 0

    def transaction(self):
        return _FakeTxn()

    async def execute(self, sql: str, *args: object) -> None:
        if self._fail_on and self._fail_on in sql:
            raise RuntimeError("boom")
        self.execute_sql.append(sql)

    async def fetch(self, sql: str, *args: object) -> list[dict]:
        return self._existing if "media_assets" in sql else []

    async def fetchval(self, sql: str, *args: object):
        self.inserted += 1
        return "new-id"


class _RecordingProvider(R2StorageProvider):
    """R2 provider subclass (so the isinstance guard passes) that records deletes."""

    def __init__(self) -> None:  # no super().__init__ — avoid needing settings
        self.deleted: list[tuple[str, str | None]] = []

    async def delete(self, *, object_key, visibility, thumbnail_key=None) -> None:
        self.deleted.append((object_key, thumbnail_key))


def _stored(key: str, thumb: str | None = None) -> object:
    from app.services.media.base import StoredObject

    return StoredObject(
        object_key=key,
        bucket="priv",
        visibility="private",
        content_hash="h",
        public_url=None,
        thumbnail_key=thumb,
    )


def test_replace_inserts_when_no_active_row(monkeypatch) -> None:
    import app.services.media.repo as repo

    prov = _RecordingProvider()
    monkeypatch.setattr(repo, "get_storage_provider", lambda: prov)
    conn = _ReplaceConn([])  # nothing active yet
    asyncio.run(
        repo.replace_cutout_assets(
            conn,
            item_id="i1",
            user_id="u1",
            cutout=_stored("u1/cutout/new.png", "t.webp"),
            mask=None,
        )
    )
    assert conn.inserted == 1  # inserted via insert_asset
    assert any("cutout_status = 'done'" in s for s in conn.execute_sql)
    assert prov.deleted == []  # nothing displaced → nothing deleted


def test_replace_updates_in_place_and_deletes_old_after_commit(monkeypatch) -> None:
    import app.services.media.repo as repo

    prov = _RecordingProvider()
    monkeypatch.setattr(repo, "get_storage_provider", lambda: prov)
    existing = [{"id": "row1", "object_key": "u1/cutout/old.png", "thumbnail_key": "old.webp"}]
    conn = _ReplaceConn(existing)
    asyncio.run(
        repo.replace_cutout_assets(
            conn,
            item_id="i1",
            user_id="u1",
            cutout=_stored("u1/cutout/new.png", "new.webp"),
            mask=None,
        )
    )
    assert conn.inserted == 0  # updated in place, not inserted (no duplicate row)
    assert any("update public.media_assets set object_key" in s for s in conn.execute_sql)
    # Old object deleted only AFTER commit.
    assert prov.deleted == [("u1/cutout/old.png", "old.webp")]


def test_replace_cleans_up_new_objects_on_db_failure(monkeypatch) -> None:
    import app.services.media.repo as repo

    prov = _RecordingProvider()
    monkeypatch.setattr(repo, "get_storage_provider", lambda: prov)
    # Fail on the final wardrobe done-update, inside the transaction.
    conn = _ReplaceConn([], fail_on="cutout_status = 'done'")
    with pytest.raises(RuntimeError):
        asyncio.run(
            repo.replace_cutout_assets(
                conn,
                item_id="i1",
                user_id="u1",
                cutout=_stored("u1/cutout/new.png", "new.webp"),
                mask=_stored("u1/cutout-mask/new.png"),
            )
        )
    # The freshly-uploaded objects are cleaned up; the OLD ones (none) are untouched.
    assert ("u1/cutout/new.png", "new.webp") in prov.deleted
    assert ("u1/cutout-mask/new.png", None) in prov.deleted
