"""Notifications feed — auth gates, validation, live SQL schema."""

from __future__ import annotations

import asyncio
import json
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
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
    return {"Authorization": f"Bearer {token}"}


def test_list_requires_token() -> None:
    assert client.get("/v1/notifications").status_code == 401


def test_mark_read_requires_token() -> None:
    assert client.post(f"/v1/notifications/{uuid.uuid4()}/read").status_code == 401


def test_mark_all_requires_token() -> None:
    assert client.post("/v1/notifications/read-all").status_code == 401


def test_mark_read_rejects_non_uuid() -> None:
    assert client.post("/v1/notifications/not-a-uuid/read", headers=_auth()).status_code == 422


def test_list_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/notifications", headers=_auth())
    assert resp.status_code not in (401, 422)


def test_unread_count_requires_token() -> None:
    assert client.get("/v1/notifications/unread-count").status_code == 401


def test_unread_count_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/notifications/unread-count", headers=_auth())
    assert resp.status_code not in (401, 422)


def test_preferences_get_requires_token() -> None:
    assert client.get("/v1/notifications/preferences").status_code == 401


def test_preferences_patch_requires_token() -> None:
    resp = client.patch("/v1/notifications/preferences", json={"social_activity": False})
    assert resp.status_code == 401


def test_preferences_patch_rejects_non_bool() -> None:
    resp = client.patch(
        "/v1/notifications/preferences",
        json={"social_activity": [1, 2, 3]},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_preferences_patch_rejects_unknown_field() -> None:
    # extra=forbid → an arbitrary/undocumented field is a 422, not silently kept.
    resp = client.patch(
        "/v1/notifications/preferences",
        json={"not_a_category": True},
        headers=_auth(),
    )
    assert resp.status_code == 422


# ── the unified pipeline: recipients, dedupe, routing, push ──────────────────


class _NotifConn:
    """A connection that models the ONE property this design depends on: writes
    made inside a transaction are only visible after that transaction commits.

    `notifications` and `notification_outbox` inserts land in a pending buffer
    while `in_txn` is set, and are discarded wholesale on rollback — so a test can
    assert what a reader (and therefore the push drainer) would actually see.
    """

    def __init__(self, *, returns: object = "n-1") -> None:
        self.returns = returns
        self.committed_notifications: list[tuple] = []
        self.committed_outbox: list[tuple] = []
        self._pending_notifications: list[tuple] = []
        self._pending_outbox: list[tuple] = []
        self.in_txn = False

    def transaction(self, *, rollback: bool = False):
        conn = self

        class _Tx:
            async def __aenter__(self):
                conn.in_txn = True
                return self

            async def __aexit__(self, exc_type, *_a):
                conn.in_txn = False
                if exc_type is not None or rollback:
                    conn._pending_notifications.clear()
                    conn._pending_outbox.clear()
                    return False
                conn.committed_notifications.extend(conn._pending_notifications)
                conn.committed_outbox.extend(conn._pending_outbox)
                conn._pending_notifications.clear()
                conn._pending_outbox.clear()
                return False

        return _Tx()

    def _record(self, bucket_pending: list, bucket_committed: list, args: tuple) -> None:
        (bucket_pending if self.in_txn else bucket_committed).append(args)

    async def fetchval(self, sql: str, *args):
        if "insert into public.notifications" in sql:
            self._record(self._pending_notifications, self.committed_notifications, args)
            return self.returns
        return None

    async def fetchrow(self, sql: str, *args):
        return None

    async def fetch(self, sql: str, *args):
        return []

    async def execute(self, sql: str, *args):
        if "insert into public.notification_outbox" in sql:
            self._record(self._pending_outbox, self.committed_outbox, args)
        return "INSERT 0 1"


def _outbox_payload(row: tuple) -> dict:
    """(notification_id, user_id, payload_json) -> the decoded push payload."""
    return json.loads(row[2])


def test_never_notifies_a_user_about_their_own_action() -> None:
    from app.services.notifications import create_notification

    conn = _NotifConn()
    out = asyncio.run(
        create_notification(
            conn, user_id="u1", actor_id="u1", type="like", title="You liked your own look"
        )
    )
    assert out.created is False
    assert conn.committed_notifications == []
    assert conn.committed_outbox == []


def test_dedupe_key_collapses_a_repeat_and_suppresses_the_second_push() -> None:
    """The second insert conflicts and RETURNs nothing — no record, and crucially
    no outbox row, so no second push. That is the noise the key exists to stop."""
    from app.services.notifications import create_notification

    conn = _NotifConn(returns=None)  # ON CONFLICT DO NOTHING → no id
    out = asyncio.run(
        create_notification(
            conn,
            user_id="u1",
            actor_id="u2",
            type="like",
            title="X liked your look",
            target_type="post",
            target_id="p1",
            dedupe_key="like:p1:u2",
        )
    )
    assert out.created is False
    assert conn.committed_outbox == []


def test_commit_yields_one_notification_and_one_push_intent() -> None:
    from app.services.notifications import create_notification

    conn = _NotifConn(returns="n-9")

    async def run() -> None:
        async with conn.transaction():
            await create_notification(
                conn,
                user_id="u1",
                actor_id="u2",
                type="giveaway_accepted",
                title="You were picked!",
                target_type="giveaway_chat",
                target_id="g1",
                dedupe_key="giveaway_accepted:c1",
                data={"chat_id": "ch1", "giveaway_id": "g1"},
            )

    asyncio.run(run())

    assert len(conn.committed_notifications) == 1
    assert len(conn.committed_outbox) == 1
    payload = _outbox_payload(conn.committed_outbox[0])
    # The intent carries everything needed to open the exact destination, even
    # when the push arrives with the app terminated.
    assert payload["data"]["route"] == "/wtm/giveaway-chat?id=g1"
    assert payload["data"]["target_type"] == "giveaway_chat"
    assert payload["data"]["chat_id"] == "ch1"
    assert payload["data"]["notification_id"] == "n-9"
    assert payload["android_channel"] == "wtm_community"


def test_rollback_leaves_no_notification_and_no_push() -> None:
    """The core guarantee. The notification insert succeeded, but the surrounding
    business transaction rolled back — so neither the record nor the push intent
    survives, and nothing can ping a device about an action that did not happen."""
    from app.services.notifications import create_notification

    conn = _NotifConn(returns="n-3")

    async def run() -> None:
        async with conn.transaction(rollback=True):
            out = await create_notification(
                conn,
                user_id="u1",
                actor_id="u2",
                type="giveaway_accepted",
                title="You were picked!",
                target_type="giveaway_chat",
                target_id="g1",
            )
            assert out.created is True  # it DID insert, inside the transaction

    asyncio.run(run())

    assert conn.committed_notifications == []
    assert conn.committed_outbox == []


def test_push_is_never_dispatched_from_create_notification(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Nothing may leave for FCM at insert time — the transaction has not
    committed yet, so a tap could reference rows the reader cannot see."""
    import app.services.notifications as mod

    sent: list = []
    monkeypatch.setattr(mod, "deliver_push_async", lambda uid, msg: sent.append((uid, msg)))
    monkeypatch.setattr(mod, "push_to_user", lambda uid, msg: sent.append((uid, msg)))

    conn = _NotifConn(returns="n-4")
    asyncio.run(mod.create_notification(conn, user_id="u1", type="like", title="t"))

    assert sent == []
    assert len(conn.committed_outbox) == 1  # queued, not sent


def test_push_failure_does_not_roll_back_the_notification(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Delivery is best-effort on top of a durable record. A sender that blows up
    must leave the notification (and the business action) intact."""
    import app.services.notifications as mod

    async def _boom(user_id, message):
        raise RuntimeError("fcm down")

    monkeypatch.setattr(mod, "push_to_user", _boom)

    conn = _NotifConn(returns="n-5")
    asyncio.run(mod.create_notification(conn, user_id="u1", type="like", title="t"))
    assert len(conn.committed_notifications) == 1
    assert len(conn.committed_outbox) == 1

    # Draining is what would surface the failure, and even there it is contained.
    class _Pool:
        def acquire(self):
            class _Ctx:
                async def __aenter__(self_inner):
                    class _C:
                        async def fetch(self_c, sql, *a):
                            return [
                                {
                                    "id": "o-1",
                                    "user_id": "u1",
                                    "payload": json.dumps({"title": "t", "body": "", "data": {}}),
                                }
                            ]

                        async def execute(self_c, sql, *a):
                            return "UPDATE 1"

                    return _C()

                async def __aexit__(self_inner, *_a):
                    return False

            return _Ctx()

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool())
    with pytest.raises(RuntimeError):
        asyncio.run(mod.drain_notification_outbox())


def test_outbox_drain_delivers_committed_intents(monkeypatch: pytest.MonkeyPatch) -> None:
    """Everything the drainer reads is, by construction, already committed."""
    import app.services.notifications as mod

    sent: list = []

    async def _send(user_id, message):
        sent.append((user_id, message))

    monkeypatch.setattr(mod, "push_to_user", _send)

    settled: list = []

    class _Conn:
        async def fetch(self, sql, *a):
            assert "for update skip locked" in sql  # two drainers never collide
            return [
                {
                    "id": "o-1",
                    "user_id": "u1",
                    "payload": json.dumps(
                        {
                            "title": "Your try-on is ready",
                            "body": "Tap to see it.",
                            "data": {"route": "/tryon/history"},
                            "android_channel": "wtm_account",
                        }
                    ),
                }
            ]

        async def execute(self, sql, *a):
            settled.append((sql, a))
            return "UPDATE 1"

    class _Pool:
        def acquire(self):
            class _Ctx:
                async def __aenter__(self_inner):
                    return _Conn()

                async def __aexit__(self_inner, *_a):
                    return False

            return _Ctx()

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool())
    assert asyncio.run(mod.drain_notification_outbox()) == 1

    assert len(sent) == 1
    user_id, message = sent[0]
    assert user_id == "u1"
    assert message.data["route"] == "/tryon/history"
    assert message.android_channel == "wtm_account"
    # And the row is marked delivered so it is never re-sent.
    assert any("set delivered_at = now()" in sql for sql, _ in settled)


