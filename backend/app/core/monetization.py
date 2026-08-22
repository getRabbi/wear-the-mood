"""Server-authoritative monetization policy (spec §7, §8, §10, §39).

ONE place decides what a render costs, how many free renders a user gets, and
whether an interruptive paywall may be shown right now. Before this module those
three answers lived in three different places — `plans.STD_COST`, a settings
value, and nowhere at all — which made "run an experiment" a code change and a
binary release.

The contract that makes this safe to deploy on day one:

    Every config value defaults to None, and None means "use the code default".

So a freshly-migrated database (0076 seeds every render/allowance key as jsonb
null) produces byte-for-byte today's behaviour: 1 credit standard, 4 HD, 4
enhance, 3 lifetime free renders from FREE_TRYON_TRIAL_CREDITS. An experiment is
something an operator turns on deliberately, never something a deploy does.

Credit *charging* itself is untouched — `core.credits.spend_credit` /
`refund_credit` keep their atomic reserve, their idempotency and their
exact-bucket refund. This layer only decides the NUMBER handed to them.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Protocol

import asyncpg

from app.core.config import get_settings
from app.core.plans import (
    AI_ENHANCE_COST,
    HD_COST,
    MAX_APP_CREDITS_PER_RENDER,
    STD_COST,
)

log = logging.getLogger("fashionos.monetization")

#: Flag that lets the v2 cost table replace the legacy 1/4 mapping (§8.2).
FLAG_CREDIT_ECONOMICS_V2 = "feature_credit_economics_v2"
#: Flag that lets an experimental lifetime free allowance replace the trial (§9).
FLAG_RENDER_GATE_V2 = "feature_render_gate_v2"
#: Flag that lets the app render the v2 paywall composition (§8, Phase 8).
FLAG_PAYWALL_V2 = "feature_paywall_v2"

#: Quality tiers a render can be requested at, in ascending provider cost. Only
#: `standard` and `hd` are reachable today; the rest exist so the v2 cost table
#: can be populated and tested before any surface offers them (§8.1).
RENDER_QUALITIES = ("standard", "hd", "hd_plus", "studio", "studio_4k")

#: The v2 mapping: WTM credits approximate the external provider cost (§8.1).
#: Inert until `feature_credit_economics_v2` is ON.
_V2_COSTS = {
    "standard": 1,
    "hd": 2,
    "hd_plus": 3,
    "studio": 4,
    "studio_4k": 5,
}


class CreditPolicy(Protocol):
    """How many app credits an action costs. Two implementations: the legacy
    one that reproduces today's prices exactly, and the v2 one behind a flag."""

    version: str

    def tryon_cost(self, *, hd: bool, quality: str | None = None) -> int: ...

    def premium_ai_cost(self, *, hd: bool, enhance: bool = False) -> int: ...


@dataclass(frozen=True)
class LegacyCreditPolicy:
    """Today's production prices: 1 standard, 4 HD, 4 AI Enhance.

    Overridable per-key from `monetization_config`, but ONLY where an operator
    has explicitly written a number — a null (the seeded state) keeps the
    compiled constant, so this class cannot drift from `core.plans` by accident.
    """

    standard: int = STD_COST
    hd: int = HD_COST
    enhance: int = AI_ENHANCE_COST
    version: str = "legacy"

    def tryon_cost(self, *, hd: bool, quality: str | None = None) -> int:
        return self.hd if hd else self.standard

    def premium_ai_cost(self, *, hd: bool, enhance: bool = False) -> int:
        if enhance:
            return self.enhance
        return self.hd if hd else self.standard


