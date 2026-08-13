"""Privacy domain — consent for third-party AI processing of personal images."""

from app.services.privacy.ai_consent import (
    AI_PERSONAL_IMAGE_CONSENT,
    CURRENT_AI_CONSENT_VERSION,
    PROVIDER_SCOPE,
    ConsentState,
    grant_ai_consent,
    read_ai_consent,
    require_ai_personal_image_consent,
    revoke_ai_consent,
)

__all__ = [
    "AI_PERSONAL_IMAGE_CONSENT",
    "CURRENT_AI_CONSENT_VERSION",
    "PROVIDER_SCOPE",
    "ConsentState",
    "grant_ai_consent",
    "read_ai_consent",
    "require_ai_personal_image_consent",
    "revoke_ai_consent",
]
