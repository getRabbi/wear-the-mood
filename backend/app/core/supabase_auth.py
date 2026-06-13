from __future__ import annotations

from functools import lru_cache

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings
from app.core.errors import ApiError
from app.models.common import ErrorCode

_bearer = HTTPBearer(auto_error=False)

# New Supabase projects sign user JWTs with an asymmetric key (ES256/RS256) and
# publish the public key via JWKS; older projects / our tests use the legacy
# HS256 shared secret. We support both, routing on the token's `alg` header.
_ASYMMETRIC_ALGS = ("ES256", "RS256")


@lru_cache(maxsize=1)
def _jwks_client() -> jwt.PyJWKClient | None:
    settings = get_settings()
    if not settings.supabase_url:
        return None
    headers = (
        {"apikey": settings.supabase_anon_key} if settings.supabase_anon_key else None
    )
    return jwt.PyJWKClient(
        f"{settings.supabase_url}/auth/v1/.well-known/jwks.json",
        headers=headers,
        cache_keys=True,
    )


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
    try:
        alg = jwt.get_unverified_header(token).get("alg")
    except jwt.PyJWTError as exc:
        raise ApiError(ErrorCode.UNAUTHENTICATED, "Invalid token.", 401) from exc

    try:
        if alg in _ASYMMETRIC_ALGS:
            client = _jwks_client()
            if client is None:
                raise ApiError(ErrorCode.INTERNAL_ERROR, "Auth is not configured.", 500)
            key = client.get_signing_key_from_jwt(token).key
            return jwt.decode(
                token,
                key,
                algorithms=list(_ASYMMETRIC_ALGS),
                audience="authenticated",
            )
        # Legacy HS256 (shared JWT secret) — dev projects + tests.
        secret = get_settings().supabase_jwt_secret
        if not secret:
            raise ApiError(ErrorCode.INTERNAL_ERROR, "Auth is not configured.", 500)
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
