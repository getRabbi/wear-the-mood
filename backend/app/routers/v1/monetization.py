"""Monetization configuration + pressure ledger (spec §10, §39, Phase 6).

`GET /v1/monetization/config` is the additive snapshot endpoint §39 asks for: it
tells the app what a render costs, how many free renders remain, which plans to
present, and whether an interruptive paywall is allowed right now.

Two things this endpoint is NOT:

  * It is not an authority the app can ignore for its own benefit. Costs are
    still charged, and gates still enforced, server-side (`core.credits`,
    `core.monetization`). This response exists so the UI can be honest, not so
    the client can decide.
  * It is not a pricing change. With the configuration seeded by migration 0076
    — every render/allowance key `null` — the numbers returned here are exactly
    today's: 1 credit standard, 4 HD, 4 enhance, 3 lifetime free renders, and
    `public.plans` verbatim for tiers and allowances (§53).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends

from app.core.credits import get_credits
from app.core.db import get_pool
from app.core.monetization import get_policy, may_interrupt, record_monetization_event
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.monetization import (
    MonetizationConfig,
    MonetizationEventIn,
    PaywallPolicy,
    PlanPresentation,
    RenderCosts,
)
from app.services.billing import user_plan

log = logging.getLogger("fashionos.monetization")

router = APIRouter(tags=["monetization"])


@router.get("/monetization/config", response_model=MonetizationConfig)
async def get_monetization_config(
    user: CurrentUser = Depends(get_current_user),
) -> MonetizationConfig:
    """The policy snapshot in force for this user right now."""
    async with get_pool().acquire() as conn:
        policy = await get_policy(conn, user.id)
        plan = await user_plan(conn, user.id)
        state = await get_credits(conn, user.id)
        rows = await conn.fetch(
            "select tier, kind, price_usd, monthly_credits, hd_allowed, priority, "
            "play_product_id, app_product_id from public.plans "
            "where active order by price_usd"
        )
        verdict = await may_interrupt(
            conn,
            user.id,
            policy=policy,
            tier=plan.tier,
            has_credits=state.total_available >= policy.std_cost,
        )

    # The free bucket is what the user has actually consumed; the limit is what
    # policy says it should be. When an experiment lowers the limit below what a
    # user already spent, remaining clamps at zero rather than going negative —
    # nobody is ever billed backwards for a change of policy.
    remaining = max(0, policy.free_render_limit - state.daily_free_used)

    return MonetizationConfig(
        render_costs=RenderCosts(
            standard=policy.std_cost, hd=policy.hd_cost, enhance=policy.enhance_cost
        ),
        free_render_limit=policy.free_render_limit,
        free_render_remaining=remaining,
        tier=plan.tier,
        hd_allowed=plan.hd_allowed,
        plans=[
            PlanPresentation(
                tier=r["tier"],
                kind=r["kind"],
                price_usd=float(r["price_usd"]),
                monthly_credits=r["monthly_credits"],
                hd_allowed=r["hd_allowed"],
                priority=r["priority"],
                play_product_id=r["play_product_id"],
                app_product_id=r["app_product_id"],
            )
            for r in rows
        ],
        paywall=PaywallPolicy(
            cooldown_hours=policy.paywall_cooldown_hours,
            post_purchase_cooldown_hours=policy.post_purchase_cooldown_hours,
            timing_variant=policy.paywall_timing_variant,
            may_interrupt=verdict.allowed,
            block_reason=verdict.reason,
            retry_after_hours=verdict.retry_after_hours,
        ),
        trial_enabled=policy.trial_enabled,
        trial_credit_cap=policy.trial_credit_cap,
        rollover_enabled=policy.rollover_enabled,
        experiments=policy.experiments,
        paywall_v2=policy.paywall_v2,
        render_gate_v2=policy.render_gate_v2,
    )


@router.post("/monetization/events", status_code=202)
async def post_monetization_event(
    body: MonetizationEventIn,
    user: CurrentUser = Depends(get_current_user),
) -> dict[str, bool]:
    """Record that a monetization surface was shown, dismissed or acted on.

    This is what makes the cooldown in §10 work across screens: one ledger every
    surface writes to, instead of a private timestamp per widget that no other
    screen can see. Fire-and-forget for the client (202) — a paywall must never
    fail to open because its bookkeeping did.
    """
    async with get_pool().acquire() as conn:
        await record_monetization_event(
            conn,
            user.id,
            surface=body.surface,
            action=body.action,
            interruptive=body.interruptive,
            context=body.context,
        )
    return {"recorded": True}
