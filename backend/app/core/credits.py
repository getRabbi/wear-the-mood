"""Credit balance + daily free-quota reads (CLAUDE.md §12).

The free tier grants a small daily bucket of try-on credits, enforced
server-side. The daily counter resets lazily: the first read on a new calendar
day (DB clock — Supabase runs UTC) zeroes `daily_free_used`, so there is no cron
needed for the reset.

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
    daily_free_used: int
    daily_free_limit: int

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
    """Return the user's credit state, lazily resetting the daily free counter
    when the stored reset date has rolled over."""
    async with conn.transaction():
        # Defensive provision — the signup trigger normally creates this row, but
        # ON CONFLICT DO NOTHING keeps reads safe for any pre-trigger accounts and
        # is a no-op (no updated_at bump) on the common path.
        await conn.execute(
            "insert into public.credits (user_id) values ($1::uuid) "
            "on conflict (user_id) do nothing",
            user_id,
        )
        # Lazy daily reset — writes at most once per calendar day.
        await conn.execute(
            """
            update public.credits
               set daily_free_used = 0,
                   daily_reset_on  = current_date
             where user_id = $1::uuid
               and daily_reset_on < current_date
            """,
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
        daily_free_limit=get_settings().free_daily_tryon_credits,
    )


async def spend_credit(conn: asyncpg.Connection, user_id: str, *, cost: int = 1) -> CreditsState:
    """Atomically charge `cost` credits, free bucket first then paid balance, and
    return the resulting state. Raises InsufficientCreditsError if uncovered.

    Call this ONLY after the paid work succeeded — never charge on failure
    (CLAUDE.md §7). The row is locked FOR UPDATE so concurrent spends can't race.
    """
    limit = get_settings().free_daily_tryon_credits
    async with conn.transaction():
        await conn.execute(
            "insert into public.credits (user_id) values ($1::uuid) "
            "on conflict (user_id) do nothing",
            user_id,
        )
        row = await conn.fetchrow(
            """
            select balance, daily_free_used, daily_reset_on, current_date as today
              from public.credits
             where user_id = $1::uuid
               for update
            """,
            user_id,
        )
        assert row is not None  # provisioned above

        # Apply the lazy daily reset (DB clock) before deciding the spend.
        free_used = 0 if row["daily_reset_on"] < row["today"] else row["daily_free_used"]

        plan = _plan_spend(balance=row["balance"], free_used=free_used, free_limit=limit, cost=cost)
        if plan is None:
            raise InsufficientCreditsError()
        new_balance, new_free_used, _source = plan

        await conn.execute(
            """
            update public.credits
               set balance = $2, daily_free_used = $3, daily_reset_on = $4
             where user_id = $1::uuid
            """,
            user_id,
            new_balance,
            new_free_used,
            row["today"],
        )

    return CreditsState(balance=new_balance, daily_free_used=new_free_used, daily_free_limit=limit)
