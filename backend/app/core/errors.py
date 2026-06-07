from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.models.common import ErrorBody, ErrorCode, ErrorResponse

_STATUS_TO_CODE = {
    400: ErrorCode.VALIDATION_ERROR,
    401: ErrorCode.UNAUTHENTICATED,
    403: ErrorCode.FORBIDDEN,
    404: ErrorCode.NOT_FOUND,
    429: ErrorCode.RATE_LIMITED,
}


class ApiError(Exception):
    """Domain error mapped to the uniform error envelope (CLAUDE.md §13)."""

    def __init__(self, code: str, message: str, status_code: int = 400) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        super().__init__(message)


def _request_id(request: Request) -> str | None:
    return getattr(request.state, "request_id", None)


def _envelope(request: Request, code: str, message: str, status_code: int) -> JSONResponse:
    body = ErrorResponse(
        error=ErrorBody(code=code, message=message, request_id=_request_id(request)),
    )
    return JSONResponse(status_code=status_code, content=body.model_dump())


async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    return _envelope(request, exc.code, exc.message, exc.status_code)


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = _STATUS_TO_CODE.get(exc.status_code, ErrorCode.HTTP_ERROR)
    message = exc.detail if isinstance(exc.detail, str) else "Request failed."
    return _envelope(request, code, message, exc.status_code)


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return _envelope(request, ErrorCode.VALIDATION_ERROR, "Invalid request.", 422)


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    # Never leak internals to the client.
    return _envelope(request, ErrorCode.INTERNAL_ERROR, "Something went wrong.", 500)
