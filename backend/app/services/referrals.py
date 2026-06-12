"""Referral loop (CLAUDE.md §24) — codes, redemption, rewards.

Each user has a unique referral_code. A new user redeems someone's code once;
both sides are granted bonus credits. All of it is server-verified — the client
never grants credits and can't redeem twice or use its own code (§11, §25).
"""

from __future__ import annotations

import logging
import secrets

import asyncpg

from app.core.errors import ApiError
from app.models.common import ErrorCode

log = logging.getLogger("fashionos.referrals")

# Unambiguous alphabet (no 0/O/1/I) so codes are easy to read/share.
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LEN = 8

_GRANT = """
    insert into public.credits (user_id, balance) values ($1::uuid, $2)
    on conflict (user_id) do update
      set balance = public.credits.balance + excluded.balance, updated_at = now()
"""


def gen_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(_CODE_LEN))


async def get_or_create_code(conn: asyncpg.Connection, user_id: str) -> str:
    """The user's referral code, generated + persisted on first request. Retries
    on the rare code collision."""
    existing = await conn.fetchval(
        "select referral_code from public.profiles where id = $1::uuid", user_id
    )
    if existing:
        return existing
    for _ in range(5):
        code = gen_code()
        try:
            updated = await conn.fetchval(
                "update public.profiles set referral_code = $2 "
                "where id = $1::uuid and referral_code is null returning referral_code",
                user_id,
                code,
            )
        except asyncpg.UniqueViolationError:
            continue  # code already taken — try another
        if updated:
            return updated
        # Lost a race: another request set it first — read it back.
        existing = await conn.fetchval(
            "select referral_code from public.profiles where id = $1::uuid", user_id
        )
        if existing:
            return existing
    raise ApiError(ErrorCode.INTERNAL_ERROR, "Couldn't create a referral code.", 500)


async def referral_count(conn: asyncpg.Connection, user_id: str) -> int:
    return await conn.fetchval(
        "select count(*) from public.referrals where referrer_id = $1::uuid", user_id
    )


async def redeem(conn: asyncpg.Connection, user_id: str, code: str, *, reward: int) -> int:
    """Redeem a referral code: record it and grant `reward` credits to both
    sides. Returns the reward. Raises on an invalid/own/already-used code."""
    code = code.strip().upper()
    async with conn.transaction():
        referrer_id = await conn.fetchval(
            "select id from public.profiles where referral_code = $1", code
        )
        if referrer_id is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That referral code isn't valid.", 422)
        if str(referrer_id) == user_id:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't use your own code.", 422)
        try:
            await conn.execute(
                "insert into public.referrals (referee_id, referrer_id, code) "
                "values ($1::uuid, $2::uuid, $3)",
                user_id,
                str(referrer_id),
                code,
            )
        except asyncpg.UniqueViolationError as exc:
            raise ApiError(
                ErrorCode.VALIDATION_ERROR, "You've already used a referral code.", 422
            ) from exc
        await conn.execute(_GRANT, user_id, reward)
        await conn.execute(_GRANT, str(referrer_id), reward)
    return reward
