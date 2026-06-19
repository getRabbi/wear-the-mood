"""Credit balance + free-trial quota reads (CLAUDE.md §12, §18).

The free tier grants a small ONE-TIME trial of AI try-on credits (total, not
per-day), enforced server-side: `daily_free_used` counts lifetime trial try-ons
and is capped at `free_tryon_trial_credits`. After the trial is spent a free user
hits the paywall; Premium covers AI try-ons without spending credits. There is no
daily reset. (The wire/DB fields keep the historical `daily_free_*` names so the
shipped client contract is unchanged — CLAUDE.md §13.)

The backend connects with the service-role DSN (bypasses RLS), so every query is
scoped strictly by the JWT-derived `user_id` (CLAUDE.md §11).
"""

from __future__ import annotations

from dataclasses import dataclass

import asyncpg

from app.core.config import get_settings
from app.core.errors import ApiError
from app.models.common import ErrorCode


class InsufficientCreditsError(ApiError):
    """Raised when neither the daily free bucket nor the paid balance can cover a
    spend (CLAUDE.md §12). Maps to the INSUFFICIENT_CREDITS code (§13)."""

    def __init__(self) -> None:
        super().__init__(ErrorCode.INSUFFICIENT_CREDITS, "Not enough credits.", 402)


@dataclass(frozen=True)
class CreditsState:
    balance: int
    daily_free_used: int  # lifetime free-trial try-ons used (one-time, no reset)
    daily_free_limit: int  # = free_tryon_trial_credits

    @property
    def daily_free_remaining(self) -> int:
        # Never negative even if the limit was lowered after credits were spent.
        return max(0, self.daily_free_limit - self.daily_free_used)


def has_credit(state: CreditsState) -> bool:
    """Pre-flight gate (e.g. before enqueuing a try-on job): is anything spendable?

    Note: this is a check, not a hold — between the gate and the actual spend a
    user could in theory race extra jobs through. The small daily bucket bounds
    the blast radius; a proper reservation can come later (CLAUDE.md §7, §12)."""
    return state.daily_free_remaining > 0 or state.balance > 0


def _plan_spend(
    *, balance: int, free_used: int, free_limit: int, cost: int
) -> tuple[int, int, str] | None:
    """Pure spend decision: free bucket first, then paid balance. Returns the
    new (balance, free_used, source) or None when nothing can cover `cost`."""
    free_remaining = max(0, free_limit - free_used)
    if free_remaining >= cost:
        return balance, free_used + cost, "free"
    if balance >= cost:
        return balance - cost, free_used, "paid"
    return None


async def get_credits(conn: asyncpg.Connection, user_id: str) -> CreditsState:
    """Return the user's credit state. The free AI try-on grant is a ONE-TIME
    trial — `daily_free_used` is lifetime usage, never reset."""
    # Defensive provision — the signup trigger normally creates this row, but
    # ON CONFLICT DO NOTHING keeps reads safe for any pre-trigger accounts.
    await conn.execute(
        "insert into public.credits (user_id) values ($1::uuid) "
        "on conflict (user_id) do nothing",
        user_id,
    )
    row = await conn.fetchrow(
        "select balance, daily_free_used from public.credits where user_id = $1::uuid",
        user_id,
    )

    assert row is not None  # provisioned above, so the row always exists
    return CreditsState(
        balance=row["balance"],
        daily_free_used=row["daily_free_used"],
        daily_free_limit=get_settings().free_tryon_trial_credits,
    )


async def spend_credit(conn: asyncpg.Connection, user_id: str, *, cost: int = 1) -> CreditsState:
    """Atomically charge `cost` credits, free bucket first then paid balance, and
    return the resulting state. Raises InsufficientCreditsError if uncovered.

    Call this ONLY after the paid work succeeded — never charge on failure
    (CLAUDE.md §7). The row is locked FOR UPDATE so concurrent spends can't race.
    """
    limit = get_settings().free_tryon_trial_credits
    async with conn.transaction():
        await conn.execute(
            "insert into public.credits (user_id) values ($1::uuid) "
            "on conflict (user_id) do nothing",
            user_id,
        )
        row = await conn.fetchrow(
            """
            select balance, daily_free_used
              from public.credits
             where user_id = $1::uuid
               for update
            """,
            user_id,
        )
        assert row is not None  # provisioned above

        # One-time trial: daily_free_used is lifetime usage (no reset).
        plan = _plan_spend(
            balance=row["balance"],
            free_used=row["daily_free_used"],
            free_limit=limit,
            cost=cost,
        )
        if plan is None:
            raise InsufficientCreditsError()
        new_balance, new_free_used, _source = plan

        await conn.execute(
            """
            update public.credits
               set balance = $2, daily_free_used = $3
             where user_id = $1::uuid
            """,
            user_id,
            new_balance,
            new_free_used,
        )

    return CreditsState(balance=new_balance, daily_free_used=new_free_used, daily_free_limit=limit)
