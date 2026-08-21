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

    A client may only record agreement to the version it actually DISPLAYED, so
    both directions are refused rather than stored:

    * **Above** what this server requires — a bad request would otherwise
      silently satisfy a future, stricter disclosure nobody has seen.
    * **Below** what this server requires — the honest case, and the one that
      matters after a version bump. An older build shows the older disclosure,
      so its grant cannot mean agreement to the current terms.

    Storing a below-required grant would be worse than refusing it. It writes a
    row that can never satisfy the gate, so the user taps Allow, is refused, is
    shown the sheet again, taps Allow again — a consent loop with no exit that
    reads as a broken app rather than as "your app is out of date". Refusing
    with a typed error lets the client say the true thing instead.

    The user is never charged and nothing is shared in either case: this
    endpoint records a decision, it does not authorise a render.
    """
    if body.consent_version != CURRENT_AI_CONSENT_VERSION:
        raise ApiError(
            ErrorCode.VALIDATION_ERROR,
            "Please update Wear The Mood to continue with AI try-on.",
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
