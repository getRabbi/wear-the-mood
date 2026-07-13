from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class ReferralResponse(BaseModel):
    """The user's referral code + stats, for the share UI (CLAUDE.md §24)."""

    code: str
    referral_count: int = 0
    reward_credits: int = 0


class ReferralRedeem(BaseModel):
    code: str = Field(min_length=1, max_length=32)


class ReferralRedeemResponse(BaseModel):
    reward_credits: int


# ── Referral rewards program (install attribution, §24) ─────────────────────


class ReferralRewardItem(BaseModel):
    """One redacted reward-history entry — amount + when, never who (§10)."""

    reward_credits: int
    credited_at: datetime | None = None


class ReferralMeResponse(BaseModel):
    """GET /v1/referrals/me — the signed-in user's referral standing."""

    referral_code: str
    referral_url: str
    bonus_per_successful_referral: int
    successful_referral_count: int = 0
    total_bonus_credits_earned: int = 0
    enabled: bool = True
    recent: list[ReferralRewardItem] = Field(default_factory=list)


class ReferralClickRequest(BaseModel):
    """POST /v1/referrals/click — installed-app App Link handling. Code only."""

    code: str = Field(min_length=1, max_length=32)
    platform: str = Field(default="android", max_length=16)


class ReferralClickResponse(BaseModel):
    token: str
    expires_at: datetime


class ReferralClaimRequest(BaseModel):
    """POST /v1/referrals/claim. Only attribution data — NEVER user ids or amount
    (those come from the server auth context + config, §11/§25)."""

    token: str = Field(min_length=1, max_length=256)
    install_id: str | None = Field(default=None, max_length=128)
    platform: str = Field(default="android", max_length=16)
    app_version: str | None = Field(default=None, max_length=32)


class ReferralClaimResponse(BaseModel):
    # status ∈ awarded | already_claimed | not_eligible_existing_user |
    # self_referral | invalid | expired | reused | disabled
    status: str
    bonus_credits_added: int = 0
    total_available: int = 0
