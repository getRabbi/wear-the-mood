"""Event → push wiring (§3/§6/§20): canonical category mapping, Android channel +
route resolution, the master+category delivery gate, and invalid-token pruning.
Pure/offline — no real DB or FCM needed (fakes stand in for both)."""

from __future__ import annotations

import asyncio

import pytest

from app.services.notifications import (
    _category_for_type,
    _channel_for_type,
    _invalidate_tokens,  # noqa: F401  (imported for coverage of the module surface)
    _push_category_enabled,
    _route_for_type,
    _send_with_retry,
    push_to_user,
)
from app.services.push import DeliveryStatus, PushMessage

# ── canonical category mapping (§3) ──────────────────────────────────────────


def test_category_for_type_maps_to_the_seven_categories() -> None:
    assert _category_for_type("referral_reward") == "referral_rewards"
    for t in ("payment_issue", "subscription_expired", "subscription_refunded", "account_warning"):
        assert _category_for_type(t) == "account_updates", t
    for t in ("follow", "like", "comment", "reply", "mention"):
        assert _category_for_type(t) == "social_activity", t
    for t in ("community", "giveaway", "challenge"):
        assert _category_for_type(t) == "community", t
    assert _category_for_type("daily_style") == "daily_style"
    assert _category_for_type("product_update") == "product_updates"
    for t in ("promotion", "offer"):
        assert _category_for_type(t) == "promotional", t


def test_unknown_type_uses_a_safe_on_by_default_category() -> None:
    # Unknown → account_updates (on by default) — never a bypass of preferences.
    assert _category_for_type("brand_new_event") == "account_updates"


def test_channel_for_type_routes_to_the_native_channels() -> None:
    assert _channel_for_type("referral_reward") == "wtm_account"
    assert _channel_for_type("payment_issue") == "wtm_account"
    for t in ("follow", "like", "comment", "reply", "mention"):
        assert _channel_for_type(t) == "wtm_social", t
    assert _channel_for_type("giveaway") == "wtm_community"
    assert _channel_for_type("daily_style") == "wtm_style"
    assert _channel_for_type("product_update") == "wtm_updates"
    assert _channel_for_type("promotion") == "wtm_updates"
    assert _channel_for_type("brand_new_event") == "wtm_account"  # via default category


def test_route_for_type_is_a_valid_in_app_path() -> None:
    assert _route_for_type("referral_reward") == "/wtm/referral"
    assert _route_for_type("subscription_expired") == "/wtm/paywall"
    assert _route_for_type("payment_issue") == "/wtm/paywall"
    assert _route_for_type("follow") == "/wtm/inbox"
    assert _route_for_type("giveaway") == "/wtm/inbox"
    # Never a scheme/host (app-side isValidPushRoute rejects those).
    for t in ("referral_reward", "subscription_expired", "follow", "giveaway"):
        r = _route_for_type(t)
        assert r.startswith("/") and not r.startswith("//") and "://" not in r


# ── per-category delivery gate (§5) ──────────────────────────────────────────


class _FakePrefConn:
    def __init__(self, row):
        self._row = row

    async def fetchrow(self, sql, *args):
        return self._row


def test_push_category_enabled_defaults_when_no_row() -> None:
    conn = _FakePrefConn(None)
    for cat in (
        "account_updates",
        "referral_rewards",
        "social_activity",
        "community",
        "daily_style",
        "product_updates",
    ):
        assert asyncio.run(_push_category_enabled(conn, "u", cat)) is True, cat
    # promotional is opt-in → OFF by default.
    assert asyncio.run(_push_category_enabled(conn, "u", "promotional")) is False


def test_push_category_enabled_respects_the_row() -> None:
    row = {
        "account_updates": True,
        "referral_rewards": True,
        "social_activity": False,
        "community": True,
        "daily_style": True,
        "product_updates": True,
        "promotional": True,
    }
    conn = _FakePrefConn(row)
    assert asyncio.run(_push_category_enabled(conn, "u", "social_activity")) is False  # muted
    assert asyncio.run(_push_category_enabled(conn, "u", "account_updates")) is True
    assert asyncio.run(_push_category_enabled(conn, "u", "promotional")) is True  # opted in


def test_push_category_enabled_fails_open_on_error() -> None:
    class _BoomConn:
        async def fetchrow(self, *a):
            raise RuntimeError("db blip")

    # A lookup blip must not silently drop a real (non-promotional) push.
    assert asyncio.run(_push_category_enabled(_BoomConn(), "u", "social_activity")) is True
    assert asyncio.run(_push_category_enabled(_BoomConn(), "u", "promotional")) is False


# ── bounded retry (§6) ───────────────────────────────────────────────────────


class _SeqSender:
    """Returns a scripted status per call so we can assert retry behaviour."""

    name = "seq"

    def __init__(self, statuses):
        self._statuses = list(statuses)
        self.calls = 0

    async def send(self, token, message):
        self.calls += 1
        return self._statuses.pop(0) if self._statuses else DeliveryStatus.ok


def test_send_with_retry_stops_on_first_ok() -> None:
    s = _SeqSender([DeliveryStatus.ok])
    msg = PushMessage(title="t", body="b")
    assert asyncio.run(_send_with_retry(s, "tok", msg)) == DeliveryStatus.ok
    assert s.calls == 1


def test_send_with_retry_retries_then_gives_up_bounded() -> None:
    s = _SeqSender([DeliveryStatus.retryable, DeliveryStatus.retryable])
    msg = PushMessage(title="t", body="b")
    assert asyncio.run(_send_with_retry(s, "tok", msg)) == DeliveryStatus.retryable
    assert s.calls == 2  # bounded — never infinite