def test_insert_failure_is_swallowed_and_reported() -> None:
    """A notification must never break the action that triggered it."""
    import app.services.notifications as mod

    class _Broken(_NotifConn):
        async def fetchval(self, sql: str, *args):
            raise RuntimeError("db down")

    conn = _Broken()
    out = asyncio.run(mod.create_notification(conn, user_id="u1", type="like", title="t"))
    assert out.created is False
    assert conn.committed_outbox == []


@pytest.mark.parametrize(
    ("ntype", "target_type", "target_id", "expected"),
    [
        ("giveaway_request", "giveaway", "g1", "/wtm/giveaways/detail?id=g1"),
        # ACCEPTED opens the conversation, not the listing the requester already
        # knows about — the chat is the whole point of being picked.
        ("giveaway_accepted", "giveaway_chat", "g1", "/wtm/giveaway-chat?id=g1"),
        ("giveaway_declined", "giveaway", "g1", "/wtm/giveaways/detail?id=g1"),
        ("giveaway_message", "giveaway_chat", "g1", "/wtm/giveaway-chat?id=g1"),
        # Async job results open what they produced.
        ("enhance_item", "wardrobe_item", "w1", "/wtm/closet/item?id=w1"),
        ("catalog_model", "generated_image", "gi1", "/wtm/looks"),
        ("try_on_ready", "tryon_result", "r1", "/tryon/history"),
        ("like", "post", "p1", "/wtm/social/post?id=p1"),
        ("comment", "post", "p1", "/wtm/social/post?id=p1"),
        ("follow", "user", "u2", "/wtm/user?u=u2"),
        ("offer", "offer", "o1", "/wtm/offers/detail?id=o1"),
        ("referral_reward", None, None, "/wtm/referral"),
        ("payment_issue", None, None, "/wtm/paywall"),
        # Unknown / missing targets must land somewhere safe, never nowhere.
        ("mystery_event", "mystery", "x1", "/wtm/inbox"),
        ("like", "post", None, "/wtm/inbox"),
    ],
)
def test_route_for_targets_the_actual_destination(
    ntype: str, target_type: str | None, target_id: str | None, expected: str
) -> None:
    from app.services.notifications import route_for

    assert route_for(ntype, target_type, target_id) == expected


