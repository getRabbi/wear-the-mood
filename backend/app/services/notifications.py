"""In-app notifications (CLAUDE.md §1 pillar 4).

A tiny best-effort helper the social/try-on flows call to drop a notification in
a user's feed. Inserts run as the service-role backend (RLS-bypassing); clients
can never forge a notification (insert has no RLS policy). Creation never raises
into the caller — a failed notification must not break the action that triggered
it (a like/comment/follow).
"""

from __future__ import annotations

import logging

import asyncpg

log = logging.getLogger("fashionos.notifications")


async def create_notification(
    conn: asyncpg.Connection,
    *,
    user_id: str,
    type: str,
    title: str,
    actor_id: str | None = None,
    body: str | None = None,
    target_type: str | None = None,
    target_id: str | None = None,
) -> None:
    """Insert a notification for [user_id]. Best-effort: never notify yourself,
    and swallow any error so the triggering action still succeeds."""
    if actor_id is not None and actor_id == user_id:
        return  # don't notify a user about their own action
    try:
        await conn.execute(
            """
            insert into public.notifications
              (user_id, actor_id, type, title, body, target_type, target_id)
            values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7)
            """,
            user_id,
            actor_id,
            type,
            title,
            body,
            target_type,
            target_id,
        )
    except Exception as exc:  # never break the caller's main action
        log.warning("notification insert failed for %s (%s): %s", user_id, type, exc)


async def actor_name(conn: asyncpg.Connection, actor_id: str) -> str:
    """Display name for an actor, for notification copy. Falls back to 'Someone'."""
    name = await conn.fetchval(
        "select display_name from public.profiles where id = $1::uuid", actor_id
    )
    return name or "Someone"
