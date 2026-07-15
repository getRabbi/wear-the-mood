"""Event → push wiring (§20): channel + route mapping and PushMessage plumbing.
Pure/offline — no DB or FCM needed."""

from __future__ import annotations

from app.services.notifications import _channel_for_type, _route_for_type
from app.services.push import PushMessage


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
