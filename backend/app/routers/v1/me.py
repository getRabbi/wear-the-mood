from fastapi import APIRouter, Depends

from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import MeResponse

router = APIRouter(tags=["users"])


@router.get("/me", response_model=MeResponse)
async def me(user: CurrentUser = Depends(get_current_user)) -> MeResponse:
    return MeResponse(id=user.id, email=user.email)
