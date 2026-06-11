"""Taste graph / Style DNA (CLAUDE.md §24).

Positive interactions (likes, try-ons, …) are recorded as taste_signals carrying
the embedding of the thing the user engaged with. The centroid of those
embeddings is the user's "taste vector" — used to bias the stylist toward what
they actually like. Everything degrades gracefully: with no signals (or no
embeddings yet, before the worker + OpenAI key are live), the centroid is None
and callers fall back to their default behaviour.
"""

from __future__ import annotations

import logging

import asyncpg

log = logging.getLogger("fashionos.taste")


async def taste_centroid(conn: asyncpg.Connection, user_id: str) -> str | None:
    """The user's taste vector: the centroid of their embedded taste signals,
    as a pgvector literal to re-bind with ``$n::vector``. None when the user has
    no embedded signals yet."""
    return await conn.fetchval(
        """
        select avg(embedding)::text
          from public.taste_signals
         where user_id = $1::uuid and embedding is not null
        """,
        user_id,
    )


async def record_like_signal(conn: asyncpg.Connection, user_id: str, post_id: str) -> None:
    """Record a positive taste signal for a liked post (§24), carrying the mean
    embedding of the post's outfit items so the centroid can bias the stylist.

    Best-effort: a failure here must never break the like that triggered it, and
    the embedding is simply null until the worker + OpenAI key have embedded the
    user's wardrobe — the signal is still recorded for later use.
    """
    try:
        await conn.execute(
            """
            insert into public.taste_signals
              (user_id, signal_type, subject_type, subject_id, embedding)
            select $1::uuid, 'like', 'post', p.id,
                   (select avg(w.embedding)
                      from public.wardrobe_items w
                     where w.id = any(o.item_ids) and w.embedding is not null)
              from public.posts p
              left join public.outfits o on o.id = p.outfit_id
             where p.id = $2::uuid
            """,
            user_id,
            post_id,
        )
    except Exception as exc:  # taste is best-effort; never fail the like
        log.warning("taste signal record failed for post %s: %s", post_id, exc)
