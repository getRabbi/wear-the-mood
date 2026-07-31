"""AI Studio shared job system — auth gates, the premium credit policy, and the
worker's success / fail-and-refund orchestration (BUILD_PROMPT_PRO_PROMAX.md P1)."""

from __future__ import annotations

import asyncio
import json
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import CreditsState, authorize_premium_ai
from app.core.errors import ApiError
from app.core.plans import FREE_PLAN, HD_COST, STD_COST, Plan
from app.core.supabase_auth import CurrentUser
from app.main import app
from app.models.ai_studio import EnhanceItemRequest
from app.services.imagegen.base import ImageGenNotConfigured
from app.services.imagegen.stub import StubImageEnhancer

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)

_PRO = Plan(tier="pro", kind="subscription", monthly_credits=75, hd_allowed=True, priority=False)
_PRO_MAX = Plan(
    tier="pro_max", kind="subscription", monthly_credits=150, hd_allowed=True, priority=True
)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token(sub: str = "user-123") -> str:
    now = int(time.time())
    payload = {
        "sub": sub,
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def _auth(extra: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {_token()}"}
    if extra:
        headers.update(extra)
    return headers


# ── auth + header gates (run before any DB access) ───────────────────────────


def test_enhance_requires_token() -> None:
    resp = client.post("/v1/ai/enhance", json={"wardrobe_item_id": str(uuid.uuid4())})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_catalog_requires_token() -> None:
    resp = client.post("/v1/ai/catalog-model", json={"wardrobe_item_id": str(uuid.uuid4())})
    assert resp.status_code == 401


def test_generated_requires_token() -> None:
    assert client.get("/v1/ai/generated").status_code == 401


def test_generated_list_excludes_removed(monkeypatch: pytest.MonkeyPatch) -> None:
    """Admin-removed outputs (0039) never come back to the owner's AI Looks."""
    import app.routers.v1.ai_studio as mod
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn([])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    asyncio.run(mod.list_generated(_user()))
    sql = next(s for m, s, _ in conn.calls if m == "fetch")
    assert "status = 'active'" in sql


def test_report_generated_files_moderation_report(monkeypatch: pytest.MonkeyPatch) -> None:
    """Self-reporting an AI output bumps the counter AND creates a reports row
    (0039 — the admin queue must be able to review it)."""
    import app.routers.v1.ai_studio as mod
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn(
        [
            ("fetchval", "update public.generated_images set report_count", uuid.uuid4()),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    asyncio.run(mod.report_generated(uuid.uuid4(), _user()))
    inserts = [s for m, s, _ in conn.calls if m == "execute"]
    assert any("insert into public.reports" in s and "'generated_image'" in s for s in inserts)


def test_report_generated_unknown_image_is_not_found(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.routers.v1.ai_studio as mod
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn([])  # update returns None → not the caller's image
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.report_generated(uuid.uuid4(), _user()))
    assert exc.value.code == "NOT_FOUND"
    assert not any("insert into public.reports" in s for m, s, _ in conn.calls)


def test_studio_models_requires_token() -> None:
    assert client.get("/v1/studio/models").status_code == 401


def test_ai_job_get_requires_token() -> None:
    assert client.get(f"/v1/ai/jobs/{uuid.uuid4()}").status_code == 401


def test_enhance_requires_idempotency_key() -> None:
    resp = client.post(
        "/v1/ai/enhance", json={"wardrobe_item_id": str(uuid.uuid4())}, headers=_auth()
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_enhance_rejects_bad_body() -> None:
    # Missing wardrobe_item_id -> validation fails before any DB access.
    resp = client.post(
        "/v1/ai/enhance", json={}, headers=_auth({"Idempotency-Key": str(uuid.uuid4())})
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


# ── authorize_premium_ai: the Pro/Pro Max + HD + cost policy gate ────────────


def _state(total: int) -> CreditsState:
    return CreditsState(balance=total, daily_free_used=999, daily_free_limit=3)


def test_premium_ai_free_user_blocked_even_with_credits() -> None:
    # AI Studio is subscriber-only — a free user is blocked even holding credits.
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=False, plan=FREE_PLAN, state=_state(10))
    assert exc.value.code == "PAYWALL"
    assert exc.value.status_code == 402


def test_premium_ai_pro_standard_costs_one() -> None:
    assert authorize_premium_ai(hd=False, plan=_PRO, state=_state(1)) == STD_COST


def test_premium_ai_pro_hd_requires_hd_allowed() -> None:
    no_hd = Plan(
        tier="pro", kind="subscription", monthly_credits=75, hd_allowed=False, priority=False
    )
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=True, plan=no_hd, state=_state(10))
    assert exc.value.code == "HD_LOCKED"
    assert exc.value.status_code == 403


def test_premium_ai_pro_max_hd_costs_four() -> None:
    assert authorize_premium_ai(hd=True, plan=_PRO_MAX, state=_state(4)) == HD_COST


def test_premium_ai_enhance_cost_override_is_four() -> None:
    # AI Enhance charges its OWN price (AI_ENHANCE_COST=4), independent of hd, and
    # is gated by that price — the single source of truth for the in-app cost.
    from app.core.plans import AI_ENHANCE_COST

    assert AI_ENHANCE_COST == 4
    assert authorize_premium_ai(hd=False, plan=_PRO, state=_state(4), cost=AI_ENHANCE_COST) == 4
    # 3 credits can't cover a 4-credit Enhance.
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=False, plan=_PRO, state=_state(3), cost=AI_ENHANCE_COST)
    assert exc.value.code == "PAYWALL"
    # A free user is still blocked regardless of the (higher) price.
    with pytest.raises(ApiError) as free_exc:
        authorize_premium_ai(hd=False, plan=FREE_PLAN, state=_state(10), cost=AI_ENHANCE_COST)
    assert free_exc.value.code == "PAYWALL"


def test_credits_response_exposes_enhance_cost_four() -> None:
    # The /v1/credits contract carries enhance_cost so the app shows the same 4.
    from app.core.plans import AI_ENHANCE_COST
    from app.models.credits import CreditsResponse

    base = dict(balance=0, daily_free_used=0, daily_free_limit=3, daily_free_remaining=3)
    assert CreditsResponse(**base).enhance_cost == 4
    assert CreditsResponse(**base, enhance_cost=AI_ENHANCE_COST).enhance_cost == AI_ENHANCE_COST


def test_premium_ai_insufficient_is_paywall() -> None:
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=False, plan=_PRO, state=_state(0))
    assert exc.value.code == "PAYWALL"
    assert exc.value.status_code == 402


# ── image enhancer stub: config-gated, never fakes success in prod ───────────


def test_enhancer_not_configured_raises() -> None:
    with pytest.raises(ImageGenNotConfigured):
        asyncio.run(StubImageEnhancer(mock=False).enhance(b"x"))


def test_enhancer_mock_echoes_input() -> None:
    out = asyncio.run(StubImageEnhancer(mock=True).enhance(b"bytes"))
    assert out == b"bytes"


# ── provider selection: FASHN Edit when configured, stub otherwise ───────────


def _clear_provider_caches() -> None:
    from app.services.imagegen import get_image_enhancer
    from app.services.tryon import get_tryon_provider

    get_settings.cache_clear()
    get_tryon_provider.cache_clear()
    get_image_enhancer.cache_clear()


def test_get_image_enhancer_uses_fashn_when_configured(monkeypatch) -> None:
    from app.services.imagegen import get_image_enhancer
    from app.services.imagegen.fashn_enhancer import FashnImageEnhancer

    monkeypatch.setenv("TRYON_PROVIDER", "fashn")
    monkeypatch.setenv("FASHN_API_KEY", "fa-real-key-abcd1234")
    _clear_provider_caches()
    try:
        assert isinstance(get_image_enhancer(), FashnImageEnhancer)
    finally:
        _clear_provider_caches()


def test_get_image_enhancer_stub_without_fashn(monkeypatch) -> None:
    from app.services.imagegen import get_image_enhancer

    monkeypatch.setenv("TRYON_PROVIDER", "stub")
    monkeypatch.delenv("FASHN_API_KEY", raising=False)
    _clear_provider_caches()
    try:
        assert isinstance(get_image_enhancer(), StubImageEnhancer)
    finally:
        _clear_provider_caches()


def test_fashn_enhancer_calls_edit_with_preserving_prompt(monkeypatch) -> None:
    import app.services.imagegen.fashn_enhancer as mod
    from app.services.imagegen.fashn_enhancer import FashnImageEnhancer
    from app.services.tryon.fashn import FashnTryOnProvider

    captured: dict = {}

    class _P(FashnTryOnProvider):
        def __init__(self) -> None:
            super().__init__("k")

        async def edit_image(self, *, image, prompt) -> str:
            captured["image"] = image
            captured["prompt"] = prompt
            return "https://cdn/enhanced.png"

    async def _dl(url):
        return b"ENHANCED-BYTES"

    monkeypatch.setattr(mod, "download_image", _dl)
    out = asyncio.run(FashnImageEnhancer(_P()).enhance(b"orig", content_type="image/png"))
    assert out == b"ENHANCED-BYTES"
    # AI Enhance = FASHN Edit with the conservative product-preserving prompt.
    assert captured["image"].startswith("data:image/png;base64,")
    assert "Preserve the garment shape" in captured["prompt"]
    assert "Do not change the product design" in captured["prompt"]


def test_mannequin_candidate_prompts_are_safe() -> None:
    import importlib.util
    from pathlib import Path

    path = Path(__file__).resolve().parents[2] / "scripts" / "generate_mannequin_candidates.py"
    spec = importlib.util.spec_from_file_location("gen_mannequin", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]

    prompts = mod.build_prompts()
    assert set(prompts) == set(mod.MANNEQUIN_STYLES)
    assert set(prompts) == {"female_studio", "modest", "male_studio", "curve", "neutral"}
    for p in prompts.values():
        low = p.lower()
        assert "full body" in low and "front facing" in low
        assert "not a toy doll" in low  # photorealistic mannequin, never toy-doll
        assert "no bag" in low and "no accessories" in low
        assert "realistic" in low


# ── worker orchestration: success keeps credit, failure refunds it ───────────


class _FakeConn:
    """Records execute()/fetchval() so we can assert what the worker wrote, without
    a live DB (matches the codebase's unit-test style)."""

    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()

    async def execute(self, sql: str, *args):
        self.executed.append((" ".join(sql.split()), args))
        return "UPDATE 1"

    async def fetchval(self, sql: str, *args):
        self.executed.append((" ".join(sql.split()), args))
        if "insert into public.generated_images" in sql:
            return "gen-1"
        return None

    async def fetchrow(self, sql: str, *args):
        return None

    async def fetch(self, sql: str, *args):
        return []

    def did(self, needle: str) -> bool:
        return any(needle in s for s, _ in self.executed)


def _job(job_type: str) -> dict:
    return {
        "id": uuid.uuid4(),
        "user_id": uuid.uuid4(),
        "job_type": job_type,
        "source_item_id": uuid.uuid4(),
        "style": "studio",
        "hd": False,
        "quality": "standard",
        "credits_reserved": 1,
    }


def _png(size: tuple[int, int] = (64, 48), mode: str = "RGB", color=(200, 120, 90)) -> bytes:
    """A real, decodable still — the enhance path normalises its source through
    Pillow, so a placeholder byte string would not exercise it."""
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new(mode, size, color).save(buf, format="PNG")
    return buf.getvalue()


def _patch_common(monkeypatch, worker_mod, *, source: bytes | None = None) -> None:
    async def _fetch_url(conn, user_id, item_id):
        return "https://x/item.png"

    async def _download(url):
        return source if source is not None else _png()

    async def _store(conn, *, user_id, role, image, content_type):
        return f"{user_id}/{role}/out.png", None

    monkeypatch.setattr(worker_mod, "_item_fetch_url", _fetch_url)
    monkeypatch.setattr(worker_mod, "_enhance_source_url", _fetch_url)
    monkeypatch.setattr(worker_mod, "download_image", _download)
    monkeypatch.setattr(worker_mod, "_store_output", _store)


def test_worker_enhance_success_updates_item_and_completes(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=True))

    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, _job("enhance_item")))

    assert conn.did("set status = 'completed'")
    assert conn.did("set enhanced_image_url")
    assert conn.did("insert into public.generated_images")
    assert not conn.did("set status = 'failed'")


