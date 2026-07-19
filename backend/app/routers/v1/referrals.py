"""Referrals — viral growth (CLAUDE.md §24). The user shares their code; a new
user redeems it and both sides get bonus credits, all server-verified (§11).

The install-attribution REWARDS program (/me, /click, /claim) supersedes the
legacy manual-code /redeem flow: a genuinely new, Play-attributed account claims
a single-use token and the REFERRER earns a persistent bonus once (§24)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from app.core.config import get_settings
from app.core.credits import get_credits
from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.rate_limit import client_ip, enforce_rate_limit
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.referral import (
    ReferralClaimRequest,
    ReferralClaimResponse,
    ReferralClickRequest,
    ReferralClickResponse,
    ReferralMeResponse,
    ReferralRedeem,
    ReferralRedeemResponse,
    ReferralResponse,
)
from app.services.referrals import (
    ClaimStatus,
    claim,
    create_attribution,
    get_or_create_code,
    redeem,
    referral_count,
    referral_summary,
)

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


# ── Referral rewards program (install attribution, §24) ─────────────────────


@router.get("/referrals/me", response_model=ReferralMeResponse)
async def my_referral_standing(
    user: CurrentUser = Depends(get_current_user),
) -> ReferralMeResponse:
    """The user's stable referral code + share URL, bonus, successful count,
    total earned, and a redacted reward history (never referred users' data)."""
    async with get_pool().acquire() as conn:
        summary = await referral_summary(conn, user.id)
    return ReferralMeResponse(**summary)


@router.post("/referrals/click", response_model=ReferralClickResponse)
async def referral_click(
    body: ReferralClickRequest,
    request: Request,
) -> ReferralClickResponse:
    """Installed-app App Link handling: validate a referral code and mint an
    opaque, short-lived attribution token (no private referrer data). Rate
    limited per IP. Unknown codes fail with VALIDATION_ERROR (no token)."""
    async with get_pool().acquire() as conn:
        await enforce_rate_limit(
            conn, bucket=f"refclick:{client_ip(request)}", limit=30, window_seconds=3600
        )
        minted = await create_attribution(conn, body.code, platform=body.platform)
    if minted is None:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "That referral code isn't valid.", 422)
    raw, expires_at = minted
    return ReferralClickResponse(token=raw, expires_at=expires_at)


@router.post("/referrals/claim", response_model=ReferralClaimResponse)
async def referral_claim(
    body: ReferralClaimRequest,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
) -> ReferralClaimResponse:
    """Claim a referral for the AUTHENTICATED (referred) user. The referred user
    id comes from the JWT — never the body (§11). On award the REFERRER (not the
    caller) gets the bonus; the response reports the caller's own current total.
    Idempotent + concurrency-safe: a repeated successful claim never re-grants."""
    async with get_pool().acquire() as conn:
        # Stricter limit on claims — per user AND per IP.
        await enforce_rate_limit(
            conn, bucket=f"refclaim:u:{user.id}", limit=10, window_seconds=3600
        )
        await enforce_rate_limit(
            conn, bucket=f"refclaim:ip:{client_ip(request)}", limit=40, window_seconds=3600
        )
        result = await claim(
            conn,
            referred_user_id=user.id,
            token=body.token,
            install_id=body.install_id,
            platform=body.platform,
        )
        # The caller is the referred user — report THEIR current total (unchanged
        # by their own claim; the bonus went to the referrer).
        state = await get_credits(conn, user.id)
    return ReferralClaimResponse(
        status=result.status.value,
        bonus_credits_added=(result.reward_credits if result.status == ClaimStatus.awarded else 0),
        total_available=state.total_available,
    )
