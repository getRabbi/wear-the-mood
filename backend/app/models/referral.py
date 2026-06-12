from __future__ import annotations

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
