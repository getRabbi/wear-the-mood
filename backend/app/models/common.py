from pydantic import BaseModel


class ErrorCode:
    """Stable error codes shared with the app (CLAUDE.md §13). The Flutter
    client maps these to localized, friendly messages."""

    UNAUTHENTICATED = "UNAUTHENTICATED"
    FORBIDDEN = "FORBIDDEN"
    INSUFFICIENT_CREDITS = "INSUFFICIENT_CREDITS"
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


class MeResponse(BaseModel):
    id: str
    email: str | None = None
