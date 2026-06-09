"""Idempotency-Key store (CLAUDE.md §9).

Every credit-spending / job-creating endpoint takes an `Idempotency-Key` header
(a UUID the client generates per user action). The first request reserves the
key and does the work; any retry with the same key returns the stored response
instead of re-charging or re-enqueueing — the guard against double-taps, retries
and flaky networks.

Composed by endpoints (added in later steps) roughly as:

    stored = await get_stored_response(conn, key, user_id, endpoint)
    if stored is not None:
        return replay(stored)
    if not await reserve_key(conn, key, user_id, endpoint):
        raise ApiError(VALIDATION_ERROR, "Request already in progress.", 409)
    ... do the work ...
    await store_response(conn, key, user_id, endpoint, status, body)

Keys are scoped by (key, user_id, endpoint) on read/write so one user can never
replay another's stored response. The table is service-role only (RLS, §5).
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import asyncpg
from fastapi import Header

from app.core.errors import ApiError
from app.models.common import ErrorCode


def require_idempotency_key(
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> str:
    """FastAPI dependency: require a non-empty Idempotency-Key header (§9)."""
    if not idempotency_key or not idempotency_key.strip():
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Missing Idempotency-Key header.", 400)
    return idempotency_key.strip()


@dataclass(frozen=True)
class StoredResponse:
    status_code: int
    response: dict


async def get_stored_response(
    conn: asyncpg.Connection, key: str, user_id: str, endpoint: str
) -> StoredResponse | None:
    """Return a completed prior response for this key, or None if the key is
    unknown or still in-flight (reserved but not yet finished)."""
    row = await conn.fetchrow(
        """
        select status_code, response
          from public.idempotency_keys
         where key = $1 and user_id = $2::uuid and endpoint = $3
        """,
        key,
        user_id,
        endpoint,
    )
    if row is None or row["status_code"] is None:
        return None
    raw = row["response"]
    body = json.loads(raw) if isinstance(raw, str) else raw
    return StoredResponse(status_code=row["status_code"], response=body or {})


async def reserve_key(conn: asyncpg.Connection, key: str, user_id: str, endpoint: str) -> bool:
    """Atomically reserve the key. Returns True when newly reserved (the caller
    should do the work), False when it already existed (replay / in-flight)."""
    result = await conn.execute(
        """
        insert into public.idempotency_keys (key, user_id, endpoint)
        values ($1, $2::uuid, $3)
        on conflict (key) do nothing
        """,
        key,
        user_id,
        endpoint,
    )
    # asyncpg returns the command tag, e.g. "INSERT 0 1" when a row was inserted.
    return result.endswith(" 1")


async def store_response(
    conn: asyncpg.Connection,
    key: str,
    user_id: str,
    endpoint: str,
    status_code: int,
    response: dict,
) -> None:
    """Persist the final response so future retries with this key replay it."""
    await conn.execute(
        """
        update public.idempotency_keys
           set status_code = $2, response = $3::jsonb
         where key = $1 and user_id = $4::uuid and endpoint = $5
        """,
        key,
        status_code,
        json.dumps(response),
        user_id,
        endpoint,
    )
