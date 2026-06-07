from __future__ import annotations

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings
from app.core.errors import ApiError
from app.models.common import ErrorCode

_bearer = HTTPBearer(auto_error=False)


class CurrentUser:
    """Authenticated principal derived from a verified Supabase JWT.

    `id` always comes from the token's `sub` claim — never from the client's
    request body/query (CLAUDE.md §11).
    """

    def __init__(self, user_id: str, email: str | None, claims: dict[str, object]) -> None:
        self.id = user_id
        self.email = email
        self.claims = claims


def _decode(token: str) -> dict[str, object]:
    secret = get_settings().supabase_jwt_secret
    if not secret:
        raise ApiError(ErrorCode.INTERNAL_ERROR, "Auth is not configured.", 500)
    try:
        return jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError as exc:
        raise ApiError(ErrorCode.UNAUTHENTICATED, "Invalid or expired token.", 401) from exc


async def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> CurrentUser:
    """FastAPI dependency: require and verify a Supabase bearer token."""
    if creds is None or not creds.credentials:
        raise ApiError(ErrorCode.UNAUTHENTICATED, "Missing bearer token.", 401)

    payload = _decode(creds.credentials)
    user_id = payload.get("sub")
    if not isinstance(user_id, str) or not user_id:
        raise ApiError(ErrorCode.UNAUTHENTICATED, "Token missing subject.", 401)

    email = payload.get("email")
    return CurrentUser(
        user_id=user_id,
        email=email if isinstance(email, str) else None,
        claims=payload,
    )
