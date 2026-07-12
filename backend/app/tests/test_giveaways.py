"""Giveaways — auth gates, validation, moderation, live SQL schema."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.giveaway import ClaimDecision, GiveawayCreate, GiveawayStatusUpdate

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


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


# ── auth gates ───────────────────────────────────────────────────────────────


def test_create_requires_token() -> None:
    resp = client.post("/v1/giveaways", json={"title": "Coat"})
    assert resp.status_code == 401


def test_browse_requires_token() -> None:
    assert client.get("/v1/giveaways").status_code == 401


def test_claim_requires_token() -> None:
    resp = client.post(f"/v1/giveaways/{uuid.uuid4()}/claim", json={})
    assert resp.status_code == 401


def test_mine_requires_token() -> None:
    assert client.get("/v1/giveaways/mine").status_code == 401


def test_create_requires_title() -> None:
    resp = client.post("/v1/giveaways", json={"description": "no title"}, headers=_auth())
    assert resp.status_code == 422


# ── model validation ─────────────────────────────────────────────────────────


def test_giveaway_caps_images_at_six() -> None:
    g = GiveawayCreate(title="Tee", images=[f"https://x/{i}.jpg" for i in range(10)])
    assert len(g.images) == 6


def test_giveaway_drops_blank_images() -> None:
    g = GiveawayCreate(title="Tee", images=["https://x/1.jpg", "  ", ""])
    assert g.images == ["https://x/1.jpg"]


def test_claim_decision_is_constrained() -> None:
    assert ClaimDecision(status="accepted").status == "accepted"
    with pytest.raises(ValueError):
        ClaimDecision(status="maybe")
    with pytest.raises(ValueError):
        GiveawayStatusUpdate(status="gone")


# ── moderation (§19) ─────────────────────────────────────────────────────────


def test_listing_moderation_blocks_flagged_image(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult

    class _Block:
        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="nudity")

        async def check_text(self, text: str) -> ModerationResult:
            return ModerationResult(allowed=True)

    monkeypatch.setattr(mod, "get_moderator", lambda: _Block())
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod._moderate_listing("u", GiveawayCreate(title="Coat", images=["https://x/p.jpg"]))
        )
    assert exc.value.code == "MODERATION_BLOCKED"


def test_listing_moderation_blocks_flagged_text(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult

    class _Block:
        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=True)

        async def check_text(self, text: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="contact")

    monkeypatch.setattr(mod, "get_moderator", lambda: _Block())
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod._moderate_listing("u", GiveawayCreate(title="Call me 0123456789"))
        )
    assert exc.value.code == "MODERATION_BLOCKED"


# ── moderation visibility (0038 — admin hide/soft-delete) ────────────────────


def test_hidden_listing_cannot_be_claimed(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn(
        [
            ("fetchrow", "select owner_id, status, hidden_at, deleted_at from public.giveaways",
             {"owner_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "status": "available",
              "hidden_at": "2026-07-13T00:00:00Z", "deleted_at": None}),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    from app.models.giveaway import ClaimCreate

    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.claim_giveaway(uuid.uuid4(), ClaimCreate(), _user()))
    assert exc.value.code == "VALIDATION_ERROR"


def test_deleted_listing_claim_is_not_found(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn(
        [
            ("fetchrow", "select owner_id, status, hidden_at, deleted_at from public.giveaways",
             {"owner_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "status": "available",
              "hidden_at": None, "deleted_at": "2026-07-13T00:00:00Z"}),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    from app.models.giveaway import ClaimCreate

    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.claim_giveaway(uuid.uuid4(), ClaimCreate(), _user()))
    assert exc.value.code == "NOT_FOUND"


def test_accept_blocked_on_hidden_listing(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.tests.test_giveaway_chat import _OWNER, _REQUESTER, _Conn, _Pool, _user

    conn = _Conn(
        [
            ("fetchrow", "select owner_id, status, hidden_at, deleted_at from public.giveaways",
             {"owner_id": _OWNER, "status": "available",
              "hidden_at": "2026-07-13T00:00:00Z", "deleted_at": None}),
            ("fetchrow", "select claimer_id, status from public.giveaway_claims",
             {"claimer_id": _REQUESTER, "status": "requested"}),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.decide_claim(
                uuid.uuid4(), uuid.uuid4(), ClaimDecision(status="accepted"), _user(_OWNER)
            )
        )
    assert exc.value.code == "VALIDATION_ERROR"


def test_browse_and_detail_filter_moderated_rows(monkeypatch: pytest.MonkeyPatch) -> None:
    """The public read paths must carry the 0038 moderation filters."""
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn([])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    asyncio.run(mod.browse_giveaways(_user(), None, None, 30))
    browse_sql = next(s for m, s, _ in conn.calls if m == "fetch")
    assert "g.hidden_at is null and g.deleted_at is null" in browse_sql

    with pytest.raises(ApiError):  # empty pool → not found, but the SQL is what matters
        asyncio.run(mod.get_giveaway(uuid.uuid4(), _user()))
    detail_sql = next(s for m, s, _ in conn.calls if m == "fetchrow")
    assert "g.deleted_at is null" in detail_sql
    assert "(g.hidden_at is null or g.owner_id = $1::uuid)" in detail_sql

    conn.calls.clear()
    asyncio.run(mod.my_giveaways(_user()))
    mine_sql = next(s for m, s, _ in conn.calls if m == "fetch")
    assert "g.deleted_at is null" in mine_sql


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_giveaways_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.giveaways import _GIVEAWAY_SELECT

    stmts = [
        "select 1 from public.wardrobe_items where id = $1::uuid and user_id = $2::uuid",
        "insert into public.giveaways (owner_id, wardrobe_item_id, title, description, "
        "images, size, category, condition, area_label) values "
        "($1::uuid, $2, $3, $4, $5::jsonb, $6, $7, $8, $9) returning id",
        _GIVEAWAY_SELECT + " where g.id = $2::uuid and g.deleted_at is null "
        "and (g.hidden_at is null or g.owner_id = $1::uuid)",
        _GIVEAWAY_SELECT + " where g.status = 'available' "
        "and g.hidden_at is null and g.deleted_at is null "
        "and ($2::text is null or "
        "g.category = $2) and ($3::text is null or g.size = $3) and not exists "
        "(select 1 from public.blocks b where (b.blocker_id = $1::uuid and "
        "b.blocked_id = g.owner_id) or (b.blocker_id = g.owner_id and "
        "b.blocked_id = $1::uuid)) order by g.created_at desc limit $4",
        _GIVEAWAY_SELECT + " where g.owner_id = $1::uuid and g.deleted_at is null "
        "order by g.created_at desc",
        "insert into public.giveaway_claims (giveaway_id, claimer_id, message) "
        "values ($1::uuid, $2::uuid, $3) on conflict (giveaway_id, claimer_id) "
        "do nothing returning id",
        "select c.id, c.giveaway_id, c.claimer_id, pr.display_name as claimer_name, "
        "c.message, c.status, c.created_at from public.giveaway_claims c "
        "join public.profiles pr on pr.id = c.claimer_id "
        "where c.giveaway_id = $1::uuid and c.claimer_id = $2::uuid",
        "update public.giveaway_claims set status = $3 where id = $1::uuid and "
        "giveaway_id = $2::uuid returning claimer_id",
        "update public.giveaways set status = 'reserved', updated_at = now() where id = $1::uuid",
        "update public.giveaways set status = $3, updated_at = now() "
        "where id = $1::uuid and owner_id = $2::uuid returning id",
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