def test_route_never_escapes_the_app() -> None:
    """A hostile id must not be able to steer the router off-app; the app also
    re-validates, but the server should not emit such a route in the first place."""
    from app.services.notifications import route_for

    route = route_for("like", "post", "https://evil.example/x")
    assert route.startswith("/wtm/social/post?id=")
    assert "://" not in route


def test_every_notification_type_maps_to_a_real_channel() -> None:
    """A type with no channel would raise at delivery time, losing the push."""
    from app.services.notifications import (
        _CATEGORY_BY_TYPE,
        _CHANNEL_BY_CATEGORY,
        PREFERENCE_CATEGORIES,
        _channel_for_type,
    )

    for ntype, category in _CATEGORY_BY_TYPE.items():
        assert category in PREFERENCE_CATEGORIES, ntype
        assert _CHANNEL_BY_CATEGORY[category]
    assert _channel_for_type("a-type-nobody-defined")  # unknown → default category


def test_offers_cron_only_notifies_promotional_opt_ins(monkeypatch: pytest.MonkeyPatch) -> None:
    """Offers are marketing. There is no audience model, so the cron uses the one
    targeting rule that exists — the opt-in `promotional` category — and never
    broadcasts to everyone."""
    import app.cron.offers as mod

    created: list[dict] = []

    async def _create(conn, **kwargs):
        created.append(kwargs)
        from app.services.notifications import NotificationOutcome

        return NotificationOutcome(True, "n-1")

    monkeypatch.setattr(mod, "create_notification", _create)

    class _Conn:
        async def fetch(self, sql: str, *args):
            if "from public.offers" in sql:
                return [{"id": "o1", "title": "50% off", "brand": "Acme", "discount_label": "-50%"}]
            return [{"user_id": "opted-in-1"}, {"user_id": "opted-in-2"}]

    assert asyncio.run(mod.notify_new_offers(_Conn())) == 2
    assert {c["user_id"] for c in created} == {"opted-in-1", "opted-in-2"}
    assert all(c["dedupe_key"] == "offer:o1" for c in created)
    assert all(c["target_type"] == "offer" for c in created)
    # The recipient query is the opt-in one, not "every profile".
    assert "np.promotional is true" in mod._OPTED_IN_SQL


