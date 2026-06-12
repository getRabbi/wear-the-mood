"""Referrals — viral growth (CLAUDE.md §24). The user shares their code; a new
user redeems it and both sides get bonus credits, all server-verified (§11)."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.config import get_settings
from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.referral import ReferralRedeem, ReferralRedeemResponse, ReferralResponse
from app.services.referrals import get_or_create_code, redeem, referral_count

router = APIRouter(tags=["referrals"])


@router.get("/referrals", response_model=ReferralResponse)
async def my_referrals(
    user: CurrentUser = Depends(get_current_user),
) -> ReferralResponse:
    """The user's referral code (created on first request) + how many friends
    they've referred."""
    async with get_pool().acquire() as conn:
        code = await get_or_create_code(conn, user.id)
        count = await referral_count(conn, user.id)
    return ReferralResponse(
        code=code,
        referral_count=count,
        reward_credits=get_settings().referral_reward_credits,
    )


@router.post("/referrals/redeem", response_model=ReferralRedeemResponse)
async def redeem_referral(
    body: ReferralRedeem,
    user: CurrentUser = Depends(get_current_user),
) -> ReferralRedeemResponse:
    """Redeem a friend's code. Both sides are granted bonus credits. Rejects an
    invalid code, your own code, or a second redemption (§24)."""
    reward = get_settings().referral_reward_credits
    async with get_pool().acquire() as conn:
        granted = await redeem(conn, user.id, body.code, reward=reward)
    return ReferralRedeemResponse(reward_credits=granted)
