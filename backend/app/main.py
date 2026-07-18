from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app import __version__
from app.core.config import get_settings
from app.core.db import close_db, init_db
from app.core.errors import (
    ApiError,
    api_error_handler,
    http_exception_handler,
    unhandled_error_handler,
    validation_error_handler,
)
from app.core.middleware import MaintenanceMiddleware, RequestIDMiddleware
from app.core.observability import init_sentry
from app.routers.health_root import router as health_root_router
from app.routers.referral_redirect import router as referral_redirect_router
from app.routers.v1 import api_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    await init_db()
    try:
        yield
    finally:
        await close_db()


def create_app() -> FastAPI:
    settings = get_settings()
    init_sentry()
    app = FastAPI(title=settings.app_name, version=__version__, lifespan=lifespan)

    # Add order matters (Starlette wraps last-added outermost): CORS → RequestID →
    # Maintenance → route, so request_id is set before the maintenance gate runs.
    app.add_middleware(MaintenanceMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Uniform error contract (CLAUDE.md §13).
    app.add_exception_handler(ApiError, api_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(Exception, unhandled_error_handler)

    app.include_router(api_router, prefix=settings.api_v1_prefix)
    # Root liveness/readiness probes for the platform (§4.6); legacy /v1/health kept.
    app.include_router(health_root_router)
    # Public referral redirect lives at ROOT so the share URL is
    # wearthemood.com/r/<code> (proxied to the API), not under /v1 (§24).
    app.include_router(referral_redirect_router)

    @app.get("/")
    async def root() -> dict[str, str]:
        return {"status": "ok", "service": settings.app_name}

    return app


app = create_app()
