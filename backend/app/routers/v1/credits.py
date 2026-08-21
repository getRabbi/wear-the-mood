from fastapi import APIRouter, Depends

from app.core.credits import get_credits
from app.core.db import get_pool
from app.core.monetization import get_policy
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.credits import CreditsResponse
from app.services.billing import user_plan

router = APIRouter(tags=["credits"])


@router.get("/credits", response_model=CreditsResponse)
async def credits(user: CurrentUser = Depends(get_current_user)) -> CreditsResponse:
    """The user's balance AND the prices the server will actually charge.

    The costs come from the monetization policy rather than the module
    constants, so the number the app shows can never disagree with the number
    the try-on endpoint charges. With the seeded configuration the policy
    returns those same constants (1 / 4 / 4), so this response is byte-for-byte
    what it was (spec §53).
    """
    async with get_pool().acquire() as conn:
        policy = await get_policy(conn, user.id)
        state = await get_credits(conn, user.id, free_limit=policy.free_render_limit)
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
        std_cost=policy.std_cost,
        hd_cost=policy.hd_cost,
        enhance_cost=policy.enhance_cost,
    )
