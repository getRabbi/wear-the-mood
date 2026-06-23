from fastapi import APIRouter, Depends

from app.core.credits import get_credits
from app.core.db import get_pool
from app.core.plans import HD_COST, STD_COST
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.credits import CreditsResponse
from app.services.billing import user_plan

router = APIRouter(tags=["credits"])


@router.get("/credits", response_model=CreditsResponse)
async def credits(user: CurrentUser = Depends(get_current_user)) -> CreditsResponse:
    async with get_pool().acquire() as conn:
        state = await get_credits(conn, user.id)
        plan = await user_plan(conn, user.id)
    return CreditsResponse(
        balance=state.balance,
        daily_free_used=state.daily_free_used,
        daily_free_limit=state.daily_free_limit,
        daily_free_remaining=state.daily_free_remaining,
        topup_balance=state.topup_balance,
        total_available=state.total_available,
        tier=plan.tier,
        monthly_credits=plan.monthly_credits,
        hd_allowed=plan.hd_allowed,
        std_cost=STD_COST,
        hd_cost=HD_COST,
    )