def test_worker_enhance_not_configured_fails_and_refunds(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=False))

    refunds: list[str] = []

    async def _refund(conn, user_id, *, ref):
        refunds.append(ref)
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)

    job = _job("enhance_item")
    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, job))

    assert conn.did("set status = 'failed'")
    assert conn.did("set ai_status = 'failed'")  # item flag cleared
    assert refunds == [str(job["id"])]  # credit released


def test_worker_catalog_unconfigured_fails_and_refunds(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod
    from app.services.tryon.stub import StubTryOnProvider

    _patch_common(monkeypatch, worker_mod)
    # Single provider = FASHN; a non-FASHN (stub) provider => not configured.
    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: StubTryOnProvider())

    refunds: list[str] = []

    async def _refund(conn, user_id, *, ref):
        refunds.append(ref)
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)

    job = _job("catalog_model")
    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, job))

    assert conn.did("set status = 'failed'")
    assert refunds == [str(job["id"])]


def test_worker_catalog_success_uses_product_to_model(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod
    from app.services.tryon.fashn import FashnTryOnProvider

    _patch_common(monkeypatch, worker_mod)

    calls: list[dict] = []

    class _FakeFashn(FashnTryOnProvider):
        def __init__(self) -> None:
            super().__init__("test-key")

        async def product_to_model(
            self,
            *,
            product_image,
            prompt,
            aspect_ratio="3:4",
        ) -> str:
            calls.append({"product_image": product_image, "prompt": prompt})
            return "https://cdn/catalog.png"

    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: _FakeFashn())

    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, _job("catalog_model")))

    assert conn.did("set status = 'completed'")
    assert conn.did("insert into public.generated_images")
    assert len(calls) == 1
    # Product-to-Model: the item is the PRODUCT (inlined as base64), style → prompt.
    # The worker passes NO resolution/mode — the provider pins fast·1k (spend cap).
    assert calls[0]["product_image"].startswith("data:image/png;base64,")
    assert "model" in calls[0]["prompt"].lower()
    # Catalog NEVER overwrites the wardrobe item's own image.
    assert not conn.did("set enhanced_image_url")


