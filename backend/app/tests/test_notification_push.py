"""Event → push wiring (§20): channel + route mapping and PushMessage plumbing.
Pure/offline — no DB or FCM needed."""

from __future__ import annotations

import asyncio

from app.services.notifications import (
    _category_for_type,
    _channel_for_type,
    _push_category_enabled,
    _route_for_type,
)
from app.services.push import PushMessage


class _FakePrefConn:
    def __init__(self, row):
        self._row = row

    async def fetchrow(self, sql, *args):
        return self._row


def test_category_for_type_maps_to_preference_categories() -> None:
    assert _category_for_type("referral_reward") == "referral"
    for t in ("follow", "like", "comment", "post"):
        assert _category_for_type(t) == "social"
    assert _category_for_type("giveaway") == "community"
    assert _category_for_type("daily_stylist") == "style"
    assert _category_for_type("announcement") == "promotions"
    assert _category_for_type("something_new") == "account"  # safe on-by-default


def test_push_category_enabled_defaults_when_no_row() -> None:
    conn = _FakePrefConn(None)
    assert asyncio.run(_push_category_enabled(conn, "u", "social")) is True
    assert asyncio.run(_push_category_enabled(conn, "u", "referral")) is True
    # Promotions are opt-in → OFF by default.
    assert asyncio.run(_push_category_enabled(conn, "u", "promotions")) is False


def test_push_category_enabled_respects_the_row() -> None:
    row = {
        "social": False, "referral": True, "account": True,
        "community": True, "style": True, "promotions": True,
    }
    conn = _FakePrefConn(row)
    assert asyncio.run(_push_category_enabled(conn, "u", "social")) is False  # muted
    assert asyncio.run(_push_category_enabled(conn, "u", "referral")) is True
    assert asyncio.run(_push_category_enabled(conn, "u", "promotions")) is True  # opted in


def test_channel_for_type_routes_events_to_the_right_android_channel() -> None:
    # Referral + account/job events → wtm_account.
    assert _channel_for_type("referral_reward") == "wtm_account"
    assert _channel_for_type("catalog_model") == "wtm_account"
    assert _channel_for_type("enhance_item") == "wtm_account"
    # Social → wtm_social.
    for t in ("follow", "like", "comment", "reply", "mention", "post", "user"):
        assert _channel_for_type(t) == "wtm_social", t
    # Community → wtm_community.
    assert _channel_for_type("giveaway") == "wtm_community"
    assert _channel_for_type("giveaway_message") == "wtm_community"
    # Anything else → the manifest default channel.
    assert _channel_for_type("something_new") == "wtm_updates"


def test_route_for_type_is_a_valid_in_app_path() -> None:
    assert _route_for_type("referral_reward") == "/wtm/referral"
    assert _route_for_type("follow") == "/wtm/inbox"
    assert _route_for_type("giveaway") == "/wtm/inbox"
    # Never a scheme/host (app-side isValidPushRoute rejects those).
    for t in ("referral_reward", "follow", "like", "giveaway", "post"):
        r = _route_for_type(t)
        assert r.startswith("/") and not r.startswith("//") and "://" not in r


def test_push_message_carries_optional_channel() -> None:
    m = PushMessage(
        title="You earned 10 referral credits",
        body="An eligible friend joined Wear The Mood using your invite.",
        data={"type": "referral_reward", "route": "/wtm/referral"},
        android_channel="wtm_account",
    )
    assert m.android_channel == "wtm_account"
    assert m.data["route"] == "/wtm/referral"
    # Defaults to None (→ manifest default channel) when unset.
    assert PushMessage(title="t", body="b").android_channel is None
