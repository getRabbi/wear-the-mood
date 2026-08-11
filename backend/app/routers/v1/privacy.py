"""Privacy controls the user can exercise for themselves (§10).

Currently one control: permission to send their own photo to a third-party AI
provider. Read it, grant it, withdraw it. Own-row only — every handler derives
the user from the JWT and never accepts a user id from the client (§11).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.privacy import AiConsentGrantRequest, AiConsentResponse
from app.services.privacy import (
    AI_PERSONAL_IMAGE_CONSENT,
    CURRENT_AI_CONSENT_VERSION,
    ConsentState,
    grant_ai_consent,
    read_ai_consent,
    revoke_ai_consent,
)

router = APIRouter(tags=["privacy"])


def _response(state: ConsentState) -> AiConsentResponse:
    return AiConsentResponse(
        consent_type=AI_PERSONAL_IMAGE_CONSENT,
        granted=state.granted,
        version=state.version,
        required_version=CURRENT_AI_CONSENT_VERSION,
        provider_scope=state.provider_scope,
        is_current=state.is_current,
    )


@router.get("/privacy/ai-consent", response_model=AiConsentResponse)
async def get_ai_consent(user: CurrentUser = Depends(get_current_user)) -> AiConsentResponse:
    """Current state. Cheap enough to call on app start to warm the client cache."""
    async with get_pool().acquire() as conn:
        return _response(await read_ai_consent(conn, user.id))


@router.post("/privacy/ai-consent", response_model=AiConsentResponse)
async def post_ai_consent(
    body: AiConsentGrantRequest, user: CurrentUser = Depends(get_current_user)
) -> AiConsentResponse:
    """Record an explicit grant.

    A client may not record agreement to a version it did not display, so a
    version ABOVE what this server requires is rejected rather than stored — that
    would otherwise let a bad request silently satisfy a future, stricter
    disclosure that nobody has actually seen. A version below is honest but
    stale, so it is stored as sent and simply will not satisfy the gate.
    """
    if body.consent_version > CURRENT_AI_CONSENT_VERSION:
        raise ApiError(
            ErrorCode.VALIDATION_ERROR,
            "Please update the app to continue.",
            422,
        )
    async with get_pool().acquire() as conn:
        return _response(await grant_ai_consent(conn, user.id, version=body.consent_version))


@router.delete("/privacy/ai-consent", response_model=AiConsentResponse)
async def delete_ai_consent(user: CurrentUser = Depends(get_current_user)) -> AiConsentResponse:
    """Withdraw consent. Governs new sharing only; renders already accepted keep
    the authorisation they were submitted under. Never deletes stored content —
    that is account deletion, which is a separate, explicit action (§10)."""
    async with get_pool().acquire() as conn:
        return _response(await revoke_ai_consent(conn, user.id))
