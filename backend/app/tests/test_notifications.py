"""Notifications feed — auth gates, validation, live SQL schema."""

from __future__ import annotations

import asyncio
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
    """Records the notification insert and controls what it RETURNs, so both the
    'inserted' and the 'collapsed by dedupe_key' branches are exercisable."""

    def __init__(self, *, returns: object = "n-1") -> None:
        self.returns = returns
        self.inserts: list[tuple] = []

    async def fetchval(self, sql: str, *args):
        if "insert into public.notifications" in sql:
            self.inserts.append(args)
            return self.returns
        return None

    async def fetchrow(self, sql: str, *args):
        return None

    async def fetch(self, sql: str, *args):
        return []

    async def execute(self, sql: str, *args):
        return "INSERT 0 1"


def _pushes(monkeypatch: pytest.MonkeyPatch) -> list:
    import app.services.notifications as mod

    sent: list = []
    monkeypatch.setattr(mod, "deliver_push_async", lambda uid, msg: sent.append((uid, msg)))
    return sent


def test_never_notifies_a_user_about_their_own_action(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services.notifications import create_notification

    sent = _pushes(monkeypatch)
    conn = _NotifConn()
    out = asyncio.run(
        create_notification(
            conn, user_id="u1", actor_id="u1", type="like", title="You liked your own look"
        )
    )
    assert out.created is False
    assert conn.inserts == []
    assert sent == []


def test_dedupe_key_collapses_a_repeat_and_suppresses_the_second_push(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The second insert conflicts and RETURNs nothing — no record, and crucially
    no second push, which is the noise the key exists to prevent."""
    from app.services.notifications import create_notification

    sent = _pushes(monkeypatch)
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
    assert sent == []


def test_a_new_event_is_recorded_and_pushed(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services.notifications import create_notification

    sent = _pushes(monkeypatch)
    conn = _NotifConn(returns="n-9")
    out = asyncio.run(
        create_notification(
            conn,
            user_id="u1",
            actor_id="u2",
            type="giveaway_accepted",
            title="You were picked!",
            target_type="giveaway",
            target_id="g1",
            dedupe_key="giveaway_accepted:c1",
            data={"chat_id": "ch1", "giveaway_id": "g1"},
        )
    )
    assert out.created is True and out.notification_id == "n-9"
    assert len(sent) == 1
    user_id, message = sent[0]
    assert user_id == "u1"
    # The push carries everything the app needs to open the exact destination,
    # including when it arrives with the app terminated.
    assert message.data["route"] == "/wtm/giveaways/detail?id=g1"
    assert message.data["target_type"] == "giveaway"
    assert message.data["target_id"] == "g1"
    assert message.data["chat_id"] == "ch1"
    assert message.data["notification_id"] == "n-9"
    assert message.android_channel == "wtm_community"


def test_push_failure_does_not_prevent_the_durable_record(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.services.notifications as mod

    def _boom(uid, msg):
        raise RuntimeError("fcm down")

    monkeypatch.setattr(mod, "deliver_push_async", _boom)
    conn = _NotifConn(returns="n-2")
    with pytest.raises(RuntimeError):
        asyncio.run(mod.create_notification(conn, user_id="u1", type="like", title="t"))
    # The record was written BEFORE delivery was attempted.
    assert len(conn.inserts) == 1


def test_insert_failure_is_swallowed_and_reported(monkeypatch: pytest.MonkeyPatch) -> None:
    """A notification must never break the action that triggered it."""
    import app.services.notifications as mod

    sent = _pushes(monkeypatch)

    class _Broken(_NotifConn):
        async def fetchval(self, sql: str, *args):
            raise RuntimeError("db down")

    out = asyncio.run(mod.create_notification(_Broken(), user_id="u1", type="like", title="t"))
    assert out.created is False
    assert sent == []


@pytest.mark.parametrize(
    ("ntype", "target_type", "target_id", "expected"),
    [
        ("giveaway_request", "giveaway", "g1", "/wtm/giveaways/detail?id=g1"),
        ("giveaway_accepted", "giveaway", "g1", "/wtm/giveaways/detail?id=g1"),
        ("giveaway_declined", "giveaway", "g1", "/wtm/giveaways/detail?id=g1"),
        ("giveaway_message", "giveaway_chat", "g1", "/wtm/giveaway-chat?id=g1"),
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
