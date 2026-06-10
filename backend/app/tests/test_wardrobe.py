import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.wardrobe import WardrobeItemCreate

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token() -> str:
    now = int(time.time())
    payload = {
        "sub": "user-123",
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


# ── auth gates (run before any DB access) ────────────────────────────────────


def test_list_requires_token() -> None:
    resp = client.get("/v1/wardrobe")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_add_requires_token() -> None:
    resp = client.post("/v1/wardrobe", json={"title": "White tee"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_delete_requires_token() -> None:
    resp = client.delete(f"/v1/wardrobe/{uuid.uuid4()}")
    assert resp.status_code == 401


# ── header / body validation (no idempotency key needed — §9 scope) ──────────


def test_add_does_not_require_idempotency_key() -> None:
    # Unlike POST /v1/tryon, adding an item spends no credits and creates no job,
    # so no idempotency key is required (§9): a valid request gets past auth +
    # validation into the DB layer (500 here only because the test harness starts
    # no pool), never a 400/401/422 header or validation gate.
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.post("/v1/wardrobe", json={"title": "White tee"}, headers=_auth())
    assert resp.status_code not in (400, 401, 422)


def test_add_rejects_negative_cost() -> None:
    resp = client.post("/v1/wardrobe", json={"cost": -5}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_delete_rejects_non_uuid() -> None:
    resp = client.delete("/v1/wardrobe/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


# ── pure model ───────────────────────────────────────────────────────────────


def test_create_model_defaults_empty_tags() -> None:
    item = WardrobeItemCreate(title="White tee")
    assert item.tags == []
    assert item.image_url is None
    assert item.category is None


# ── live schema validation (skips without a DSN; prepare-only, never mutates) ─


def test_wardrobe_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    columns = (
        "id, title, category, subcategory, color, pattern, brand, "
        "image_url, cutout_url, thumbnail_url, tags, cost, purchase_date, "
        "last_worn_at, wear_count, cutout_status, created_at"
    )
    stmts = [
        f"select {columns} from public.wardrobe_items "
        "where user_id = $1::uuid order by created_at desc limit 500",
        "insert into public.wardrobe_items "
        "(user_id, title, category, subcategory, color, pattern, brand, "
        "image_url, cost, purchase_date, tags, cutout_status) "
        "values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) "
        f"returning {columns}",
        "delete from public.wardrobe_items "
        "where id = $1::uuid and user_id = $2::uuid returning id",
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