# ── AI Enhance: the source the provider actually receives ────────────────────
# Enhance is judged on lighting, contrast and texture, all of which live in the
# ORIGINAL photograph. Feeding it the alpha cutout instead left the model nothing
# to improve but edge contrast — the "it only sharpens now" regression.


def test_enhance_reads_the_original_not_the_cutout() -> None:
    """The enhance source resolver asks for `original` first; the display resolver
    still asks for `cutout` first. The two precedences are deliberately opposite."""
    import app.workers.ai_jobs_worker as worker_mod

    seen: list[tuple] = []

    async def _resolve(conn, kind, ids, roles):
        seen.append(tuple(roles))
        return {}

    async def _fetchval(sql, *args):
        return "https://x/original.jpg"

    class _Conn:
        fetchval = staticmethod(_fetchval)

    import app.services.media.repo as repo_mod

    original_resolve = worker_mod.resolve_images
    worker_mod.resolve_images = _resolve
    repo_mod.resolve_images = _resolve
    try:
        asyncio.run(worker_mod._enhance_source_url(_Conn(), "u1", "i1"))
        asyncio.run(worker_mod._item_fetch_url(_Conn(), "u1", "i1"))
    finally:
        worker_mod.resolve_images = original_resolve
        repo_mod.resolve_images = original_resolve

    assert seen[0] == ("original", "cutout")  # enhance
    assert seen[1] == ("cutout", "original")  # display


