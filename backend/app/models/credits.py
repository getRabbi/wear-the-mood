from pydantic import BaseModel


class CreditsResponse(BaseModel):
    """The user's credit state + their plan's costs/allowance, so the UI can show
    the balance and what HD costs — all server-authoritative (§18)."""

    balance: int  # plan credits (reset monthly, no rollover)
    daily_free_used: int
    daily_free_limit: int
    daily_free_remaining: int
    topup_balance: int = 0
    total_available: int = 0  # free_remaining + balance + topup_balance
    tier: str = "free"  # free | pro | pro_max
    monthly_credits: int = 0  # the plan's allowance (config, from plans table)
    hd_allowed: bool = False
    std_cost: int = 1
    hd_cost: int = 4
    enhance_cost: int = 4  # AI Enhance Item — server-authoritative, so the UI
    # shows the same 4 it will be charged (never drifts from the backend).
