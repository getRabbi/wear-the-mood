import asyncio

import pytest

from app.core.config import get_settings
from app.services.bg import get_background_remover
from app.services.bg.base import BackgroundRemover
from app.services.bg.stub import StubBackgroundRemover


@pytest.fixture(autouse=True)
def _clear_cache():
    get_background_remover.cache_clear()
    get_settings.cache_clear()
    yield
    get_background_remover.cache_clear()
    get_settings.cache_clear()


def test_stub_routing(monkeypatch: pytest.MonkeyPatch) -> None:
    # api / cron / CI run with the light stub (BG_PROVIDER=stub).
    monkeypatch.setenv("BG_PROVIDER", "stub")
    get_settings.cache_clear()
    get_background_remover.cache_clear()
    remover = get_background_remover()
    assert isinstance(remover, BackgroundRemover)
    assert remover.name == "stub"


def test_stub_remover_echoes_bytes() -> None:
    out = asyncio.run(StubBackgroundRemover().remove(b"image-bytes"))
    assert out == b"image-bytes"


def test_rembg_routing(monkeypatch: pytest.MonkeyPatch) -> None:
    # BG_PROVIDER=rembg routes to the rembg remover via a lazy import. rembg is
    # worker-only: where it isn't installed (CI/api) the import raises rather than
    # pulling onnxruntime; where it is (the worker / local dev) it resolves.
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    get_settings.cache_clear()
    get_background_remover.cache_clear()
    try:
        import rembg  # noqa: F401
    except ModuleNotFoundError:
        with pytest.raises(ModuleNotFoundError):
            get_background_remover()
    else:
        assert get_background_remover().name == "rembg"