@dataclass(frozen=True)
class TieredCreditPolicy:
    """Credit economics v2 (§8.1): cost scales with the render quality actually
    requested, so a cheap render is cheap for the user too.

    `hd=True` with no explicit quality maps to `hd`, which is 2 here rather than
    4 — that is the whole point of the experiment and exactly why it stays
    behind `feature_credit_economics_v2` until the economics are reviewed.
    """

    costs: dict[str, int]
    enhance: int = AI_ENHANCE_COST
    version: str = "v2"

    def tryon_cost(self, *, hd: bool, quality: str | None = None) -> int:
        key = quality or ("hd" if hd else "standard")
        return self.costs.get(key, self.costs["hd"] if hd else self.costs["standard"])

    def premium_ai_cost(self, *, hd: bool, enhance: bool = False) -> int:
        if enhance:
            return self.enhance
        return self.tryon_cost(hd=hd)


@dataclass(frozen=True)
class MonetizationPolicy:
    """The full policy snapshot for ONE user at ONE moment.

    Composed per request from `monetization_config` + the feature flags + the
    user's experiment assignment. Cheap to build (two small queries) and never
    cached across users — a stale policy is a wrong price.
    """

    credits: CreditPolicy
    #: Lifetime free standard renders. Falls back to the deployed setting.
    free_render_limit: int
    #: Hours before another INTERRUPTIVE monetization surface may be shown.
    paywall_cooldown_hours: int
    post_purchase_cooldown_hours: int
    paywall_timing_variant: str
    trial_enabled: bool
    trial_credit_cap: int | None
    rollover_enabled: bool
    rollover_cap_multiplier: int
    quality_recovery_limit_30d: int
    push_frequency_cap_7d: int
    paywall_v2: bool
    render_gate_v2: bool
    #: {experiment: variant} for everything this user is currently assigned to.
    experiments: dict[str, str]

    @property
    def std_cost(self) -> int:
        return self.credits.tryon_cost(hd=False)

    @property
    def hd_cost(self) -> int:
        return self.credits.tryon_cost(hd=True)

    @property
    def enhance_cost(self) -> int:
        return self.credits.premium_ai_cost(hd=False, enhance=True)


def _coerce(raw: object) -> Any:
    """jsonb comes back from asyncpg as a str; a stored SQL null and a stored
    JSON null both mean "use the code default"."""
    if raw is None:
        return None
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw
    return raw


def _int_or(value: Any, fallback: int) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return fallback
    return int(value)


def _capped(value: int, *, key: str) -> int:
    """Clamp a render price to [0, MAX_APP_CREDITS_PER_RENDER].

    One tap is one credit, and that promise cannot be allowed to depend on a row
    in `monetization_config` that no test reads and no diff shows. An operator
    may still make a render CHEAPER (free promotions, a zero-cost experiment);
    they simply cannot make it cost more than the product says it does.

    Logged loudly rather than silently, because a clamped config value means
    somebody wrote a price expecting it to take effect.
    """
    if value > MAX_APP_CREDITS_PER_RENDER:
        log.warning(
            "monetization: %s=%d exceeds the %d-credit cap and was clamped",
            key,
            value,
            MAX_APP_CREDITS_PER_RENDER,
        )
        return MAX_APP_CREDITS_PER_RENDER
    return max(0, value)


async def load_config(conn: asyncpg.Connection) -> dict[str, Any]:
    """Every `monetization_config` row as {key: python value}. An empty table
    (a database that has not run 0076 yet) yields {}, and every consumer below
    falls back to its code default — so this can never break a deploy order."""
    try:
        rows = await conn.fetch("select key, value from public.monetization_config")
    except asyncpg.UndefinedTableError:
        log.info("monetization_config missing; using code defaults")
        return {}
    return {r["key"]: _coerce(r["value"]) for r in rows}