def test_offers_cron_is_restartable(monkeypatch: pytest.MonkeyPatch) -> None:
    """A re-run creates nothing new: every notification collapses on its key."""
    import app.cron.offers as mod

    async def _create(conn, **kwargs):
        from app.services.notifications import NotificationOutcome

        return NotificationOutcome(False)  # already exists

    monkeypatch.setattr(mod, "create_notification", _create)

    class _Conn:
        async def fetch(self, sql: str, *args):
            if "from public.offers" in sql:
                return [{"id": "o1", "title": "t", "brand": None, "discount_label": None}]
            return [{"user_id": "u1"}]

    assert asyncio.run(mod.notify_new_offers(_Conn())) == 0


def test_notifications_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.notifications import _SELECT

    stmts = [
        # Keyset page: (created_at, id) is a total order, so a burst of
        # same-timestamp rows cannot repeat or skip across page boundaries.
        _SELECT
        + """
             where user_id = $1::uuid
               and ($2::timestamptz is null
                    or (created_at, id)
                         < ($2::timestamptz, coalesce($3::uuid, $5::uuid)))
             order by created_at desc, id desc
             limit $4
            """,
        "update public.notifications set is_read = true "
        "where id = $1::uuid and user_id = $2::uuid returning id",
        "update public.notifications set is_read = true "
        "where user_id = $1::uuid and is_read = false",
        "select count(*) from public.notifications where user_id = $1::uuid and is_read = false",
        "select account_updates, referral_rewards, social_activity, community, "
        "daily_style, product_updates, promotional "
        "from public.notification_preferences where user_id = $1::uuid",
        "insert into public.notification_preferences (user_id, social_activity) "
        "values ($1::uuid, $2) on conflict (user_id) do update set "
        "social_activity = excluded.social_activity, updated_at = now() "
        "returning account_updates, referral_rewards, social_activity, community, "
        "daily_style, product_updates, promotional",
        # create_notification insert (app.services.notifications) — the ON CONFLICT
        # target must match the partial unique index from migration 0050, or
        # Postgres rejects it at prepare time.
        """
            insert into public.notifications
              (user_id, actor_id, type, title, body, target_type, target_id,
               dedupe_key, data)
            values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9::jsonb)
            on conflict (user_id, dedupe_key) where dedupe_key is not null
              do nothing
            returning id
        """,
        # cron/offers.py recipient query — strictly the promotional opt-ins.
        "select np.user_id from public.notification_preferences np "
        "join public.profiles pr on pr.id = np.user_id "
        "where np.promotional is true and pr.account_status = 'active'",
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
