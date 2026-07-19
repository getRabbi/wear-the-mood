"""Secret pickup chat (0037) — auth gates, validation, moderation, and the
authorization/retention proofs:

  1. a non-participant can never read someone else's approved chat;
  2. a non-owner can never see a listing's full request list;
  3. a non-participant can never send into a chat;
  4. an expired/locked chat rejects new messages;
  5. cleanup never redacts a REPORTED chat and is idempotent.

Endpoint logic runs against a scripted fake pool (no network); the live-DSN
test prepares every new SQL statement against the real schema.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi.testclient import TestClient

import app.cron.giveaway_chats as cron
import app.routers.v1.giveaways as mod
from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser
from app.main import app
from app.models.giveaway import ChatMessageCreate, ClaimDecision, PickupPlanUpdate

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


# ── scripted fake pool ───────────────────────────────────────────────────────
# Handlers: (method, sql-substring) → value or callable(sql, args). First match
# wins; unmatched calls return None/"UPDATE 0" so best-effort side paths
# (notifications) never explode a test.


class _Tx:
    async def __aenter__(self) -> _Tx:
        return self

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Conn:
    def __init__(self, handlers: list[tuple[str, str, object]]) -> None:
        self.handlers = handlers
        self.calls: list[tuple[str, str, tuple]] = []

    def transaction(self) -> _Tx:
        return _Tx()

    def _dispatch(self, method: str, sql: str, args: tuple) -> object:
        self.calls.append((method, " ".join(sql.split()), args))
        for m, frag, value in self.handlers:
            if m == method and frag in " ".join(sql.split()):
                return value(sql, args) if callable(value) else value
        return "UPDATE 0" if method == "execute" else None

    async def fetchrow(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchrow", sql, args)

    async def fetchval(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchval", sql, args)

    async def fetch(self, sql: str, *args: object) -> object:
        return self._dispatch("fetch", sql, args) or []

    async def execute(self, sql: str, *args: object) -> object:
        return self._dispatch("execute", sql, args)


class _AcquireCtx:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _Conn:
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self) -> _AcquireCtx:
        return _AcquireCtx(self.conn)


def _wire(monkeypatch: pytest.MonkeyPatch, conn: _Conn) -> None:
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))


def _user(uid: str = "11111111-1111-1111-1111-111111111111") -> CurrentUser:
    return CurrentUser(uid, None, {})


_OWNER = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
_REQUESTER = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
_STRANGER = "cccccccc-cccc-cccc-cccc-cccccccccccc"


def _chat_row(status: str = "active") -> dict:
    now = datetime.now(UTC)
    return {
        "id": uuid.uuid4(),
        "giveaway_id": uuid.uuid4(),
        "giveaway_title": "Wool coat",
        "claim_id": uuid.uuid4(),
        "owner_id": _OWNER,
        "requester_id": _REQUESTER,
        "status": status,
        "report_flag": False,
        "pickup_plan": "{}",
        "approved_at": now,
        "expires_at": now + timedelta(days=7),
        "locked_at": None,
        "completed_at": None,
        "created_at": now,
        "owner_display": "Ada",
        "owner_username": "ada",
        "requester_display": "Lin",
        "requester_username": "lin",
    }


class _AllowModerator:
    async def check_text(self, text: str):
        from app.services.moderation.base import ModerationResult

        return ModerationResult(allowed=True)


# ── auth gates ───────────────────────────────────────────────────────────────


def test_chat_endpoints_require_token() -> None:
    gid, cid = uuid.uuid4(), uuid.uuid4()
    assert client.get(f"/v1/giveaways/{gid}/chat").status_code == 401
    assert client.get(f"/v1/giveaways/chats/{cid}/messages").status_code == 401
    assert (
        client.post(f"/v1/giveaways/chats/{cid}/messages", json={"body": "hi"}).status_code == 401
    )
    assert client.post(f"/v1/giveaways/chats/{cid}/plan", json={}).status_code == 401
    assert client.post(f"/v1/giveaways/chats/{cid}/report", json={}).status_code == 401
    assert client.delete(f"/v1/giveaways/{gid}/claim").status_code == 401


# ── model validation (text-only, ≤500 chars) ─────────────────────────────────


def test_message_body_is_bounded() -> None:
    assert ChatMessageCreate(body="  hello  ").body == "hello"
    assert len(ChatMessageCreate(body="x" * 500).body) == 500
    with pytest.raises(ValueError):
        ChatMessageCreate(body="x" * 501)
    with pytest.raises(ValueError):
        ChatMessageCreate(body="   ")


def test_plan_fields_are_capped() -> None:
    plan = PickupPlanUpdate(area="Dhanmondi", landmark="Rabindra Sarobar gate")
    assert plan.confirmed is False
    with pytest.raises(ValueError):
        PickupPlanUpdate(area="x" * 121)
    with pytest.raises(ValueError):
        PickupPlanUpdate(landmark="x" * 161)


# ── moderation (§19) ─────────────────────────────────────────────────────────


def test_send_blocked_by_moderation(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services.moderation.base import ModerationResult

    class _Block:
        async def check_text(self, text: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="contact")

    monkeypatch.setattr(mod, "get_moderator", lambda: _Block())
    _wire(monkeypatch, _Conn([]))  # must never reach the DB
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.send_chat_message(
                uuid.uuid4(), ChatMessageCreate(body="call 0123456789"), _user(_OWNER)
            )
        )
    assert exc.value.code == "MODERATION_BLOCKED"


# ── proof 1+3: non-participants get 404 (read AND send) ──────────────────────


def test_non_participant_cannot_read_chat(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([])  # participant-scoped lookup finds nothing for a stranger
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.get_pickup_chat(uuid.uuid4(), _user(_STRANGER)))
    assert exc.value.code == "NOT_FOUND"
    # The lookup itself is participant-scoped — the caller id is IN the SQL.
    lookup = next(c for c in conn.calls if "giveaway_pickup_chats" in c[1])
    assert "owner_id = $2::uuid or requester_id = $2::uuid" in lookup[1]


def test_non_participant_cannot_read_messages(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([])
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.list_chat_messages(uuid.uuid4(), _user(_STRANGER)))
    assert exc.value.code == "NOT_FOUND"
    assert not any("from public.giveaway_chat_messages" in c[1] for c in conn.calls)


def test_non_participant_cannot_send(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mod, "get_moderator", lambda: _AllowModerator())
    conn = _Conn([])  # stranger: the participant-scoped chat fetch returns None
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.send_chat_message(uuid.uuid4(), ChatMessageCreate(body="hi"), _user(_STRANGER))
        )
    assert exc.value.code == "NOT_FOUND"
    assert not any("insert into public.giveaway_chat_messages" in c[1] for c in conn.calls)


# ── proof 2: request list is owner-only ──────────────────────────────────────


def test_non_owner_cannot_list_requests(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn([("fetchval", "select owner_id from public.giveaways", _OWNER)])
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(mod.list_claims(uuid.uuid4(), _user(_STRANGER)))
    assert exc.value.code == "NOT_FOUND"
    assert not any("from public.giveaway_claims" in c[1] for c in conn.calls)


# ── proof 4: an expired/locked chat rejects sends ────────────────────────────


def test_expired_chat_rejects_send(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mod, "get_moderator", lambda: _AllowModerator())
    conn = _Conn(
        [
            # The guarded insert matches no active-window row → None…
            ("fetchrow", "insert into public.giveaway_chat_messages", None),
            # …while the participant gate still resolves the (expired) chat.
            ("fetchrow", "join public.giveaways g on g.id = c.giveaway_id", _chat_row("expired")),
        ]
    )
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.send_chat_message(uuid.uuid4(), ChatMessageCreate(body="hi"), _user(_OWNER))
        )
    assert exc.value.code == "VALIDATION_ERROR"
    insert = next(c for c in conn.calls if "insert into public.giveaway_chat_messages" in c[1])
    # The active window is enforced INSIDE the insert — no check-then-act race.
    assert "c.status = 'active' and now() < c.expires_at" in insert[1]


def test_locked_chat_rejects_plan_update(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mod, "get_moderator", lambda: _AllowModerator())
    conn = _Conn(
        [
            ("fetchrow", "join public.giveaways g on g.id = c.giveaway_id", _chat_row("completed")),
            ("fetchval", "set pickup_plan", None),  # guarded update matches nothing
        ]
    )
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.update_pickup_plan(uuid.uuid4(), PickupPlanUpdate(area="Banani"), _user(_REQUESTER))
        )
    assert exc.value.code == "VALIDATION_ERROR"


# ── accept: one winner, everyone else not_selected, chat opens ───────────────


def test_accept_opens_chat_and_settles_the_rest(monkeypatch: pytest.MonkeyPatch) -> None:
    gid, cid = uuid.uuid4(), uuid.uuid4()
    conn = _Conn(
        [
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {"owner_id": _OWNER, "status": "available", "hidden_at": None, "deleted_at": None},
            ),
            (
                "fetchrow",
                "select claimer_id, status from public.giveaway_claims",
                {"claimer_id": _REQUESTER, "status": "requested"},
            ),
            ("fetchval", "status = 'active'", None),  # no live chat yet
            ("fetchval", "insert into public.giveaway_pickup_chats", uuid.uuid4()),
            (
                "fetchrow",
                "join public.profiles pr on pr.id = c.claimer_id",
                {
                    "id": cid,
                    "giveaway_id": gid,
                    "claimer_id": _REQUESTER,
                    "claimer_name": "Lin",
                    "message": None,
                    "status": "accepted",
                    "created_at": datetime.now(UTC),
                },
            ),
        ]
    )
    _wire(monkeypatch, conn)
    out = asyncio.run(mod.decide_claim(gid, cid, ClaimDecision(status="accepted"), _user(_OWNER)))
    assert out.status == "accepted"
    joined = [c[1] for c in conn.calls]
    assert any(
        "set status = 'not_selected'" in s and "status = 'requested'" in s for s in joined
    ), "other pending requests must become not_selected"
    assert any(
        "insert into public.giveaway_pickup_chats" in s and "interval '7 days'" in s for s in joined
    ), "chat must open for 7 days"
    assert any("set status = 'reserved'" in s for s in joined)


def test_accept_rejected_when_listing_not_open(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn(
        [
            (
                "fetchrow",
                "select owner_id, status, hidden_at, deleted_at from public.giveaways",
                {"owner_id": _OWNER, "status": "claimed", "hidden_at": None, "deleted_at": None},
            ),
            (
                "fetchrow",
                "select claimer_id, status from public.giveaway_claims",
                {"claimer_id": _REQUESTER, "status": "requested"},
            ),
        ]
    )
    _wire(monkeypatch, conn)
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            mod.decide_claim(
                uuid.uuid4(), uuid.uuid4(), ClaimDecision(status="accepted"), _user(_OWNER)
            )
        )
    assert exc.value.code == "VALIDATION_ERROR"


# ── proof 5 + retention: cleanup behavior ────────────────────────────────────


def test_redaction_skips_reported_chats_and_is_idempotent() -> None:
    seen: list[str] = []

    def _count(sql: str, args: tuple) -> str:
        seen.append(" ".join(sql.split()))
        return "UPDATE 3" if len(seen) == 1 else "UPDATE 0"

    conn = _Conn([("execute", "giveaway_chat_messages", _count)])
    assert asyncio.run(cron.redact_ended_chats(conn)) == 3
    assert asyncio.run(cron.redact_ended_chats(conn)) == 0  # idempotent re-run
    # Reported chats are frozen; already-redacted rows are never touched again.
    assert "c.report_flag = false" in seen[0]
    assert "m.body_deleted = false" in seen[0]
    assert "'expired','completed','cancelled','locked'" in seen[0]


def test_expire_chats_settles_claim_and_listing() -> None:
    conn = _Conn([("fetch", "set status = 'expired'", [{"id": uuid.uuid4()}])])
    assert asyncio.run(cron.expire_chats(conn)) == 1
    joined = [c[1] for c in conn.calls]
    assert any(
        "set status = 'expired'" in s
        and "pc.claim_id = cl.id" in s
        and "cl.status = 'accepted'" in s
        for s in joined
    )
    assert any("set status = 'available'" in s and "g.status = 'reserved'" in s for s in joined)


def test_expire_settles_lazily_expired_chats_too() -> None:
    """The API flips chats to `expired` at read time; the cron's settle step
    must key off that STATE, not just this run's own transitions."""
    conn = _Conn([])  # nothing newly due this run
    assert asyncio.run(cron.expire_chats(conn)) == 0
    joined = [c[1] for c in conn.calls]
    # The claim/listing settles still ran, driven by pc.status = 'expired'.
    assert any(
        "update public.giveaway_claims cl" in s and "pc.status = 'expired'" in s for s in joined
    )
    reopen = next(s for s in joined if "update public.giveaways g" in s)
    assert "pc.status = 'expired'" in reopen
    # …and never reopens a listing that already has a NEWER live chat.
    assert "live.status = 'active'" in reopen


