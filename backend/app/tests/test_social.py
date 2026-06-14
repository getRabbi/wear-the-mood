"""Social — auth gates, post validation, image moderation, live SQL schema."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.social import PostCreate

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
        {
            "sub": "user-123",
            "aud": "authenticated",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


# ── auth gates (run before any DB access) ────────────────────────────────────


def test_create_post_requires_token() -> None:
    resp = client.post("/v1/social/posts", json={"image_url": "x"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_feed_requires_token() -> None:
    assert client.get("/v1/social/feed").status_code == 401


def test_like_requires_token() -> None:
    assert client.post(f"/v1/social/posts/{uuid.uuid4()}/like").status_code == 401


def test_comment_requires_token() -> None:
    resp = client.post(f"/v1/social/posts/{uuid.uuid4()}/comments", json={"body": "hi"})
    assert resp.status_code == 401


def test_follow_requires_token() -> None:
    assert client.post(f"/v1/social/follow/{uuid.uuid4()}").status_code == 401


def test_leaderboard_requires_token() -> None:
    assert client.get("/v1/social/leaderboard").status_code == 401


def test_leaderboard_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/social/leaderboard", headers=_auth())
    assert resp.status_code not in (401, 422)


# ── request validation ───────────────────────────────────────────────────────


def test_post_requires_content() -> None:
    with pytest.raises(ValueError):
        PostCreate()  # neither image nor outfit
    assert PostCreate(image_url="x").image_url == "x"
    assert PostCreate(outfit_id=uuid.uuid4()).outfit_id is not None


def test_post_tags_are_cleaned_and_capped() -> None:
    p = PostCreate(
        image_url="x",
        tags=["#OOTD", " summer ", "summer", "", "  ", "Streetwear"],
    )
    # strips '#'/whitespace, drops blanks, de-dupes (case-sensitive).
    assert p.tags == ["OOTD", "summer", "Streetwear"]
    # capped at 10.
    assert len(PostCreate(image_url="x", tags=[f"t{i}" for i in range(20)]).tags) == 10


def test_empty_post_body_is_rejected() -> None:
    resp = client.post("/v1/social/posts", json={}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_comment_body_required() -> None:
    resp = client.post(
        f"/v1/social/posts/{uuid.uuid4()}/comments",
        json={"body": ""},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_follow_rejects_non_uuid_path() -> None:
    # A non-UUID followee id is rejected by FastAPI path validation (422).
    resp = client.post("/v1/social/follow/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


# ── post image moderation (§19) ──────────────────────────────────────────────


def test_moderate_post_image_blocks_flagged(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult

    class _Block:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="sexual")

    monkeypatch.setattr(social_mod, "get_moderator", lambda: _Block())
    with pytest.raises(ApiError) as exc:
        asyncio.run(social_mod._moderate_post_image("user", "https://x/p.jpg"))
    assert exc.value.code == "MODERATION_BLOCKED"
    assert exc.value.status_code == 422


def test_moderate_post_image_allows_clean(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod
    from app.services.moderation.base import ModerationResult

    class _Allow:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=True)

    monkeypatch.setattr(social_mod, "get_moderator", lambda: _Allow())
    asyncio.run(social_mod._moderate_post_image("user", "https://x/p.jpg"))  # no raise


def test_moderate_skips_when_no_image(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod

    def _boom():  # must not be called when there's no image
        raise AssertionError("moderator should not run without an image")

    monkeypatch.setattr(social_mod, "get_moderator", _boom)
    asyncio.run(social_mod._moderate_post_image("user", None))  # no call, no raise


# ── comment / caption text moderation (§19) ──────────────────────────────────


def test_moderate_text_blocks_flagged(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult

    class _Block:
        name = "x"

        async def check_text(self, text: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="hate")

    monkeypatch.setattr(social_mod, "get_moderator", lambda: _Block())
    with pytest.raises(ApiError) as exc:
        asyncio.run(social_mod._moderate_text("user", "bad words", kind="comment"))
    assert exc.value.code == "MODERATION_BLOCKED"
    assert exc.value.status_code == 422


def test_moderate_text_skips_when_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod

    def _boom():
        raise AssertionError("moderator should not run on empty text")

    monkeypatch.setattr(social_mod, "get_moderator", _boom)
    asyncio.run(social_mod._moderate_text("user", "   ", kind="caption"))  # no call
    asyncio.run(social_mod._moderate_text("user", None, kind="caption"))


# ── reports + blocks (§19) ────────────────────────────────────────────────────


def test_report_requires_token() -> None:
    resp = client.post(
        "/v1/social/reports",
        json={"subject_type": "post", "subject_id": str(uuid.uuid4())},
    )
    assert resp.status_code == 401


def test_report_rejects_bad_subject_type() -> None:
    resp = client.post(
        "/v1/social/reports",
        json={"subject_type": "banana", "subject_id": str(uuid.uuid4())},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_block_requires_token() -> None:
    assert client.post(f"/v1/social/block/{uuid.uuid4()}").status_code == 401


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_social_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.social import _COMMENT_SELECT, _FEED_SELECT

    stmts = [
        "select 1 from public.outfits where id = $1::uuid and user_id = $2::uuid",
        "insert into public.posts (user_id, caption, image_url, outfit_id) "
        "values ($1::uuid, $2, $3, $4) returning id",
        _FEED_SELECT + " where p.id = $2::uuid",
        _FEED_SELECT + " where p.visibility = 'public' and ($2::timestamptz is null or "
        "p.created_at < $2::timestamptz) and not exists (select 1 from public.blocks b "
        "where (b.blocker_id = $1::uuid and b.blocked_id = p.user_id) or "
        "(b.blocker_id = p.user_id and b.blocked_id = $1::uuid)) "
        "order by p.created_at desc limit $3",
        "delete from public.posts where id = $1::uuid and user_id = $2::uuid returning id",
        "insert into public.likes (user_id, post_id) values ($1::uuid, $2::uuid) "
        "on conflict do nothing returning post_id",
        "update public.posts set like_count = like_count + 1 where id = $1::uuid",
        "delete from public.likes where user_id = $1::uuid and post_id = $2::uuid "
        "returning post_id",
        "update public.posts set like_count = greatest(like_count - 1, 0) where id = $1::uuid",
        "insert into public.comments (post_id, user_id, body) "
        "values ($1::uuid, $2::uuid, $3) returning id",
        "update public.posts set comment_count = comment_count + 1 where id = $1::uuid",
        _COMMENT_SELECT + " where c.id = $1::uuid",
        _COMMENT_SELECT + " where c.post_id = $1::uuid and ($2::timestamptz is null or "
        "c.created_at < $2::timestamptz) order by c.created_at desc limit $3",
        "insert into public.follows (follower_id, followee_id) "
        "values ($1::uuid, $2::uuid) on conflict do nothing",
        "delete from public.follows where follower_id = $1::uuid and followee_id = $2::uuid",
        "insert into public.reports (reporter_id, subject_type, subject_id, reason) "
        "values ($1::uuid, $2, $3::uuid, $4)",
        "insert into public.blocks (blocker_id, blocked_id) "
        "values ($1::uuid, $2::uuid) on conflict do nothing",
        "delete from public.blocks where blocker_id = $1::uuid and blocked_id = $2::uuid",
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
