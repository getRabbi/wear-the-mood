"""Credit balance, metered spend, and grants (CLAUDE.md §12, §18).

Three buckets, spent in this order:
  1. free trial  — one-time `free_tryon_trial_credits` (lifetime; `daily_free_used`).
  2. plan balance — `credits.balance`, granted monthly per the user's plan, RESET
     (no rollover) on renewal.
  3. top-up       — `credits.topup_balance`, paid one-off packs that SURVIVE the reset.

Every mutation writes an immutable `credit_transactions` row. Spends are idempotent
on the try-on job id (a re-processed job never double-charges). Grants go through
the DB primitive `app_grant_credits` (idempotent on its ref). The backend connects
service-role (bypasses RLS), so every query is scoped by the JWT user_id (§11).
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import asyncpg

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.plans import HD_COST, STD_COST, Plan
from app.models.common import ErrorCode


class InsufficientCreditsError(ApiError):
    """Raised when no bucket can cover a spend (§12). Maps to INSUFFICIENT_CREDITS."""

    def __init__(self) -> None:
        super().__init__(ErrorCode.INSUFFICIENT_CREDITS, "Not enough credits.", 402)


@dataclass(frozen=True)
class CreditsState:
    balance: int  # plan credits (reset monthly, no rollover)
    daily_free_used: int  # lifetime free-trial try-ons used (one-time, no reset)
    daily_free_limit: int  # = free_tryon_trial_credits
    topup_balance: int = 0  # paid top-up credits (survive the monthly reset)

    @property
    def daily_free_remaining(self) -> int:
        return max(0, self.daily_free_limit - self.daily_free_used)

    @property
    def total_available(self) -> int:
        return self.daily_free_remaining + self.balance + self.topup_balance


def has_credit(state: CreditsState, cost: int = STD_COST) -> bool:
    """Pre-flight gate: can the three buckets together cover `cost`? (A check, not
    a hold — `spend_credit` does the authoritative atomic reserve under a row
    lock, §7/§12.)"""
    return state.total_available >= cost


def authorize_tryon(*, hd: bool, plan: Plan, state: CreditsState) -> int:
    """Pure policy gate for an AI try-on (CLAUDE.md §18). Returns the credit cost
    (1 standard / 4 HD) or raises ApiError. Rules:

      * HD / Try-On Max is a SUBSCRIBER feature — allowed only on a plan with
        `hd_allowed` (Pro OR Pro Max). A free user is blocked with HD_LOCKED even
        if they hold enough top-up credits.
      * Otherwise the user just needs to cover the cost from any bucket.

    This is the fast pre-check that rejects BEFORE any provider call (§7); the
    atomic reserve (`spend_credit`) re-checks under a row lock when the job is
    created, so this can never let an under-funded job through."""
    cost = HD_COST if hd else STD_COST
    if hd and not plan.hd_allowed:
        raise ApiError(
            ErrorCode.HD_LOCKED, "Upgrade to Pro or Pro Max for HD.", 403
        )
    if not has_credit(state, cost):
        message = (
            f"You need {HD_COST} credits for HD."
            if hd
            else "You're out of AI credits. Upgrade or top up to keep generating."
        )
        raise ApiError(ErrorCode.PAYWALL, message, 402)
    return cost


def _draw(
    *, free_remaining: int, balance: int, topup: int, cost: int
) -> tuple[int, int, int] | None:
    """Pure spend plan: how much to take from free → balance → top-up to cover
    `cost`, or None when the three together can't. Returns (take_free, take_bal, take_top)."""
    if free_remaining + balance + topup < cost:
        return None
    remaining = cost
    take_free = min(free_remaining, remaining)
    remaining -= take_free
    take_bal = min(balance, remaining)
    remaining -= take_bal
    take_top = min(topup, remaining)
    return take_free, take_bal, take_top


async def get_credits(conn: asyncpg.Connection, user_id: str) -> CreditsState:
    """The user's current credit state across all three buckets."""
    await conn.execute(
        "insert into public.credits (user_id) values ($1::uuid) "
        "on conflict (user_id) do nothing",
        user_id,
    )
    row = await conn.fetchrow(
        "select balance, daily_free_used, topup_balance "
        "from public.credits where user_id = $1::uuid",
        user_id,
    )
    assert row is not None  # provisioned above
    return CreditsState(
        balance=row["balance"],
        daily_free_used=row["daily_free_used"],
        topup_balance=row["topup_balance"],
        daily_free_limit=get_settings().free_tryon_trial_credits,
    )