def test_enhance_source_declares_the_content_type_it_actually_sends(monkeypatch) -> None:
    """A local cutout is lossless WebP. The worker used to hand the provider those
    bytes labelled `image/png`; the prepared source must describe itself."""
    import io

    from PIL import Image

    import app.workers.ai_jobs_worker as worker_mod

    buf = io.BytesIO()
    Image.new("RGBA", (40, 30), (10, 20, 30, 255)).save(buf, format="WEBP", lossless=True)
    _patch_common(monkeypatch, worker_mod, source=buf.getvalue())

    sent: list[tuple[bytes, str]] = []

    class _Recorder:
        name = "fashn"

        async def enhance(self, image, *, content_type="image/png"):
            sent.append((image, content_type))
            return _png()

    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: _Recorder())
    asyncio.run(worker_mod.process_ai_job(_FakeConn(), _job("enhance_item")))

    assert len(sent) == 1
    payload, declared = sent[0]
    assert declared == "image/png"
    assert payload.startswith(b"\x89PNG\r\n")  # the bytes match the declaration


def test_enhance_source_flattens_alpha_and_bounds_the_long_edge() -> None:
    """Transparency is composited onto studio white (never left for the provider to
    flatten onto black), and an oversized original is bounded WITHOUT distorting it."""
    import io

    from PIL import Image

    from app.services.bg.imaging import prepare_enhance_source

    buf = io.BytesIO()
    # Fully transparent pixels: if alpha were dropped rather than composited, the
    # result would be black, which is what starved the model of anything to fix.
    Image.new("RGBA", (3000, 1500), (0, 0, 0, 0)).save(buf, format="PNG")

    data, content_type, width, height = prepare_enhance_source(buf.getvalue(), max_edge=2048)

    assert content_type == "image/png"
    assert (width, height) == (2048, 1024)  # bounded, aspect ratio 2:1 preserved
    out = Image.open(io.BytesIO(data))
    assert out.mode == "RGB"
    assert out.getpixel((0, 0)) == (255, 255, 255)


def test_enhance_source_never_upscales_a_small_original() -> None:
    import io

    from PIL import Image

    from app.services.bg.imaging import prepare_enhance_source

    buf = io.BytesIO()
    Image.new("RGB", (300, 400), (5, 5, 5)).save(buf, format="JPEG")
    _, _, width, height = prepare_enhance_source(buf.getvalue(), max_edge=2048)
    assert (width, height) == (300, 400)


def test_enhance_unreadable_source_fails_and_refunds(monkeypatch) -> None:
    """A source we cannot decode is a clean failure + refund — never a charge for
    an enhancement that was never attempted."""
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod, source=b"not-an-image")
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=True))

    refunds: list[str] = []

    async def _refund(conn, user_id, *, ref):
        refunds.append(ref)
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)

    job = _job("enhance_item")
    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, job))

    assert conn.did("set status = 'failed'")
    assert refunds == [str(job["id"])]
    assert not conn.did("set enhanced_image_url")  # the good cutout is left alone


def test_enhance_empty_provider_output_fails_and_refunds(monkeypatch) -> None:
    """An empty body is not a result: refund rather than store a zero-byte cover."""
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)

    class _Empty:
        name = "fashn"

        async def enhance(self, image, *, content_type="image/png"):
            return b""

    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: _Empty())

    refunds: list[str] = []

    async def _refund(conn, user_id, *, ref):
        refunds.append(ref)
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)

    job = _job("enhance_item")
    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, job))

    assert conn.did("set status = 'failed'")
    assert refunds == [str(job["id"])]
    assert not conn.did("set enhanced_image_url")


def test_enhance_provider_timeout_fails_and_refunds(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)

    class _Timeout:
        name = "fashn"

        async def enhance(self, image, *, content_type="image/png"):
            raise TimeoutError("FASHN run timed out")

    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: _Timeout())

    refunds: list[str] = []

    async def _refund(conn, user_id, *, ref):
        refunds.append(ref)
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)

    job = _job("enhance_item")
    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, job))

    assert conn.did("set status = 'failed'")
    assert refunds == [str(job["id"])]


def test_fashn_enhancer_inlines_the_declared_content_type() -> None:
    """The data URI's media type must be the one the caller declared, so a WebP
    source is never announced as PNG."""
    from app.services.imagegen.fashn_enhancer import FashnImageEnhancer

    seen: list[str] = []

    class _Provider:
        async def edit_image(self, *, image, prompt):
            seen.append(image)
            return "https://cdn/out.png"

    async def _run():
        import app.services.imagegen.fashn_enhancer as mod

        async def _download(url):
            return b"result"

        original = mod.download_image
        mod.download_image = _download
        try:
            return await FashnImageEnhancer(_Provider()).enhance(
                b"\x00\x01", content_type="image/webp"
            )
        finally:
            mod.download_image = original

    assert asyncio.run(_run()) == b"result"
    assert seen[0].startswith("data:image/webp;base64,")


