"""Monetization policy, credit-policy versioning and paywall pressure.

The most important test in this file is the FIRST one: with nothing configured
and every flag off — which is exactly what migration 0076 seeds and exactly what
production looks like the moment this ships — the policy must return today's
numbers. Everything else here is an experiment that has to be switched on
deliberately (spec §53).
"""

from __future__ import annotations

import asyncio
import json

from app.core.config import get_settings
from app.core.monetization import (
    RENDER_QUALITIES,
    LegacyCreditPolicy,
    MonetizationPolicy,
    PressureVerdict,
    TieredCreditPolicy,
    build_credit_policy,
    get_policy,
    may_interrupt,
)
from app.core.plans import AI_ENHANCE_COST, HD_COST, MAX_APP_CREDITS_PER_RENDER, STD_COST


class _FakeConn:
    """Stand-in for the asyncpg connection behind the policy loader.

    Answers the three queries `get_policy` makes — config rows, flag lookups,
    experiment assignments — from plain dicts, so the composition logic is
    testable without a database.
    """

    def __init__(
        self,
        *,
        config: dict | None = None,
        flags: dict | None = None,
        experiments: dict | None = None,
        events: dict | None = None,
        table_missing: bool = False,
    ):
        self.config = config or {}
        self.flags = flags or {}
        self.experiments = experiments or {}
        self.events = events or {}
        self.table_missing = table_missing
        self.inserted: list[tuple] = []

    @staticmethod
    def _norm(sql: str) -> str:
        return " ".join(sql.split()).lower()

    async def fetch(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.monetization_config" in s:
            if self.table_missing:
                import asyncpg

                raise asyncpg.UndefinedTableError("no such table")
            return [{"key": k, "value": json.dumps(v)} for k, v in self.config.items()]
        if "from public.experiment_assignments" in s:
            return [{"experiment": k, "variant": v} for k, v in self.experiments.items()]
        if "from public.feature_flags" in s:
            # Batched read: only keys with a ROW come back, exactly like the
            # real table, so an unset flag exercises the caller's own default.
            return [{"key": k, "enabled": v} for k, v in self.flags.items() if k in args[0]]
        return []

    async def fetchval(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.feature_flags" in s:
            return self.flags.get(args[0])
        if "extract(epoch" in s:
            return self.events.get("_hours", {}).get(args[0], 0.0)
        return None

    async def fetchrow(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.monetization_events" in s:
            return self.events.get("row")
        return None

    async def execute(self, sql: str, *args):
        self.inserted.append(args)
        return "INSERT 0 1"

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()


# ── the control case ─────────────────────────────────────────────────────────


def test_seeded_defaults_reproduce_current_production() -> None:
    """Every config key null, every flag off - the shipped numbers."""
    conn = _FakeConn(
        config={
            "free_render_lifetime_limit": None,
            "render_cost_standard": None,
            "render_cost_hd": None,
            "render_cost_enhance": None,
            "trial_enabled": False,
            "rollover_enabled": False,
        }
    )
    policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
    assert policy.std_cost == STD_COST == 1
    assert policy.hd_cost == HD_COST == 1
    assert policy.enhance_cost == AI_ENHANCE_COST == 1
    assert policy.free_render_limit == get_settings().free_tryon_trial_credits
    assert policy.trial_enabled is False
    assert policy.rollover_enabled is False
    assert policy.credits.version == "legacy"


def test_missing_config_table_falls_back_to_code_defaults() -> None:
    """A backend deployed BEFORE its migration must still price correctly."""
    conn = _FakeConn(table_missing=True)
    policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
    assert (policy.std_cost, policy.hd_cost, policy.enhance_cost) == (1, 1, 1)
    assert policy.free_render_limit == get_settings().free_tryon_trial_credits


# ── credit economics v2 ──────────────────────────────────────────────────────


def test_every_action_costs_one_app_credit() -> None:
    """Standard, HD and AI Enhance are all one credit."""
    policy = LegacyCreditPolicy()
    assert policy.tryon_cost(hd=False) == 1
    assert policy.tryon_cost(hd=True) == 1
    assert policy.premium_ai_cost(hd=False, enhance=True) == 1


def test_the_v2_quality_ladder_is_clamped_to_one_credit() -> None:
    """The tiered table survives, and every rung of it is capped.

    It was written when a render could cost 2-5 by quality. Quality is
    what somebody CHOSE, not a price ladder, so the structure is kept (a
    future currency change would use it) while the numbers it can produce
    are bounded by the same cap everything else obeys. Turning the flag on
    can therefore no longer raise anybody's bill."""
    policy = build_credit_policy({}, v2=True)
    assert isinstance(policy, TieredCreditPolicy)
    for quality in RENDER_QUALITIES:
        assert policy.tryon_cost(hd=True, quality=quality) == 1, quality
    assert policy.tryon_cost(hd=False) == 1
    assert policy.tryon_cost(hd=True) == 1


def test_v2_flag_off_keeps_legacy_costs() -> None:
    policy = build_credit_policy({}, v2=False)
    assert (policy.tryon_cost(hd=False), policy.tryon_cost(hd=True)) == (1, 1)


def test_config_may_lower_a_cost_but_never_raise_it() -> None:
    """An operator can run a free promotion. They cannot outprice the
    product's promise from a database row that no diff shows and no test
    reads — the clamp in `build_credit_policy` is what makes that true."""
    cheaper = build_credit_policy({"render_cost_standard": 0}, v2=False)
    assert cheaper.tryon_cost(hd=False) == 0

    dearer = build_credit_policy({"render_cost_hd": 3}, v2=False)
    assert dearer.tryon_cost(hd=True) == MAX_APP_CREDITS_PER_RENDER
    assert dearer.tryon_cost(hd=False) == 1  # untouched


def test_a_boolean_is_not_a_number() -> None:
    """`true` in a numeric config slot must not silently become 1 credit."""
    policy = build_credit_policy({"render_cost_hd": True}, v2=False)
    assert policy.tryon_cost(hd=True) == HD_COST


# ── render gate v2 ───────────────────────────────────────────────────────────


def test_free_limit_unchanged_when_only_the_number_is_configured() -> None:
    """Configuring a number without turning the flag on must do nothing."""
    conn = _FakeConn(config={"free_render_lifetime_limit": 2})
    policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
    assert policy.free_render_limit == get_settings().free_tryon_trial_credits


def test_free_limit_unchanged_when_only_the_flag_is_on() -> None:
    """And turning the flag on without a number must also do nothing."""
    conn = _FakeConn(flags={"feature_render_gate_v2": True})
    policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
    assert policy.free_render_limit == get_settings().free_tryon_trial_credits


def test_experiment_variants_set_two_and_three() -> None:
    for variant, expected in (("v2", 2), ("v3", 3)):
        conn = _FakeConn(
            flags={"feature_render_gate_v2": True}, experiments={"free_allowance": variant}
        )
        policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
        assert policy.free_render_limit == expected


def test_control_variant_keeps_the_deployed_setting() -> None:
    conn = _FakeConn(
        flags={"feature_render_gate_v2": True},
        experiments={"free_allowance": "control"},
        config={"free_render_lifetime_limit": None},
    )
    policy = asyncio.run(get_policy(conn, "user-1"))  # type: ignore[arg-type]
    assert policy.free_render_limit == get_settings().free_tryon_trial_credits


# ── paywall pressure ─────────────────────────────────────────────────────────


def _policy(**over) -> MonetizationPolicy:
    base = dict(
        credits=LegacyCreditPolicy(),
        free_render_limit=3,
        paywall_cooldown_hours=24,
        post_purchase_cooldown_hours=72,
        paywall_timing_variant="control",
        trial_enabled=False,
        trial_credit_cap=None,
        rollover_enabled=False,
        rollover_cap_multiplier=1,
        quality_recovery_limit_30d=1,
        push_frequency_cap_7d=2,
        paywall_v2=False,
        render_gate_v2=False,
        experiments={},
    )
    base.update(over)
    return MonetizationPolicy(**base)  # type: ignore[arg-type]


def test_subscriber_with_credits_is_never_interrupted() -> None:
    conn = _FakeConn()
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="pro", has_credits=True)  # type: ignore[arg-type]
    )
    assert verdict == PressureVerdict(False, "subscriber_with_credits")


def test_a_clean_history_allows_one_interruption() -> None:
    conn = _FakeConn(events={"row": {"purchased_at": None, "dismissed_at": None, "shown_at": None}})
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="free", has_credits=False)  # type: ignore[arg-type]
    )
    assert verdict.allowed is True


