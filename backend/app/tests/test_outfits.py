import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.outfit import OutfitCreate
from app.routers.v1.outfits import _dedupe

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
    resp = client.get("/v1/outfits")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_create_requires_token() -> None:
    resp = client.post("/v1/outfits", json={"item_ids": [str(uuid.uuid4())]})
    assert resp.status_code == 401


def test_delete_requires_token() -> None:
    resp = client.delete(f"/v1/outfits/{uuid.uuid4()}")
    assert resp.status_code == 401


# ── body / path validation ───────────────────────────────────────────────────


def test_create_rejects_empty_item_ids() -> None:
    resp = client.post("/v1/outfits", json={"item_ids": []}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_create_rejects_non_uuid_item() -> None:
    resp = client.post("/v1/outfits", json={"item_ids": ["nope"]}, headers=_auth())
    assert resp.status_code == 422


def test_delete_rejects_non_uuid() -> None:
    resp = client.delete("/v1/outfits/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


def test_update_requires_token() -> None:
    resp = client.put(
        f"/v1/outfits/{uuid.uuid4()}", json={"item_ids": [str(uuid.uuid4())]}
    )
    assert resp.status_code == 401


def test_update_rejects_empty_item_ids() -> None:
    resp = client.put(
        f"/v1/outfits/{uuid.uuid4()}", json={"item_ids": []}, headers=_auth()
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_update_rejects_non_uuid_path() -> None:
    resp = client.put(
        "/v1/outfits/not-a-uuid",
        json={"item_ids": [str(uuid.uuid4())]},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_update_valid_body_passes_gates() -> None:
    # A well-formed edit clears auth + validation and reaches the DB layer (500
    # only because the test harness has no pool) — never a 400/401/422 gate.
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.put(
        f"/v1/outfits/{uuid.uuid4()}",
        json={"name": "Updated", "item_ids": [str(uuid.uuid4())]},
        headers=_auth(),
    )
    assert resp.status_code not in (400, 401, 422)


def test_create_needs_no_idempotency_key() -> None:
    # No credits/jobs → no idempotency key (§9): a valid request gets past auth +
    # validation into the DB layer (500 only because the test harness has no
    # pool), never a 400/401/422 gate.
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.post("/v1/outfits", json={"item_ids": [str(uuid.uuid4())]}, headers=_auth())
    assert resp.status_code not in (400, 401, 422)


# ── pure model + helper ──────────────────────────────────────────────────────


def test_create_model_parses_item_ids() -> None:
    item_id = uuid.uuid4()
    outfit = OutfitCreate(name="Friday", item_ids=[item_id])
    assert outfit.item_ids == [item_id]
    assert outfit.cover_image_url is None


def test_dedupe_preserves_order_and_drops_repeats() -> None:
    a, b, c = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    assert _dedupe([a, b, a, c, b]) == [a, b, c]


# ── live schema validation (skips without a DSN; prepare-only, never mutates) ─


def test_outfits_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    columns = "id, name, item_ids, cover_image_url, created_at"
    stmts = [
        f"select {columns} from public.outfits "
        "where user_id = $1::uuid order by created_at desc limit 500",
        "select count(*) from public.wardrobe_items "
        "where user_id = $1::uuid and id = any($2::uuid[])",
        "insert into public.outfits (user_id, name, item_ids, cover_image_url) "
        f"values ($1::uuid, $2, $3::uuid[], $4) returning {columns}",
        "delete from public.outfits where id = $1::uuid and user_id = $2::uuid returning id",
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
