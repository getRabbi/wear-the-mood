"""AI Studio shared job system — auth gates, the premium credit policy, and the
worker's success / fail-and-refund orchestration (BUILD_PROMPT_PRO_PROMAX.md P1)."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import CreditsState, authorize_premium_ai
from app.core.errors import ApiError
from app.core.plans import FREE_PLAN, HD_COST, STD_COST, Plan
from app.main import app
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
        "sub": sub, "aud": "authenticated", "email": "a@b.com",
        "role": "authenticated", "iat": now, "exp": now + 3600,
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
        "id": uuid.uuid4(), "user_id": uuid.uuid4(), "job_type": job_type,
        "source_item_id": uuid.uuid4(), "style": "studio", "hd": False,
        "quality": "standard", "credits_reserved": 1,
    }


def _patch_common(monkeypatch, worker_mod) -> None:
    async def _fetch_url(conn, user_id, item_id):
        return "https://x/item.png"

    async def _download(url):
        return b"image-bytes"

    async def _store(conn, *, user_id, role, image, content_type):
        return f"{user_id}/{role}/out.png", None

    monkeypatch.setattr(worker_mod, "_item_fetch_url", _fetch_url)
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

    _patch_common(monkeypatch, worker_mod)

    async def _no_model(conn, style):
        return None  # no active catalog preset configured

    monkeypatch.setattr(worker_mod, "_active_catalog_model", _no_model)

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


def test_worker_catalog_success_uses_tryon_provider(monkeypatch) -> None:
    import app.workers.ai_jobs_worker as worker_mod

    _patch_common(monkeypatch, worker_mod)

    async def _model(conn, style):
        return {"id": "preset-1", "image_url": "https://x/model.jpg"}

    monkeypatch.setattr(worker_mod, "_active_catalog_model", _model)

    calls: list[tuple[str, str]] = []

    class _Provider:
        name = "fashn"

        async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
            calls.append((person_image_url, garment_image_url))
            return "https://cdn/result.png"

    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: _Provider())

    conn = _FakeConn()
    asyncio.run(worker_mod.process_ai_job(conn, _job("catalog_model")))

    assert conn.did("set status = 'completed'")
    assert conn.did("insert into public.generated_images")
    # Catalog renders the garment ON the model (model=person, item=garment).
    assert calls == [("https://x/model.jpg", "https://x/item.png")]
    # Catalog NEVER overwrites the wardrobe item's own image.
    assert not conn.did("set enhanced_image_url")


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
