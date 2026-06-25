from pydantic import BaseModel


class ErrorCode:
    """Stable error codes shared with the app (CLAUDE.md §13). The Flutter
    client maps these to localized, friendly messages."""

    UNAUTHENTICATED = "UNAUTHENTICATED"
    FORBIDDEN = "FORBIDDEN"
    INSUFFICIENT_CREDITS = "INSUFFICIENT_CREDITS"
    PAYWALL = "PAYWALL"  # no plan / out of credits — show the upsell + top-up (§18)
    HD_LOCKED = "HD_LOCKED"  # HD / Try-On Max requested without a Pro Max plan (§18)
    RATE_LIMITED = "RATE_LIMITED"
    PROVIDER_ERROR = "PROVIDER_ERROR"
    VALIDATION_ERROR = "VALIDATION_ERROR"
    MODERATION_BLOCKED = "MODERATION_BLOCKED"
    NOT_FOUND = "NOT_FOUND"
    HTTP_ERROR = "HTTP_ERROR"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class ErrorBody(BaseModel):
    code: str
    message: str
    request_id: str | None = None


class ErrorResponse(BaseModel):
    """Uniform error envelope (CLAUDE.md §13): {"error": {code, message, request_id}}."""

    error: ErrorBody


class HealthResponse(BaseModel):
    status: str
    app: str
    environment: str
    version: str
    # Deployed commit SHA (empty when the env var isn't set) — lets us verify the
    # live backend matches HEAD without sshing into the droplet (CLAUDE.md §21).
    commit: str | None = None


class MeResponse(BaseModel):
    id: str
    email: str | None = None
