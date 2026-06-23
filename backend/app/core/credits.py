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

from dataclasses import dataclass

import asyncpg

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.plans import STD_COST
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
    a hold — the worker does the authoritative atomic spend on success, §7/§12.)"""
    return state.total_available >= cost


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
    the ledger row, and return the resulting state. **Idempotent on `ref`** (the
    try-on job id): a re-processed job returns the current state without charging
    again. Raises InsufficientCreditsError if uncovered. Call ONLY after the paid
    work succeeded — never charge on failure (§7). Row-locked FOR UPDATE.
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
            "(user_id, delta, reason, balance_after, ref, tryon_job_id) "
            "values ($1::uuid, $2, 'spend', $3, $4, $5::uuid)",
            user_id,
            -cost,
            new_balance + new_topup,
            ref,
            ref,
        )
        return CreditsState(
            balance=new_balance,
            daily_free_used=new_free_used,
            topup_balance=new_topup,
            daily_free_limit=limit,
        )


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