async def spend_credit(
    conn: asyncpg.Connection, user_id: str, *, cost: int = STD_COST, ref: str
) -> CreditsState:
    """Atomically charge `cost` credits (free trial → plan balance → top-up), write
    the ledger row (recording the per-bucket split in `meta` so a refund can
    reverse the EXACT buckets), and return the resulting state. **Idempotent on
    `ref`** (the try-on job id): a repeated reserve returns the current state
    without charging again. Raises InsufficientCreditsError if uncovered.

    Called as the RESERVE when a try-on job is created (§7/§12): the row lock
    means two concurrent submits can never both pass and the balance can never go
    negative. A job that ultimately fails is reversed by `refund_credit`.
    """
    limit = get_settings().free_tryon_trial_credits
    async with conn.transaction():
        await conn.execute(
            "insert into public.credits (user_id) values ($1::uuid) "
            "on conflict (user_id) do nothing",
            user_id,
        )
        row = await conn.fetchrow(
            "select balance, daily_free_used, topup_balance "
            "from public.credits where user_id = $1::uuid for update",
            user_id,
        )
        assert row is not None
        state = CreditsState(
            balance=row["balance"],
            daily_free_used=row["daily_free_used"],
            topup_balance=row["topup_balance"],
            daily_free_limit=limit,
        )
        # Idempotency: this job already charged → no-op, return current state.
        already = await conn.fetchval(
            "select 1 from public.credit_transactions "
            "where user_id = $1::uuid and ref = $2",
            user_id,
            ref,
        )
        if already:
            return state

        plan = _draw(
            free_remaining=state.daily_free_remaining,
            balance=state.balance,
            topup=state.topup_balance,
            cost=cost,
        )
        if plan is None:
            raise InsufficientCreditsError()
        take_free, take_bal, take_top = plan
        new_free_used = state.daily_free_used + take_free
        new_balance = state.balance - take_bal
        new_topup = state.topup_balance - take_top

        await conn.execute(
            "update public.credits set balance = $2, daily_free_used = $3, "
            "topup_balance = $4, updated_at = now() where user_id = $1::uuid",
            user_id,
            new_balance,
            new_free_used,
            new_topup,
        )
        await conn.execute(
            "insert into public.credit_transactions "
            "(user_id, delta, reason, balance_after, ref, tryon_job_id, meta) "
            "values ($1::uuid, $2, 'spend', $3, $4, $5::uuid, $6::jsonb)",
            user_id,
            -cost,
            new_balance + new_topup,
            ref,
            ref,
            json.dumps({"free": take_free, "balance": take_bal, "topup": take_top}),
        )
        return CreditsState(
            balance=new_balance,
            daily_free_used=new_free_used,
            topup_balance=new_topup,
            daily_free_limit=limit,
        )


async def refund_credit(conn: asyncpg.Connection, user_id: str, *, ref: str) -> bool:
    """Reverse a reserved spend when its try-on job ultimately FAILS (§7). Reads
    the original spend's per-bucket split (`credit_transactions.meta`) and restores
    those EXACT buckets, so the refund is perfectly neutral (no free→paid
    laundering). **Idempotent**: a no-op returning False when there is no spend to
    reverse (e.g. a legacy job created before reserve-at-submit) or it was already
    refunded. Row-locked FOR UPDATE.
    """
    refund_ref = f"refund:{ref}"
    async with conn.transaction():
        spend = await conn.fetchrow(
            "select delta, meta from public.credit_transactions "
            "where user_id = $1::uuid and ref = $2 and reason = 'spend'",
            user_id,
            ref,
        )
        if spend is None:
            return False  # nothing was reserved for this job → nothing to refund
        already = await conn.fetchval(
            "select 1 from public.credit_transactions "
            "where user_id = $1::uuid and ref = $2",
            user_id,
            refund_ref,
        )
        if already:
            return False  # already refunded

        raw = spend["meta"]
        meta = json.loads(raw) if isinstance(raw, str) else (raw or {})
        take_free = int(meta.get("free", 0))
        take_bal = int(meta.get("balance", 0))
        take_top = int(meta.get("topup", 0))
        if take_free + take_bal + take_top == 0:
            # Defensive: a pre-split (legacy) spend row with no recorded buckets.
            # Reverse the recorded magnitude into top-up (survives the monthly
            # reset; never makes the user worse off).
            take_top = -int(spend["delta"])

        row = await conn.fetchrow(
            "select balance, daily_free_used, topup_balance "
            "from public.credits where user_id = $1::uuid for update",
            user_id,
        )
        assert row is not None
        new_free_used = max(0, row["daily_free_used"] - take_free)
        new_balance = row["balance"] + take_bal
        new_topup = row["topup_balance"] + take_top
        amount = take_free + take_bal + take_top

        await conn.execute(
            "update public.credits set balance = $2, daily_free_used = $3, "
            "topup_balance = $4, updated_at = now() where user_id = $1::uuid",
            user_id,
            new_balance,
            new_free_used,
            new_topup,
        )
        await conn.execute(
            "insert into public.credit_transactions "
            "(user_id, delta, reason, balance_after, ref, tryon_job_id, meta) "
            "values ($1::uuid, $2, 'refund', $3, $4, $5::uuid, $6::jsonb)",
            user_id,
            amount,
            new_balance + new_topup,
            refund_ref,
            ref,
            json.dumps({"free": take_free, "balance": take_bal, "topup": take_top}),
        )
        return True


async def grant_credits(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    amount: int,
    reason: str,
    ref: str,
    set_plan_balance: bool = False,
    target: str = "plan",
) -> bool:
    """Idempotent credit grant via the DB primitive `app_grant_credits`
    (webhook / reset cron / migration). `set_plan_balance=True` resets the plan
    balance (no rollover); `target='topup'` adds to the top-up bucket. Returns
    True if applied, False if `ref` was already granted."""
    return await conn.fetchval(
        "select public.app_grant_credits($1::uuid, $2, $3, $4, $5, $6)",
        user_id,
        amount,
        reason,
        ref,
        set_plan_balance,
        target,
    )