# ── the user is told when an async job finishes ──────────────────────────────
# These jobs run for tens of seconds and the user routinely leaves the processing
# screen. A result nobody is told about is a result they do not know they paid
# for — and a refund they never learn happened.


def _capture_notifications(monkeypatch, worker_mod) -> list[dict]:
    sent: list[dict] = []

    async def _create(conn, **kwargs):
        sent.append(kwargs)
        from app.services.notifications import NotificationOutcome

        return NotificationOutcome(True, "n-1")

    monkeypatch.setattr(worker_mod, "create_notification", _create)
    return sent


def test_completed_enhance_notifies_and_opens_the_item(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=True))
    sent = _capture_notifications(monkeypatch, worker_mod)

    job = _job("enhance_item")
    asyncio.run(worker_mod.process_ai_job(_FakeConn(), job))

    assert len(sent) == 1
    note = sent[0]
    assert note["user_id"] == str(job["user_id"])
    assert note["type"] == "enhance_item"
    # Opens the item whose cover just changed.
    assert note["target_type"] == "wardrobe_item"
    assert note["target_id"] == str(job["source_item_id"])
    # One per job, whatever happens upstream — a recovery re-claim cannot restate it.
    assert note["dedupe_key"] == f"ai_job:{job['id']}:done"

    from app.services.notifications import route_for

    assert route_for(note["type"], note["target_type"], note["target_id"]).startswith(
        "/wtm/closet/item?id="
    )


def test_completed_catalog_notifies_and_opens_the_generated_image(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod
    from app.services.tryon.fashn import FashnTryOnProvider

    _patch_common(monkeypatch, worker_mod)

    class _FakeFashn(FashnTryOnProvider):
        def __init__(self) -> None:
            super().__init__("test-key")

        async def product_to_model(self, *, product_image, prompt, aspect_ratio="3:4") -> str:
            return "https://cdn/catalog.png"

    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: _FakeFashn())
    sent = _capture_notifications(monkeypatch, worker_mod)

    job = _job("catalog_model")
    asyncio.run(worker_mod.process_ai_job(_FakeConn(), job))

    assert len(sent) == 1
    note = sent[0]
    assert note["type"] == "catalog_model"
    assert note["target_type"] == "generated_image"
    assert note["target_id"] == "gen-1"  # the row _FakeConn returns
    assert note["dedupe_key"] == f"ai_job:{job['id']}:done"

    from app.services.notifications import route_for

    assert route_for(note["type"], note["target_type"], note["target_id"]) == "/wtm/looks"


def test_failed_job_notifies_about_the_refund(monkeypatch) -> None:
    """The refund is the part the user must not have to discover for themselves."""
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=False))

    async def _refund(conn, user_id, *, ref):
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)
    sent = _capture_notifications(monkeypatch, worker_mod)

    job = _job("enhance_item")
    asyncio.run(worker_mod.process_ai_job(_FakeConn(), job))

    assert len(sent) == 1
    note = sent[0]
    assert note["type"] == "enhance_item"
    assert note["dedupe_key"] == f"ai_job:{job['id']}:failed"
    # Still opens somewhere real — the item is untouched and still there.
    assert note["target_type"] == "wardrobe_item"


def test_job_notification_is_written_inside_the_completion_transaction(monkeypatch) -> None:
    """It must not be possible to announce a result the database has not recorded,
    so the notification shares the completion's transaction."""
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=True))

    depth: list[bool] = []

    class _TrackingConn(_FakeConn):
        def __init__(self) -> None:
            super().__init__()
            self.in_txn = False

        def transaction(self):
            outer = self

            class _Tx:
                async def __aenter__(self_):
                    outer.in_txn = True
                    return self_

                async def __aexit__(self_, *_a):
                    outer.in_txn = False
                    return False

            return _Tx()

    conn = _TrackingConn()

    async def _create(c, **kwargs):
        depth.append(c.in_txn)
        from app.services.notifications import NotificationOutcome

        return NotificationOutcome(True, "n-1")

    monkeypatch.setattr(worker_mod, "create_notification", _create)
    asyncio.run(worker_mod.process_ai_job(conn, _job("enhance_item")))

    assert depth == [True]


# ── enhance never charges twice for the same in-flight item ──────────────────


