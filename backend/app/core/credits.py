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


@dataclass(frozen=True)
class CreditsState:
    balance: int
    daily_free_used: int
    daily_free_limit: int

    @property
    def daily_free_remaining(self) -> int:
        # Never negative even if the limit was lowered after credits were spent.
        return max(0, self.daily_free_limit - self.daily_free_used)


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
