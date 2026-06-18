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
        _GIVEAWAY_SELECT + " where g.id = $2::uuid",
        _GIVEAWAY_SELECT + " where g.status = 'available' and ($2::text is null or "
        "g.category = $2) and ($3::text is null or g.size = $3) and not exists "
        "(select 1 from public.blocks b where (b.blocker_id = $1::uuid and "
        "b.blocked_id = g.owner_id) or (b.blocker_id = g.owner_id and "
        "b.blocked_id = $1::uuid)) order by g.created_at desc limit $4",
        _GIVEAWAY_SELECT + " where g.owner_id = $1::uuid order by g.created_at desc",
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