def test_enhance_reuses_an_in_flight_job_instead_of_charging_again(monkeypatch) -> None:
    """A second tap / retry while a job is queued or processing returns the SAME
    job id and reserves nothing. The idempotency KEY cannot cover this: a genuine
    second tap mints a fresh key."""
    import app.routers.v1.ai_studio as mod

    running_id = uuid.uuid4()
    item_id = uuid.uuid4()
    spends: list[int] = []

    locks: list[tuple] = []

    class _Conn:
        def transaction(self):
            class _Tx:
                async def __aenter__(self_):
                    return self_

                async def __aexit__(self_, *_a):
                    return False

            return _Tx()

        async def fetchval(self, sql: str, *args):
            if "insert into public.ai_jobs" in sql:
                raise AssertionError("must not create a second job")
            if "from public.ai_jobs" in sql:
                return running_id
            if "from public.wardrobe_items" in sql:
                return 1
            return None

        async def execute(self, sql: str, *args):
            if "pg_advisory_xact_lock" in sql:
                locks.append(args)
            return "UPDATE 1"

        async def fetchrow(self, sql: str, *args):
            return None

    class _Pool:
        def acquire(self):
            class _Ctx:
                async def __aenter__(self_):
                    return _Conn()

                async def __aexit__(self_, *_a):
                    return False

            return _Ctx()

    async def _no_stored(conn, key, user_id, endpoint):
        return None

    async def _reserve(conn, key, user_id, endpoint):
        return True

    async def _store(conn, key, user_id, endpoint, status, response):
        return None

    async def _flag(conn, name, default=True):
        return True

    async def _spend(conn, user_id, *, cost, ref):
        spends.append(cost)

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool())
    monkeypatch.setattr(mod, "get_stored_response", _no_stored)
    monkeypatch.setattr(mod, "reserve_key", _reserve)
    monkeypatch.setattr(mod, "store_response", _store)
    monkeypatch.setattr(mod, "flag_enabled", _flag)
    monkeypatch.setattr(mod, "spend_credit", _spend)

    resp = client.post(
        "/v1/ai/enhance",
        json={"wardrobe_item_id": str(item_id)},
        headers=_auth({"Idempotency-Key": str(uuid.uuid4())}),
    )

    assert resp.status_code == 202
    assert resp.json()["job_id"] == str(running_id)
    assert spends == []  # nothing reserved a second time
    # The lookup happened UNDER the advisory lock, keyed on (user, type, item).
    assert len(locks) == 1
    assert locks[0][0] == mod._AI_JOB_LOCK_NAMESPACE
    assert locks[0][1] == mod.ai_job_lock_key("user-123", "enhance_item", item_id)


def test_two_concurrent_enhances_create_one_job_and_one_debit(monkeypatch) -> None:
    """The real race: two SIMULTANEOUS submits, same user, same item, DIFFERENT
    idempotency keys, enough balance for both.

    Before the advisory lock both requests read "nothing running" and both
    reserved 4 credits. Here the fake connection honours `pg_advisory_xact_lock`
    with a real asyncio lock held until the transaction exits, which is exactly
    the guarantee Postgres provides — so this pins the ORDERING the router
    depends on: lock, then look, then write, all in one transaction.
    """
    import app.routers.v1.ai_studio as mod

    item_id = uuid.uuid4()
    created_jobs: list[str] = []
    spends: list[int] = []
    key_locks: dict[str, asyncio.Lock] = {}

    class _Conn:
        """One connection per request, sharing the module-level job table."""

        def __init__(self) -> None:
            self._held: asyncio.Lock | None = None

        def transaction(self):
            conn = self

            class _Tx:
                async def __aenter__(self_):
                    return self_

                async def __aexit__(self_, *_a):
                    # pg_advisory_xact_lock releases on commit AND on rollback.
                    if conn._held is not None:
                        conn._held.release()
                        conn._held = None
                    return False

            return _Tx()

        async def execute(self, sql: str, *args):
            if "pg_advisory_xact_lock" in sql:
                lock = key_locks.setdefault(args[1], asyncio.Lock())
                await lock.acquire()
                self._held = lock
            return "UPDATE 1"

        async def fetchval(self, sql: str, *args):
            if "from public.wardrobe_items" in sql:
                return 1
            if "select id from public.ai_jobs" in sql:
                # Only rows already committed by a finished transaction.
                return created_jobs[0] if created_jobs else None
            if "insert into public.ai_jobs" in sql:
                job_id = str(uuid.uuid4())
                created_jobs.append(job_id)
                return job_id
            return None

        async def fetchrow(self, sql: str, *args):
            return None

    class _Pool:
        def acquire(self):
            class _Ctx:
                async def __aenter__(self_):
                    return _Conn()

                async def __aexit__(self_, *_a):
                    return False

            return _Ctx()

    async def _no_stored(conn, key, user_id, endpoint):
        return None

    async def _reserve(conn, key, user_id, endpoint):
        return True  # two DIFFERENT keys — both reserve cleanly, so no 409

    stored: list[tuple] = []

    async def _store(conn, key, user_id, endpoint, status, response):
        stored.append((key, status, response))

    async def _flag(conn, name, default=True):
        return True

    async def _spend(conn, user_id, *, cost, ref):
        spends.append(cost)

    async def _plan(conn, user_id):
        return _PRO_MAX

    async def _credits(conn, user_id):
        return _state(100)  # ample balance for BOTH jobs

    async def _signal(kind, ref):
        return False

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool())
    monkeypatch.setattr(mod, "get_stored_response", _no_stored)
    monkeypatch.setattr(mod, "reserve_key", _reserve)
    monkeypatch.setattr(mod, "store_response", _store)
    monkeypatch.setattr(mod, "flag_enabled", _flag)
    monkeypatch.setattr(mod, "spend_credit", _spend)
    monkeypatch.setattr(mod, "user_plan", _plan)
    monkeypatch.setattr(mod, "get_credits", _credits)
    monkeypatch.setattr(mod, "enqueue_signal", _signal)

    async def submit() -> tuple[int, dict]:
        resp = await mod.enhance_item(
            EnhanceItemRequest(wardrobe_item_id=item_id),
            user=CurrentUser("user-123", None, {}),
            idempotency_key=str(uuid.uuid4()),  # a DIFFERENT key each time
        )
        return resp.status_code, json.loads(resp.body)

    async def race() -> list[tuple[int, dict]]:
        return list(await asyncio.gather(submit(), submit()))

    results = asyncio.run(race())

    assert len(created_jobs) == 1, "exactly one AI job"
    assert spends == [4], "exactly one 4-credit debit"
    assert [status for status, _ in results] == [202, 202], "no 409, both accepted"
    assert {body["job_id"] for _, body in results} == {created_jobs[0]}, "same job id"
    # Both keys have a stored response, and they agree — a later replay of either
    # returns the same job rather than a contradictory one.
    assert len(stored) == 2
    assert {r["job_id"] for _, _, r in stored} == {created_jobs[0]}


