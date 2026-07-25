import uuid
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.config import get_settings
from app.models.common import ErrorCode

# Health/readiness endpoints are never gated (§4.6, §11.9).
_HEALTH_PATHS = frozenset({"/healthz", "/readyz", "/v1/health"})
_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


class MaintenanceMiddleware(BaseHTTPMiddleware):
    """Maintenance-mode gate + emergency-API guard (blueprint §11.8, §11.9).

    * Health/readiness paths always pass.
    * An emergency instance (``EMERGENCY_API=true``) with the guard off refuses ALL
      traffic — it exists only as a manual break-glass and has no production route.
    * Maintenance mode blocks mutating (non-safe) requests with a clear retryable
      503; reads still pass. Off by default, so normal operation is unaffected.
    """

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        path = request.url.path
        if path in _HEALTH_PATHS:
            return await call_next(request)
        settings = get_settings()
        if settings.emergency_api and not settings.emergency_api_enabled:
            return self._blocked(request, "Service temporarily unavailable.")
        if settings.maintenance_mode and request.method not in _SAFE_METHODS:
            return self._blocked(
                request, "We're doing quick maintenance. Please try again in a moment."
            )
        return await call_next(request)

    @staticmethod
    def _blocked(request: Request, message: str) -> JSONResponse:
        request_id = getattr(request.state, "request_id", None)
        return JSONResponse(
            status_code=503,
            content={
                "error": {
                    "code": ErrorCode.MAINTENANCE,
                    "message": message,
                    "request_id": request_id,
                }
            },
            headers={"Retry-After": "30"},
        )


class RequestIDMiddleware(BaseHTTPMiddleware):
    """Assigns a request id (from the inbound `X-Request-ID` header or a fresh
    UUID) to `request.state.request_id` and echoes it back on the response, so
    it can be carried end-to-end through logs and error responses (CLAUDE.md §14)."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