def build_credit_policy(config: dict[str, Any], *, v2: bool) -> CreditPolicy:
    """The cost table for this request. `v2` is the flag; the config can still
    override individual numbers in either mode."""
    enhance = _capped(
        _int_or(config.get("render_cost_enhance"), AI_ENHANCE_COST), key="render_cost_enhance"
    )
    if v2:
        # The v2 tiers were written when a render could cost 2-5. They are kept
        # so the table and its tests still exist, but every one of them is now
        # clamped: quality is what the person chose, not a price ladder.
        costs = {k: _capped(v, key=f"v2:{k}") for k, v in _V2_COSTS.items()}
        costs["standard"] = _capped(
            _int_or(config.get("render_cost_standard"), costs["standard"]),
            key="render_cost_standard",
        )
        costs["hd"] = _capped(
            _int_or(config.get("render_cost_hd"), costs["hd"]), key="render_cost_hd"
        )
        return TieredCreditPolicy(costs=costs, enhance=enhance)
    return LegacyCreditPolicy(
        standard=_capped(
            _int_or(config.get("render_cost_standard"), STD_COST), key="render_cost_standard"
        ),
        hd=_capped(_int_or(config.get("render_cost_hd"), HD_COST), key="render_cost_hd"),
        enhance=enhance,
    )


async def load_flags(conn: asyncpg.Connection, keys: tuple[str, ...]) -> dict[str, bool]:
    """Read several flags in ONE round trip.

    `core.flags.flag_enabled` reads a single key, which is right for a
    kill-switch checked once per request. This policy needs three at once and
    sits on `/v1/credits` — a hot endpoint — so three separate queries would be
    three round trips per credit read. A key with no row is absent from the
    result and the caller applies its own default, exactly as before.
    """
    try:
        rows = await conn.fetch(
            "select key, enabled from public.feature_flags where key = any($1::text[])",
            list(keys),
        )
    except asyncpg.UndefinedTableError:  # pragma: no cover - defensive
        return {}
    return {r["key"]: bool(r["enabled"]) for r in rows}


async def get_experiments(conn: asyncpg.Connection, user_id: str) -> dict[str, str]:
    """This user's stable experiment assignments. Read-only: nothing here
    assigns, so simply loading a policy can never enrol anybody (§37)."""
    try:
        rows = await conn.fetch(
            "select experiment, variant from public.experiment_assignments "
            "where user_id = $1::uuid",
            user_id,
        )
    except asyncpg.UndefinedTableError:
        return {}
    return {r["experiment"]: r["variant"] for r in rows}


async def get_policy(conn: asyncpg.Connection, user_id: str) -> MonetizationPolicy:
    """Compose the policy in force for `user_id` right now.

    Every fallback is today's production value, so a database with no config
    rows, no flags and no assignments produces exactly current behaviour.
    """
    settings = get_settings()
    config = await load_config(conn)
    flags = await load_flags(conn, (FLAG_CREDIT_ECONOMICS_V2, FLAG_RENDER_GATE_V2, FLAG_PAYWALL_V2))
    economics_v2 = flags.get(FLAG_CREDIT_ECONOMICS_V2, False)
    gate_v2 = flags.get(FLAG_RENDER_GATE_V2, False)
    paywall_v2 = flags.get(FLAG_PAYWALL_V2, False)
    experiments = await get_experiments(conn, user_id)

    # The free allowance moves ONLY when the gate flag is on AND a limit is
    # configured. Two independent conditions on purpose: shipping the flag and
    # choosing the number are separate decisions, and either one alone must be
    # a no-op (§53).
    free_limit = settings.free_tryon_trial_credits
    if gate_v2:
        configured = config.get("free_render_lifetime_limit")
        variant = experiments.get("free_allowance")
        if variant in ("v2", "v3"):
            # The 2-vs-3 lifetime experiment (§9). `control` deliberately has no
            # branch here — it keeps the deployed setting.
            free_limit = 2 if variant == "v2" else 3
        elif configured is not None:
            free_limit = _int_or(configured, free_limit)
        free_limit = max(0, free_limit)

    return MonetizationPolicy(
        credits=build_credit_policy(config, v2=economics_v2),
        free_render_limit=free_limit,
        paywall_cooldown_hours=_int_or(config.get("paywall_cooldown_hours"), 24),
        post_purchase_cooldown_hours=_int_or(
            config.get("paywall_post_purchase_cooldown_hours"), 72
        ),
        paywall_timing_variant=str(config.get("paywall_timing_variant") or "control"),
        trial_enabled=bool(config.get("trial_enabled") or False),
        trial_credit_cap=(
            _int_or(config["trial_credit_cap"], 0)
            if config.get("trial_credit_cap") is not None
            else None
        ),
        rollover_enabled=bool(config.get("rollover_enabled") or False),
        rollover_cap_multiplier=_int_or(config.get("rollover_cap_multiplier"), 1),
        quality_recovery_limit_30d=_int_or(config.get("quality_recovery_limit_30d"), 1),
        push_frequency_cap_7d=_int_or(config.get("push_frequency_cap_7d"), 2),
        paywall_v2=paywall_v2,
        render_gate_v2=gate_v2,
        experiments=experiments,
    )


