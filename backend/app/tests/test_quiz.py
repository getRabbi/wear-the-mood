"""Style Quiz — auth gates, result computation, validation, live SQL schema."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.quiz import QuizSubmit
from app.services.style_quiz import compute_style_result

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
    return jwt.encode(
        {"sub": "u1", "aud": "authenticated", "role": "authenticated",
         "iat": now, "exp": now + 3600},
        TEST_SECRET,
        algorithm="HS256",
    )


def _auth(extra: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {_token()}"}
    if extra:
        headers.update(extra)
    return headers


# ── auth + header gates ──────────────────────────────────────────────────────


def test_active_quiz_requires_token() -> None:
    assert client.get("/v1/quiz/active").status_code == 401


def test_latest_result_requires_token() -> None:
    assert client.get("/v1/quiz/result/latest").status_code == 401


def test_submit_requires_token() -> None:
    resp = client.post(f"/v1/quiz/{uuid.uuid4()}/submit", json={"answers": {"q": "minimal"}})
    assert resp.status_code == 401


def test_submit_requires_idempotency_key() -> None:
    resp = client.post(
        f"/v1/quiz/{uuid.uuid4()}/submit",
        json={"answers": {"q": "minimal"}},
        headers=_auth(),
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_submit_rejects_empty_answers() -> None:
    resp = client.post(
        f"/v1/quiz/{uuid.uuid4()}/submit",
        json={"answers": {}},
        headers=_auth({"Idempotency-Key": str(uuid.uuid4())}),
    )
    assert resp.status_code == 422


def test_submit_model_requires_answers() -> None:
    with pytest.raises(ValueError):
        QuizSubmit(answers={})
    assert QuizSubmit(answers={"q1": "minimal"}).answers == {"q1": "minimal"}


# ── result computation ───────────────────────────────────────────────────────


def test_style_result_ranks_traits_by_frequency() -> None:
    r = compute_style_result(["minimal", "minimal", "earthy", "classic", "minimal"])
    assert r.keywords == ["minimal", "earthy", "classic"]  # 3, then ties by order
    assert r.title == "Minimal · Earthy · Classic"
    assert len(r.palette) == 3
    assert r.description.startswith("Your Style DNA blends")


def test_style_result_caps_at_three_and_ignores_unknown() -> None:
    r = compute_style_result(["bold", "street", "romantic", "classic", "??", ""])
    assert len(r.keywords) == 3
    assert "??" not in r.keywords


def test_style_result_safe_default_when_no_known_traits() -> None:
    r = compute_style_result(["", "nonsense"])
    assert r.keywords == ["classic"]


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_quiz_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "select id, slug, title, description from public.quizzes "
        "where is_active order by created_at limit 1",
        "select id, prompt, options from public.quiz_questions "
        "where quiz_id = $1::uuid order by order_index",
        "select 1 from public.quizzes where id = $1::uuid and is_active",
        "insert into public.quiz_responses (user_id, quiz_id, answers, result) "
        "values ($1::uuid, $2::uuid, $3::jsonb, $4::jsonb) returning id, created_at",
        "insert into public.taste_signals (user_id, signal_type, subject_type, subject_id) "
        "values ($1::uuid, 'quiz', 'quiz', $2::uuid)",
        "select id, result, created_at from public.quiz_responses "
        "where user_id = $1::uuid order by created_at desc limit 1",
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