def test_a_dismissal_starts_a_cooldown() -> None:
    conn = _FakeConn(
        events={
            "row": {"purchased_at": None, "dismissed_at": "2h-ago", "shown_at": None},
            "_hours": {"2h-ago": 2.0},
        }
    )
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="free", has_credits=False)  # type: ignore[arg-type]
    )
    assert verdict.allowed is False
    assert verdict.reason == "dismiss_cooldown"
    assert verdict.retry_after_hours == 23


def test_a_dismissal_expires_after_the_cooldown() -> None:
    conn = _FakeConn(
        events={
            "row": {"purchased_at": None, "dismissed_at": "yesterday", "shown_at": None},
            "_hours": {"yesterday": 25.0},
        }
    )
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="free", has_credits=False)  # type: ignore[arg-type]
    )
    assert verdict.allowed is True


def test_a_pack_buyer_gets_a_longer_quiet_period() -> None:
    """Someone who just paid must not be immediately asked to pay again."""
    conn = _FakeConn(
        events={
            "row": {"purchased_at": "1h-ago", "dismissed_at": None, "shown_at": None},
            "_hours": {"1h-ago": 1.0},
        }
    )
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="free", has_credits=False)  # type: ignore[arg-type]
    )
    assert verdict.allowed is False
    assert verdict.reason == "post_purchase_cooldown"


def test_an_out_of_credits_subscriber_may_still_be_offered_a_top_up() -> None:
    conn = _FakeConn(events={"row": {"purchased_at": None, "dismissed_at": None, "shown_at": None}})
    verdict = asyncio.run(
        may_interrupt(conn, "u", policy=_policy(), tier="pro", has_credits=False)  # type: ignore[arg-type]
    )
    assert verdict.allowed is True