# ── paywall pressure (§10) ───────────────────────────────────────────────────


async def record_monetization_event(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    surface: str,
    action: str,
    interruptive: bool = False,
    context: dict[str, Any] | None = None,
) -> None:
    """Append to the pressure ledger. Best-effort: a monetization surface must
    never fail to render because its bookkeeping row could not be written."""
    try:
        await conn.execute(
            """
            insert into public.monetization_events
              (user_id, surface, action, interruptive, context)
            values ($1::uuid, $2, $3, $4, $5::jsonb)
            """,
            user_id,
            surface,
            action,
            interruptive,
            json.dumps(context or {}),
        )
    except Exception as exc:  # pragma: no cover - defensive
        log.warning("monetization event not recorded for %s: %s", user_id, exc)


@dataclass(frozen=True)
class PressureVerdict:
    """May we interrupt this user with a monetization surface right now?"""

    allowed: bool
    #: Machine-readable reason when not allowed, for analytics and for tests.
    reason: str | None = None
    retry_after_hours: int | None = None


async def may_interrupt(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    policy: MonetizationPolicy,
    tier: str,
    has_credits: bool,
) -> PressureVerdict:
    """The single gate every INTERRUPTIVE monetization surface must pass (§10).

    A surface the user opened themselves — tapping Upgrade, tapping a locked
    feature, running out mid-action — does NOT call this and is never blocked.
    This governs only the surfaces WTM decides to raise on its own.

    The rules, in the order they are checked:

      1. A subscriber who can still render is never interrupted to upgrade.
      2. Any purchase (pack or subscription) buys a quiet period.
      3. A dismissal buys a cooldown — dismissing is an answer, and asking
         again an hour later is not asking, it is nagging.
    """
    if tier != "free" and has_credits:
        return PressureVerdict(False, "subscriber_with_credits")

    row = await conn.fetchrow(
        """
        select
          max(created_at) filter (where action = 'purchased')            as purchased_at,
          max(created_at) filter (where action = 'dismissed'
                                    and interruptive)                    as dismissed_at,
          max(created_at) filter (where action = 'viewed'
                                    and interruptive)                    as shown_at
          from public.monetization_events
         where user_id = $1::uuid
           and created_at > now() - interval '30 days'
        """,
        user_id,
    )
    if row is None:
        return PressureVerdict(True)

    now_hours = "extract(epoch from (now() - $1::timestamptz)) / 3600"

    async def _hours_since(value: object) -> float | None:
        if value is None:
            return None
        return float(await conn.fetchval(f"select {now_hours}", value))

    since_purchase = await _hours_since(row["purchased_at"])
    if since_purchase is not None and since_purchase < policy.post_purchase_cooldown_hours:
        return PressureVerdict(
            False,
            "post_purchase_cooldown",
            int(policy.post_purchase_cooldown_hours - since_purchase) + 1,
        )

    for key, reason in (("dismissed_at", "dismiss_cooldown"), ("shown_at", "impression_cooldown")):
        since = await _hours_since(row[key])
        if since is not None and since < policy.paywall_cooldown_hours:
            return PressureVerdict(False, reason, int(policy.paywall_cooldown_hours - since) + 1)

    return PressureVerdict(True)