def test_a_terminal_job_does_not_block_a_new_one(monkeypatch) -> None:
    """The guard is about CONCURRENCY, not a permanent lockout: once a job is
    completed or failed, the user can deliberately run it again."""
    import app.routers.v1.ai_studio as mod

    item_id = uuid.uuid4()
    created: list[str] = []

    class _Conn:
        def transaction(self):
            class _Tx:
                async def __aenter__(self_):
                    return self_

                async def __aexit__(self_, *_a):
                    return False

            return _Tx()

        async def execute(self, sql: str, *args):
            return "UPDATE 1"

        async def fetchval(self, sql: str, *args):
            if "from public.wardrobe_items" in sql:
                return 1
            if "select id from public.ai_jobs" in sql:
                # The in-flight query filters status in ('queued','processing'),
                # so a completed job simply does not match.
                assert "status in ('queued', 'processing')" in " ".join(sql.split())
                return None
            if "insert into public.ai_jobs" in sql:
                job_id = str(uuid.uuid4())
                created.append(job_id)
                return job_id
            return None

        async def fetchrow(self, sql: str, *args):
            return None

    class _Pool:
        def acquire(self):
            class _Ctx:
                async def __aenter__(self_):
                    return _Conn()

                async def __aexit__(self_, *_a):
                    return False

            return _Ctx()

    async def _noop(*a, **k):
        return None

    async def _true(*a, **k):
        return True

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool())
    monkeypatch.setattr(mod, "get_stored_response", _noop)
    monkeypatch.setattr(mod, "reserve_key", _true)
    monkeypatch.setattr(mod, "store_response", _noop)
    monkeypatch.setattr(mod, "flag_enabled", _true)
    monkeypatch.setattr(mod, "spend_credit", _noop)
    monkeypatch.setattr(mod, "enqueue_signal", _noop)

    async def _plan(conn, user_id):
        return _PRO_MAX

    async def _credits(conn, user_id):
        return _state(100)

    monkeypatch.setattr(mod, "user_plan", _plan)
    monkeypatch.setattr(mod, "get_credits", _credits)

    resp = client.post(
        "/v1/ai/enhance",
        json={"wardrobe_item_id": str(item_id)},
        headers=_auth({"Idempotency-Key": str(uuid.uuid4())}),
    )
    assert resp.status_code == 202
    assert len(created) == 1