def test_purge_targets_only_settled_requests() -> None:
    seen: list[str] = []

    def _count(sql: str, args: tuple) -> str:
        seen.append(" ".join(sql.split()))
        return "DELETE 2"

    conn = _Conn([("execute", "delete from public.giveaway_claims", _count)])
    assert asyncio.run(cron.purge_settled_claims(conn)) == 2
    assert "status in ('declined','not_selected')" in seen[0]
    assert "interval '72 hours'" in seen[0]


def test_expiring_nudge_fires_once_per_chat() -> None:
    gid = uuid.uuid4()
    conn = _Conn(
        [
            (
                "fetch",
                "set expiry_notified = true",
                [{"giveaway_id": gid, "owner_id": _OWNER, "requester_id": _REQUESTER}],
            )
        ]
    )
    assert asyncio.run(cron.notify_expiring(conn)) == 1
    scan = next(c[1] for c in conn.calls if "expiry_notified" in c[1])
    assert "expiry_notified = false" in scan  # the flag flip IS the once-guard
    notifs = [c for c in conn.calls if "insert into public.notifications" in c[1]]
    assert len(notifs) == 2  # both participants


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_giveaway_chat_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        mod._CHAT_SELECT + " where c.id = $1::uuid and (c.owner_id = $2::uuid "
        "or c.requester_id = $2::uuid)",
        "select id from public.giveaway_pickup_chats where giveaway_id = $1::uuid "
        "and (owner_id = $2::uuid or requester_id = $2::uuid) "
        "order by (status = 'active') desc, created_at desc limit 1",
        "insert into public.giveaway_pickup_chats (giveaway_id, claim_id, owner_id, "
        "requester_id, expires_at) values ($1::uuid, $2::uuid, $3::uuid, $4::uuid, "
        "now() + interval '7 days') on conflict (giveaway_id, requester_id) "
        "do nothing returning id",
        "update public.giveaway_pickup_chats set status = 'active', claim_id = $2::uuid, "
        "approved_at = now(), expires_at = now() + interval '7 days', locked_at = null, "
        "completed_at = null, cancelled_at = null, expiry_notified = false, "
        "updated_at = now() where giveaway_id = $1::uuid and requester_id = $3::uuid "
        "and status <> 'active'",
        "update public.giveaway_pickup_chats set status = $2, completed_at = now(), "
        "locked_at = coalesce(locked_at, now()), updated_at = now() "
        "where giveaway_id = $1::uuid and status = 'active' "
        "and ($3::uuid is null or requester_id = $3::uuid) returning requester_id",
        "update public.giveaway_pickup_chats set status = 'expired', "
        "locked_at = coalesce(locked_at, now()), updated_at = now() "
        "where id = $1::uuid and status = 'active' and now() >= expires_at",
        "insert into public.giveaway_chat_messages (chat_id, sender_id, body) "
        "select $1::uuid, $2::uuid, $3 where exists (select 1 from "
        "public.giveaway_pickup_chats c where c.id = $1::uuid and c.status = 'active' "
        "and now() < c.expires_at and (c.owner_id = $2::uuid or c.requester_id = $2::uuid)) "
        "returning id, created_at",
        "select id, chat_id, sender_id, body, body_deleted, created_at "
        "from public.giveaway_chat_messages where chat_id = $1::uuid "
        "order by created_at, id limit 500",
        "update public.giveaway_pickup_chats set pickup_plan = $2::jsonb, "
        "updated_at = now() where id = $1::uuid and status = 'active' "
        "and now() < expires_at returning id",
        "update public.giveaway_pickup_chats set report_flag = true, "
        "updated_at = now() where id = $1::uuid",
        "update public.giveaway_claims set status = 'cancelled', updated_at = now() "
        "where id = $1::uuid",
        "update public.giveaway_claims set status = 'not_selected', updated_at = now() "
        "where giveaway_id = $1::uuid and id <> $2::uuid and status = 'requested'",
        "update public.giveaway_claims cl set status = 'expired', updated_at = now() "
        "from public.giveaway_pickup_chats pc where pc.claim_id = cl.id "
        "and pc.status = 'expired' and cl.status = 'accepted'",
        "update public.giveaways g set status = 'available', updated_at = now() "
        "from public.giveaway_pickup_chats pc where pc.giveaway_id = g.id "
        "and pc.status = 'expired' and g.status = 'reserved' and not exists "
        "(select 1 from public.giveaway_pickup_chats live "
        "where live.giveaway_id = g.id and live.status = 'active')",
        "delete from public.giveaway_claims where status in ('declined','not_selected') "
        "and updated_at < now() - interval '72 hours'",
        "update public.giveaway_pickup_chats set status = 'expired', "
        "locked_at = coalesce(locked_at, now()), updated_at = now() "
        "where status = 'active' and now() >= expires_at returning id",
        "update public.giveaway_pickup_chats set expiry_notified = true, "
        "updated_at = now() where status = 'active' and expiry_notified = false "
        "and expires_at > now() and expires_at <= now() + interval '24 hours' "
        "returning giveaway_id, owner_id, requester_id",
        "update public.giveaway_chat_messages m set body = null, body_deleted = true, "
        "deleted_at = now() from public.giveaway_pickup_chats c "
        "where m.chat_id = c.id and m.body_deleted = false and c.report_flag = false "
        "and c.status in ('expired','completed','cancelled','locked')",
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
