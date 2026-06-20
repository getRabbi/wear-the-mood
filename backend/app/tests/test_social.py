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
from app.models.social import PostCreate, PostUpdate

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
    # Send the key so this exercises BODY validation, not the missing-key gate.
    resp = client.post(
        "/v1/social/posts",
        json={},
        headers={**_auth(), "Idempotency-Key": str(uuid.uuid4())},
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_create_post_requires_idempotency_key() -> None:
    # Post-creation spends work (§9), so it now requires an Idempotency-Key.
    resp = client.post("/v1/social/posts", json={"image_url": "x"}, headers=_auth())
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_post_accepts_an_attached_poll() -> None:
    from app.models.poll import PollCreate

    p = PostCreate(
        image_url="x",
        poll=PollCreate(question="Which fit?", options=["A", "B", "C"]),
    )
    assert p.poll is not None
    assert [o for o in p.poll.options] == ["A", "B", "C"]
    # a poll counts as content (Issue 1): a poll-only post — no image, no
    # outfit — is allowed, so it can be shared.
    poll_only = PostCreate(poll=PollCreate(question="Q", options=["A", "B"]))
    assert poll_only.poll is not None
    assert poll_only.image_url is None and poll_only.outfit_id is None
    # but a totally empty post (no image, outfit, OR poll) is still rejected.
    with pytest.raises(ValueError):
        PostCreate()


# ── post edit (FEATURES_COMMUNITY_PLUS · Post Edit) ──────────────────────────


def test_edit_post_requires_token() -> None:
    resp = client.patch(f"/v1/social/posts/{uuid.uuid4()}", json={"image_url": "x"})
    assert resp.status_code == 401


def test_post_update_requires_content() -> None:
    with pytest.raises(ValueError):
        PostUpdate()  # neither image nor outfit — same rule as create
    assert PostUpdate(image_url="x").image_url == "x"
    # tags are cleaned + capped exactly like create
    assert PostUpdate(image_url="x", tags=["#OOTD", "OOTD", ""]).tags == ["OOTD"]


def test_edit_empty_post_body_is_rejected() -> None:
    # Validation runs before any DB/moderation, so this is deterministic.
    resp = client.patch(
        f"/v1/social/posts/{uuid.uuid4()}", json={}, headers=_auth()
    )
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


# ── durable-image fetch before moderation (Issue 6/7b) ───────────────────────


def test_fetch_for_moderation_returns_data_uri(monkeypatch: pytest.MonkeyPatch) -> None:
    import base64

    import app.routers.v1.social as social_mod

    async def _fake_download(url: str) -> bytes:
        return b"\xff\xd8\xff-jpeg"

    monkeypatch.setattr(social_mod, "download_image", _fake_download)
    out = asyncio.run(social_mod._fetch_for_moderation("https://x/post.jpg"))
    assert out.startswith("data:image/jpeg;base64,")
    assert base64.b64decode(out.split(",", 1)[1]) == b"\xff\xd8\xff-jpeg"


def test_fetch_for_moderation_none_passes_through() -> None:
    import app.routers.v1.social as social_mod

    assert asyncio.run(social_mod._fetch_for_moderation(None)) is None


def test_fetch_for_moderation_retries_then_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.social as social_mod
    from app.core.errors import ApiError

    calls = {"n": 0}

    async def _always_fail(url: str) -> bytes:
        calls["n"] += 1
        raise RuntimeError("404 not served yet")

    monkeypatch.setattr(social_mod, "download_image", _always_fail)
    monkeypatch.setattr(social_mod, "_MOD_FETCH_DELAY", 0)  # keep the test instant
    with pytest.raises(ApiError) as exc:
        asyncio.run(social_mod._fetch_for_moderation("https://x/fresh.jpg"))
    assert exc.value.code == "PROVIDER_ERROR"
    assert exc.value.status_code == 503
    assert calls["n"] == social_mod._MOD_FETCH_ATTEMPTS  # retried, then gave up


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


# ── public creator profiles (CLAUDE.md §1 pillar 4) ──────────────────────────


def test_public_profile_requires_token() -> None:
    assert client.get(f"/v1/social/users/{uuid.uuid4()}").status_code == 401


def test_user_posts_requires_token() -> None:
    assert client.get(f"/v1/social/users/{uuid.uuid4()}/posts").status_code == 401


def test_followers_requires_token() -> None:
    assert client.get(f"/v1/social/users/{uuid.uuid4()}/followers").status_code == 401


def test_following_requires_token() -> None:
    assert client.get(f"/v1/social/users/{uuid.uuid4()}/following").status_code == 401


def test_user_closet_requires_token() -> None:
    assert client.get(f"/v1/social/users/{uuid.uuid4()}/closet").status_code == 401


def test_public_profile_rejects_non_uuid_path() -> None:
    # A non-UUID user id is rejected by FastAPI path validation (422), not 404.
    assert client.get("/v1/social/users/not-a-uuid", headers=_auth()).status_code == 422


def test_public_profile_authed_reaches_db_layer() -> None:
    # Authed request passes auth + path validation and reaches the DB layer
    # (tolerates a DB error in CI without a DSN, like the leaderboard test).
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get(f"/v1/social/users/{uuid.uuid4()}", headers=_auth())
    assert resp.status_code not in (401, 422)


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_social_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.social import (
        _COMMENT_SELECT,
        _FEED_SELECT,
        _FOLLOW_LIST_SELECT,
    )

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
        # post edit (migration 0015: posts.is_edited / edited_at)
        "update public.posts set caption = $3, image_url = $4, outfit_id = $5, "
        "tags = $6::text[], is_edited = true, edited_at = now() "
        "where id = $1::uuid and user_id = $2::uuid returning id",
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
        # public creator profiles (migration 0012: profiles.bio/style_tags/is_public)
        "select is_public from public.profiles where id = $1::uuid",
        "select 1 from public.blocks b where (b.blocker_id = $1::uuid and "
        "b.blocked_id = $2::uuid) or (b.blocker_id = $2::uuid and b.blocked_id = $1::uuid)",
        "select pr.id, pr.display_name, pr.username, pr.bio, pr.style_tags, "
        "(select count(*) from public.follows f where f.followee_id = pr.id) as follower_count, "
        "(select count(*) from public.follows f where f.follower_id = pr.id) as following_count, "
        "(select count(*) from public.posts p where p.user_id = pr.id and "
        "p.visibility = 'public') as post_count, "
        "exists(select 1 from public.follows f where f.follower_id = $1::uuid and "
        "f.followee_id = pr.id) as is_following "
        "from public.profiles pr where pr.id = $2::uuid",
        _FEED_SELECT + " where p.user_id = $2::uuid and p.visibility = 'public' and "
        "($3::timestamptz is null or p.created_at < $3::timestamptz) "
        "order by p.created_at desc limit $4",
        _FOLLOW_LIST_SELECT.format(join_col="f.follower_id", filter_col="followee_id"),
        _FOLLOW_LIST_SELECT.format(join_col="f.followee_id", filter_col="follower_id"),
        # public closet (migration 0013: profiles.show_public_closet)
        "select show_public_closet from public.profiles where id = $1::uuid",
        "select id, title, category, color, image_url, cutout_url, thumbnail_url "
        "from public.wardrobe_items where user_id = $1::uuid "
        "order by created_at desc limit $2",
        # notification hooks (post owner lookup)
        "select user_id from public.posts where id = $1::uuid",
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