def test_send_with_retry_does_not_retry_invalid_or_auth() -> None:
    for terminal in (DeliveryStatus.invalid_token, DeliveryStatus.auth_error):
        s = _SeqSender([terminal, DeliveryStatus.ok])
        msg = PushMessage(title="t", body="b")
        assert asyncio.run(_send_with_retry(s, "tok", msg)) == terminal
        assert s.calls == 1  # returned immediately — no pointless retry


# ── push_to_user: master+category gate + invalid-token pruning (§5/§6) ───────


class _StatusSender:
    """Maps token → the DeliveryStatus it should report."""

    name = "status"

    def __init__(self, mapping):
        self._mapping = mapping
        self.sent: list[str] = []

    async def send(self, token, message):
        self.sent.append(token)
        return self._mapping.get(token, DeliveryStatus.ok)


class _FakeConn:
    def __init__(self, pool):
        self._pool = pool

    async def fetchrow(self, sql, *args):
        return self._pool.prefs_row  # preference lookup

    async def fetch(self, sql, *args):
        # Only the still-valid, opted-in tokens (the query filters the rest).
        return [{"token": t} for t in self._pool.tokens]

    async def execute(self, sql, *args):
        self._pool.executes.append(args)


class _FakeAcquire:
    def __init__(self, pool):
        self._pool = pool

    async def __aenter__(self):
        return _FakeConn(self._pool)

    async def __aexit__(self, *exc):
        return False


class _FakePool:
    def __init__(self, tokens, prefs_row=None):
        self.tokens = tokens
        self.prefs_row = prefs_row
        self.executes: list = []

    def acquire(self):
        return _FakeAcquire(self)


def _patch(monkeypatch, pool, sender):
    import app.services.notifications as m

    monkeypatch.setattr(m, "get_pool", lambda: pool)
    monkeypatch.setattr(m, "get_push_sender", lambda: sender)


def _msg(kind="follow"):
    return PushMessage(title="t", body="b", data={"type": kind, "route": "/wtm/inbox"})


def test_push_to_user_prunes_only_invalid_tokens(monkeypatch) -> None:
    pool = _FakePool(tokens=["ok1", "dead", "retry1"])
    sender = _StatusSender(
        {"dead": DeliveryStatus.invalid_token, "retry1": DeliveryStatus.retryable}
    )
    _patch(monkeypatch, pool, sender)
    asyncio.run(push_to_user("u", _msg()))
    # Exactly one invalidate execute, carrying only the dead token.
    assert len(pool.executes) == 1
    args = pool.executes[0]  # (user_id, [tokens]) — sql is the named first param
    assert args[1] == ["dead"]


def test_push_to_user_does_not_prune_when_all_healthy(monkeypatch) -> None:
    pool = _FakePool(tokens=["a", "b"])
    sender = _StatusSender({})  # all ok
    _patch(monkeypatch, pool, sender)
    asyncio.run(push_to_user("u", _msg()))
    assert pool.executes == []  # nothing invalidated


def test_push_to_user_auth_error_stops_and_prunes_nothing(monkeypatch) -> None:
    # A credential/project failure is identical for every token — stop, prune none.
    pool = _FakePool(tokens=["a", "b", "c"])
    sender = _StatusSender({"a": DeliveryStatus.auth_error})
    _patch(monkeypatch, pool, sender)
    asyncio.run(push_to_user("u", _msg()))
    assert pool.executes == []  # invalidated nothing
    assert sender.sent == ["a"]  # stopped after the first (no storm)


def test_push_to_user_skips_when_category_muted(monkeypatch) -> None:
    # promotional is off by default (no prefs row) → no send at all.
    pool = _FakePool(tokens=["a"])
    sender = _StatusSender({})
    _patch(monkeypatch, pool, sender)
    asyncio.run(push_to_user("u", _msg("promotion")))
    assert sender.sent == []  # muted category → durable record only, no push


def test_push_to_user_dedupes_repeated_tokens(monkeypatch) -> None:
    pool = _FakePool(tokens=["dup", "dup", "other"])
    sender = _StatusSender({})
    _patch(monkeypatch, pool, sender)
    asyncio.run(push_to_user("u", _msg()))
    assert sender.sent == ["dup", "other"]  # each device once


# ── FCM error classification (only runs where firebase-admin is installed) ───


def test_fcm_classify_maps_errors_to_delivery_status() -> None:
    pytest.importorskip("firebase_admin")
    from firebase_admin import exceptions as fx
    from firebase_admin import messaging

    from app.services.push.fcm import _classify

    # Permanent, token-specific → invalidate.
    assert _classify(messaging.UnregisteredError("gone")) == DeliveryStatus.invalid_token
    assert _classify(messaging.SenderIdMismatchError("mismatch")) == DeliveryStatus.invalid_token
    assert (
        _classify(fx.InvalidArgumentError("The registration token is not valid"))
        == DeliveryStatus.invalid_token
    )
    # INVALID_ARGUMENT that is NOT about the token → retryable, never a mass-prune.
    assert _classify(fx.InvalidArgumentError("bad payload field")) == DeliveryStatus.retryable
    # Credential/project → auth_error (stop, invalidate nothing).
    assert _classify(fx.UnauthenticatedError("bad creds")) == DeliveryStatus.auth_error
    # Transient → retryable.
    assert _classify(fx.UnavailableError("503")) == DeliveryStatus.retryable
    assert _classify(fx.InternalError("500")) == DeliveryStatus.retryable
    # Unknown → conservative retryable (never invalidate on a guess).
    assert _classify(RuntimeError("who knows")) == DeliveryStatus.retryable
