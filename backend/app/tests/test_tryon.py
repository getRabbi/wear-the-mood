import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.tryon import TryOnRequest
from app.services.tryon import get_tryon_provider

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


def _auth(extra: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {_token()}"}
    if extra:
        headers.update(extra)
    return headers


# ── auth + header gates (run before any DB access) ───────────────────────────


def test_tryon_requires_token() -> None:
    resp = client.post("/v1/tryon", json={"person_image_url": "x", "garment_image_url": "y"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_tryon_requires_idempotency_key() -> None:
    resp = client.post(
        "/v1/tryon",
        json={"person_image_url": "x", "garment_image_url": "y"},
        headers=_auth(),
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_tryon_rejects_bad_body() -> None:
    # Neither garment source supplied -> model validator fails before DB.
    resp = client.post(
        "/v1/tryon",
        json={"person_image_url": "x"},
        headers=_auth({"Idempotency-Key": str(uuid.uuid4())}),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_get_tryon_requires_token() -> None:
    resp = client.get(f"/v1/tryon/{uuid.uuid4()}")
    assert resp.status_code == 401


def test_get_tryon_rejects_non_uuid() -> None:
    resp = client.get("/v1/tryon/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


# ── pure model + provider ────────────────────────────────────────────────────


def test_request_requires_exactly_one_garment_source() -> None:
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p")  # neither
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_url="g", wardrobe_item_id=uuid.uuid4())
    # Each single source is valid.
    assert TryOnRequest(person_image_url="p", garment_image_url="g").garment_image_url == "g"
    assert TryOnRequest(person_image_url="p", wardrobe_item_id=uuid.uuid4()).wardrobe_item_id


def test_stub_provider_echoes_person_image() -> None:
    provider = get_tryon_provider()
    out = asyncio.run(provider.generate(person_image_url="person", garment_image_url="garment"))
    assert out == "person"


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_tryon_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "insert into public.tryon_jobs "
        "(user_id, status, person_image_url, garment_image_url, wardrobe_item_id, "
        "provider, idempotency_key) "
        "values ($1::uuid, 'queued', $2, $3, $4, $5, $6) returning id",
        "select id, status, error from public.tryon_jobs "
        "where id = $1::uuid and user_id = $2::uuid",
        "select result_image_url from public.tryon_results "
        "where job_id = $1::uuid and user_id = $2::uuid order by created_at desc limit 1",
        "select coalesce(cutout_url, image_url) from public.wardrobe_items "
        "where id = $1::uuid and user_id = $2::uuid",
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