def test_advisory_lock_really_serialises_live() -> None:
    """The mutual exclusion above is the FAKE honouring the contract. This proves
    the contract itself against a real Postgres, using the router's own key
    derivation: a second transaction taking the same key genuinely blocks until
    the first commits."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    import app.routers.v1.ai_studio as mod

    key = mod.ai_job_lock_key(str(uuid.uuid4()), "enhance_item", uuid.uuid4())
    order: list[str] = []

    async def run() -> None:
        import asyncpg

        dsn = get_settings().connection_string
        first = await asyncpg.connect(dsn=dsn, statement_cache_size=0, ssl="require")
        second = await asyncpg.connect(dsn=dsn, statement_cache_size=0, ssl="require")
        try:
            holder_released = asyncio.Event()

            async def holder() -> None:
                async with first.transaction():
                    await first.execute(
                        "select pg_advisory_xact_lock($1::int, hashtext($2)::int)",
                        mod._AI_JOB_LOCK_NAMESPACE,
                        key,
                    )
                    order.append("first-locked")
                    await asyncio.sleep(0.4)  # hold it while the contender tries
                    order.append("first-committing")
                holder_released.set()

            async def contender() -> None:
                await asyncio.sleep(0.1)  # ensure the holder locks first
                async with second.transaction():
                    await second.execute(
                        "select pg_advisory_xact_lock($1::int, hashtext($2)::int)",
                        mod._AI_JOB_LOCK_NAMESPACE,
                        key,
                    )
                    order.append("second-locked")

            await asyncio.gather(holder(), contender())
        finally:
            await first.close()
            await second.close()

    asyncio.run(run())

    # The contender did NOT get in until the holder's transaction ended.
    assert order == ["first-locked", "first-committing", "second-locked"]


# ── inactive studio presets are hidden by the serving query (rolled back) ────


def test_inactive_studio_preset_is_hidden_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        tr = conn.transaction()
        await tr.start()
        try:
            # One INACTIVE + one ACTIVE studio preset, both WITH an image.
            await conn.execute(
                "insert into public.tryon_model_presets "
                "(kind, name, style, is_active, image_url) values "
                "('studio_tryon','T-inactive','zzz_test_inactive',false,'https://x/i.png'),"
                "('studio_tryon','T-active','zzz_test_active',true,'https://x/a.png')"
            )
            rows = await conn.fetch(
                "select style from public.tryon_model_presets "
                "where kind='studio_tryon' and is_active=true and image_url is not null "
                "and style like 'zzz_test_%'"
            )
            styles = {r["style"] for r in rows}
            assert "zzz_test_active" in styles  # active shows
            assert "zzz_test_inactive" not in styles  # inactive is hidden
        finally:
            await tr.rollback()  # never persist the test rows
            await conn.close()

    asyncio.run(run())


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_ai_jobs_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "insert into public.ai_jobs "
        "(user_id, job_type, status, source_item_id, style, hd, quality, "
        "credits_reserved, idempotency_key) "
        "values ($1::uuid, $2, 'queued', $3::uuid, $4, $5, $6, $7, $8) returning id",
        # worker claim returns the fields process_ai_job needs (scoped is via id)
        "update public.ai_jobs set status = 'processing' where id = "
        "(select id from public.ai_jobs where status = 'queued' "
        "order by created_at for update skip locked limit 1) "
        "returning id, user_id, job_type, source_item_id, style, hd, quality, credits_reserved",
        # user-scoped read (cross-user isolation)
        "select id, job_type, status, output_urls, error_message from public.ai_jobs "
        "where id = $1::uuid and user_id = $2::uuid",
        "insert into public.generated_images "
        "(user_id, source_item_id, job_id, type, output_url, is_ai_generated) "
        "values ($1::uuid, $2, $3::uuid, $4, $5, true) returning id",
        "select id, type, output_url, source_item_id, is_ai_generated, created_at "
        "from public.generated_images where user_id = $1::uuid order by created_at desc limit 200",
        "select id, name, image_url, style, body_type, skin_tone, pose_type, is_pro_only "
        "from public.tryon_model_presets where kind = 'studio_tryon' and is_active = true "
        "and image_url is not null order by sort_order",
        "update public.wardrobe_items set enhanced_image_url = $2, cover_image_url = $2, "
        "ai_enhanced = true, ai_status = 'done' where id = $1::uuid",
        "alter table public.tryon_jobs add column if not exists model_source text",
        # catalog model resolution (the worker's _active_catalog_model query)
        "select id, image_url from public.tryon_model_presets "
        "where kind = 'catalog' and is_active = true and image_url is not null "
        "and ($1::text is null or style = $1) order by sort_order limit 1",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())


# ── a failure notification must always confirm the refund ────────────────────


def _failed_note(monkeypatch, error: str) -> dict:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: StubImageEnhancer(mock=False))

    async def _refund(conn, user_id, *, ref):
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)
    sent = _capture_notifications(monkeypatch, worker_mod)

    class _Failing:
        name = "fashn"

        async def enhance(self, image, *, content_type="image/png"):
            from app.services.imagegen.base import ImageGenError

            raise ImageGenError(error)

    monkeypatch.setattr(worker_mod, "get_image_enhancer", lambda: _Failing())
    asyncio.run(worker_mod.process_ai_job(_FakeConn(), _job("enhance_item")))
    assert len(sent) == 1
    return sent[0]


def test_enhance_failure_body_always_confirms_the_refund(monkeypatch) -> None:
    note = _failed_note(monkeypatch, "We couldn't read that item's photo.")
    # A present reason must never displace the refund confirmation, which is the
    # part the user actually needs.
    assert note["body"].startswith("Your credits were refunded.")
    assert "couldn't read" in note["body"]


def test_enhance_failure_confirms_the_refund_even_with_no_reason(monkeypatch) -> None:
    note = _failed_note(monkeypatch, "")
    assert note["body"].startswith("Your credits were refunded.")


def test_enhance_failure_never_leaks_provider_internals(monkeypatch) -> None:
    note = _failed_note(monkeypatch, "https://cdn.fashn.ai/a.png?X-Amz-Signature=deadbeef")
    body = note["body"]
    assert body.startswith("Your credits were refunded.")
    assert "http" not in body and "X-Amz" not in body


def test_catalog_failure_copy_confirms_the_refund(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod
    from app.services.tryon.stub import StubTryOnProvider

    _patch_common(monkeypatch, worker_mod)
    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: StubTryOnProvider())

    async def _refund(conn, user_id, *, ref):
        return True

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)
    sent = _capture_notifications(monkeypatch, worker_mod)

    asyncio.run(worker_mod.process_ai_job(_FakeConn(), _job("catalog_model")))

    assert len(sent) == 1
    assert sent[0]["type"] == "catalog_model"
    assert sent[0]["body"].startswith("Your credits were refunded.")
    assert sent[0]["dedupe_key"].endswith(":failed")
