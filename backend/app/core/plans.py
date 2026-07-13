"""Subscription plan config (Pro / Pro Max + top-ups) — read from the `plans`
table so allowances (monthly_credits, hd_allowed) are DATA, never hardcoded
(§18, decision: credits come from plans.monthly_credits). The backend connects
service-role, so reads bypass RLS.
"""

from __future__ import annotations

from dataclasses import dataclass

import asyncpg

# Credit cost of one AI try-on. Standard = 1 (1 FASHN credit, $0.075); HD /
# Try-On Max = 4. Cost is hard-capped here — no path may exceed it.
STD_COST = 1
HD_COST = 4

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
    row = await conn.fetchrow(
        f"select {_COLS} from public.plans where tier = $1", tier
    )
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
        f"select {_COLS} from public.plans "
        "where play_product_id = $1 or app_product_id = $1",
        product_id,
    )
    if row is None and ":" in product_id:
        base = product_id.split(":", 1)[0]
        row = await conn.fetchrow(
            f"select {_COLS} from public.plans "
            "where play_product_id = $1 or app_product_id = $1",
            base,
        )
    return _from_row(row) if row is not None else None
