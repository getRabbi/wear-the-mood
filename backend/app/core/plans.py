"""Subscription plan config (Pro / Pro Max + top-ups) — read from the `plans`
table so allowances (monthly_credits, hd_allowed) are DATA, never hardcoded
(§18, decision: credits come from plans.monthly_credits). The backend connects
service-role, so reads bypass RLS.
"""

from __future__ import annotations

from dataclasses import dataclass

import asyncpg

# ── ONE app credit per user-visible render. The ceiling, not a default. ──────
#
# A person taps once and expects to be charged once. What it took to satisfy that
# tap — HD, six garments chained through six provider calls, a fallback model
# after the first one failed, a worker that restarted halfway — is OUR production
# cost, not a second thing to bill them for. The previous prices (HD = 4, AI
# Enhance = 4) leaked the provider's cost structure onto the user, so the same
# button charged 1 or 4 depending on a toggle most people would not connect to
# the number.
#
# This is a CAP and it is enforced in three places, deliberately overlapping:
#   1. here, as the compiled default for every action;
#   2. `core.monetization.build_credit_policy`, which clamps anything an operator
#      or an experiment puts in `monetization_config` (a DB row must not be able
#      to outprice the promise);
#   3. `core.credits.spend_credit`, which refuses to debit more than this no
#      matter what number reaches it — the backstop that survives a future caller
#      nobody has written yet.
#
# Provider credits are a separate currency and are unaffected: FASHN may bill us
# 1, 2 or 5 of its own credits for one of these, and that is a COGS line.
MAX_APP_CREDITS_PER_RENDER = 1

# Credit cost of one AI try-on, standard or HD. Both are one app credit; HD stays
# an entitlement (Pro Max only) rather than a price.
STD_COST = 1
HD_COST = MAX_APP_CREDITS_PER_RENDER

# In-app credit cost of one AI Enhance Item. A premium, higher-quality render
# (FASHN Edit at balanced·1k = 2 EXTERNAL FASHN credits/result — see
# `services/tryon/fashn._GEN_BUDGET`), and still ONE app credit: the external
# cost is ours to carry. This remains the single source of truth for the in-app
# price; `/v1/credits` (`enhance_cost`) surfaces it so backend and app cannot
# drift.
AI_ENHANCE_COST = MAX_APP_CREDITS_PER_RENDER

_COLS = "tier, kind, monthly_credits, hd_allowed, priority"


@dataclass(frozen=True)
class Plan:
    tier: str
    kind: str
    monthly_credits: int
    hd_allowed: bool
    priority: bool


# The implicit plan for a user with no active subscription. monthly_credits 0 —
# free users get the one-time trial (credits.daily_free_*), not plan credits.
FREE_PLAN = Plan(
    tier="free", kind="subscription", monthly_credits=0, hd_allowed=False, priority=False
)


def _from_row(row: asyncpg.Record) -> Plan:
    return Plan(
        tier=row["tier"],
        kind=row["kind"],
        monthly_credits=row["monthly_credits"],
        hd_allowed=row["hd_allowed"],
        priority=row["priority"],
    )


async def get_plan(conn: asyncpg.Connection, tier: str) -> Plan:
    """The plan for `tier`; FREE_PLAN when the tier is unknown/'free'."""
    row = await conn.fetchrow(f"select {_COLS} from public.plans where tier = $1", tier)
    return _from_row(row) if row is not None else FREE_PLAN


async def plan_for_product(conn: asyncpg.Connection, product_id: str) -> Plan | None:
    """Map a store product id (Play or App Store) to its plan, or None if unknown.

    Store-format agnostic. Google Play sends a subscription's product id as
    ``"<subscription_id>:<base_plan_id>"`` (e.g. ``"pro_monthly:monthly"``) while
    the `plans` seed stores the bare subscription id (``"pro_monthly"``). We try
    the id EXACTLY as received first — so a bare id (``topup_40``, an App Store
    id, or a seed that already carries the colon form) matches directly — then
    fall back to the part before ``:`` for the Play base-plan case. App Store
    product ids never contain ``:``, so iOS mappings are unaffected (§18)."""
    if not product_id:
        return None
    row = await conn.fetchrow(
        f"select {_COLS} from public.plans where play_product_id = $1 or app_product_id = $1",
        product_id,
    )
    if row is None and ":" in product_id:
        base = product_id.split(":", 1)[0]
        row = await conn.fetchrow(
            f"select {_COLS} from public.plans where play_product_id = $1 or app_product_id = $1",
            base,
        )
    return _from_row(row) if row is not None else None
