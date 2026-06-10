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


def test_default_remover_is_stub() -> None:
    remover = get_background_remover()
    assert isinstance(remover, BackgroundRemover)
    assert remover.name == "stub"


def test_stub_remover_echoes_bytes() -> None:
    out = asyncio.run(StubBackgroundRemover().remove(b"image-bytes"))
    assert out == b"image-bytes"


def test_rembg_routing_lazy_imports(monkeypatch: pytest.MonkeyPatch) -> None:
    # BG_PROVIDER=rembg reaches the lazy import; rembg isn't installed in
    # CI/api/local (worker-only), so it raises rather than pulling onnxruntime.
    monkeypatch.setenv("BG_PROVIDER", "rembg")
    get_settings.cache_clear()
    get_background_remover.cache_clear()
    with pytest.raises(ModuleNotFoundError):
        get_background_remover()
