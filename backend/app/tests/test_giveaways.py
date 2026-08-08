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
        {
            "sub": "u1",
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
        asyncio.run(mod._moderate_listing("u", GiveawayCreate(title="Call me 0123456789")))
    assert exc.value.code == "MODERATION_BLOCKED"


# ── moderation visibility (0038 — admin hide/soft-delete) ────────────────────


def test_hidden_listing_cannot_be_claimed(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.giveaways as mod
    from app.core.errors import ApiError
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn(
        [
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {
                    "owner_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                    "status": "available",
                    "hidden_at": "2026-07-13T00:00:00Z",
                    "deleted_at": None,
                },
            ),
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
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {
                    "owner_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                    "status": "available",
                    "hidden_at": None,
                    "deleted_at": "2026-07-13T00:00:00Z",
                },
            ),
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
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {
                    "owner_id": _OWNER,
                    "status": "available",
                    "hidden_at": "2026-07-13T00:00:00Z",
                    "deleted_at": None,
                },
            ),
            (
                "fetchrow",
                "select claimer_id, status from public.giveaway_claims",
                {"claimer_id": _REQUESTER, "status": "requested"},
            ),
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


# ── the requester's own listings survive the accept (status → 'reserved') ────
# Browse filters to `available`, and /mine is owner-only. Accepting a requester
# therefore removed the listing from the only view that requester had, taking the
# accepted state and the pickup chat with it.


def test_requested_requires_token() -> None:
    assert client.get("/v1/giveaways/requested").status_code == 401


def test_requested_lists_claims_regardless_of_listing_status(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.routers.v1.giveaways as mod
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    conn = _Conn([])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    asyncio.run(mod.my_requested_giveaways(_user()))

    sql = next(s for m, s, _ in conn.calls if m == "fetch")
    # Joined on the caller's OWN claim, with no status filter — a 'reserved' or
    # 'claimed' listing must still come back.
    assert "join public.giveaway_claims mc" in sql
    assert "mc.claimer_id = $1::uuid" in sql
    assert "g.status = 'available'" not in sql
    assert "g.deleted_at is null" in sql


def test_requested_route_is_not_shadowed_by_the_detail_route() -> None:
    """`/giveaways/{id}` would swallow `/giveaways/requested` if declared first."""
    paths = [r.path for r in app.routes if getattr(r, "path", "").startswith("/v1/giveaways")]
    assert paths.index("/v1/giveaways/requested") < paths.index("/v1/giveaways/{giveaway_id}")


# ── one conversation, visible to BOTH participants ───────────────────────────


def test_giveaway_row_exposes_the_callers_chat(monkeypatch: pytest.MonkeyPatch) -> None:
    """The listing payload carries the caller's chat id for the owner AND the
    accepted requester, so each side renders the same conversation affordance and
    rebuilds it from the database after a restart."""
    import app.routers.v1.giveaways as mod
    from app.tests.test_giveaway_chat import _Conn

    async def _resolve(conn, kind, owner_id, role, urls):
        return []

    monkeypatch.setattr(mod, "resolve_image_list", _resolve)

    chat_id = uuid.uuid4()
    row = {
        "id": uuid.uuid4(),
        "owner_id": uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        "owner_name": "Ana",
        "wardrobe_item_id": None,
        "title": "Coat",
        "description": None,
        "images": [],
        "size": None,
        "category": None,
        "condition": None,
        "area_label": None,
        "status": "reserved",
        "created_at": __import__("datetime").datetime.now(),
        "my_claim_status": "accepted",
        "my_claim_id": uuid.uuid4(),
        "my_chat_id": chat_id,
        "my_chat_status": "active",
        "claim_count": 3,
    }
    out = asyncio.run(
        mod._giveaway_from_row(_Conn([]), row, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    )

    assert out.chat_id == str(chat_id)
    assert out.chat_status == "active"
    assert out.my_claim_status == "accepted"
    assert out.is_mine is False  # the requester, not the owner


def test_giveaway_select_resolves_the_chat_for_either_participant() -> None:
    from app.routers.v1.giveaways import _GIVEAWAY_SELECT

    assert "pc.owner_id = $1::uuid or pc.requester_id = $1::uuid" in _GIVEAWAY_SELECT
    # Prefer the live chat over an older ended one.
    assert "order by (pc.status = 'active') desc" in _GIVEAWAY_SELECT


def test_accept_locks_the_listing_row_before_deciding(monkeypatch: pytest.MonkeyPatch) -> None:
    """Two concurrent accepts of DIFFERENT requesters must not both win — the
    listing row is locked FOR UPDATE and the state re-read under that lock."""
    import app.routers.v1.giveaways as mod
    from app.models.giveaway import ClaimDecision
    from app.tests.test_giveaway_chat import _Conn, _Pool, _user

    owner = "11111111-1111-1111-1111-111111111111"  # == _user()
    claimer = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    chat_id = uuid.uuid4()

    conn = _Conn(
        [
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {
                    "owner_id": owner,
                    "status": "available",
                    "hidden_at": None,
                    "deleted_at": None,
                },
            ),
            (
                "fetchrow",
                "select status, hidden_at from public.giveaways where id = $1::uuid for update",
                {"status": "available", "hidden_at": None},
            ),
            (
                "fetchrow",
                "select claimer_id, status from public.giveaway_claims",
                {"claimer_id": claimer, "status": "requested"},
            ),
            ("fetchval", "select status from public.giveaway_claims where id", "requested"),
            ("fetchval", "insert into public.giveaway_pickup_chats", chat_id),
            (
                "fetchrow",
                "select c.id, c.giveaway_id, c.claimer_id",
                {
                    "id": uuid.uuid4(),
                    "giveaway_id": uuid.uuid4(),
                    "claimer_id": claimer,
                    "claimer_name": "Bo",
                    "message": None,
                    "status": "accepted",
                    "created_at": __import__("datetime").datetime.now(),
                },
            ),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    notified: list[dict] = []

    async def _notify(_conn, **kwargs):
        notified.append(kwargs)
        return None

    async def _actor(*a, **k):
        return "Ana"

    monkeypatch.setattr(mod, "create_notification", _notify)
    monkeypatch.setattr(mod, "actor_name", _actor)

    giveaway_id_holder = [uuid.uuid4()]
    asyncio.run(
        mod.decide_claim(
            giveaway_id_holder[0], uuid.uuid4(), ClaimDecision(status="accepted"), _user()
        )
    )

    assert any("for update" in s for _, s, _ in conn.calls)
    # Exactly one accepted system message, inserted with ON CONFLICT DO NOTHING.
    system = [s for _, s, _ in conn.calls if "kind, body" in s]
    assert len(system) == 1
    assert "on conflict (chat_id, kind) where kind = 'system' do nothing" in system[0]

    # The requester's notification opens the CONVERSATION, not the listing.
    accepted = next(n for n in notified if n["type"] == "giveaway_accepted")
    assert accepted["target_type"] == "giveaway_chat"
    assert accepted["target_id"] == str(giveaway_id_holder[0])
    assert accepted["data"]["chat_id"] == str(chat_id)
    assert accepted["data"]["giveaway_id"] == str(giveaway_id_holder[0])
    assert accepted["data"]["claim_id"]
    assert accepted["dedupe_key"].startswith("giveaway_accepted:")
    from app.services.notifications import route_for

    assert (
        route_for(accepted["type"], accepted["target_type"], accepted["target_id"])
        == f"/wtm/giveaway-chat?id={giveaway_id_holder[0]}"
    )


def test_repeat_accept_reuses_the_same_chat(monkeypatch: pytest.MonkeyPatch) -> None:
    """A retried accept must resolve to the EXISTING conversation, not a new one,
    and must not stack a second system message."""
    import app.routers.v1.giveaways as mod
    from app.tests.test_giveaway_chat import _Conn

    existing = uuid.uuid4()
    conn = _Conn(
        [
            # insert ... on conflict do nothing -> no row returned
            ("fetchval", "insert into public.giveaway_pickup_chats", None),
            ("fetchval", "select id from public.giveaway_pickup_chats", existing),
        ]
    )
    got = asyncio.run(mod._open_pickup_chat(conn, str(uuid.uuid4()), str(uuid.uuid4()), "o", "r"))

    assert got == str(existing)
    assert any("set status = 'active'" in s for _, s, _ in conn.calls)  # re-armed
    system = [s for _, s, _ in conn.calls if "kind, body" in s]
    assert len(system) == 1
    assert "do nothing" in system[0]


def test_system_message_belongs_to_neither_participant(monkeypatch: pytest.MonkeyPatch) -> None:
    import datetime

    import app.routers.v1.giveaways as mod
    from app.tests.test_giveaway_chat import _chat_row, _Conn, _Pool, _user

    chat_id = uuid.uuid4()
    conn = _Conn(
        [
            ("fetchrow", "from public.giveaway_pickup_chats c", _chat_row()),
            (
                "fetch",
                "from public.giveaway_chat_messages",
                [
                    {
                        "id": uuid.uuid4(),
                        "chat_id": chat_id,
                        "sender_id": None,
                        "kind": "system",
                        "body": "Request accepted",
                        "body_deleted": False,
                        "created_at": datetime.datetime.now(),
                    }
                ],
            ),
        ]
    )
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    out = asyncio.run(mod.list_chat_messages(chat_id, _user()))
    assert len(out) == 1
    assert out[0].kind == "system"
    assert out[0].sender_id is None
    assert out[0].is_mine is False


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
