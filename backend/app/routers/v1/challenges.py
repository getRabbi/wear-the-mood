"""Style challenges — community engagement (CLAUDE.md §1 pillar 4, §24).

Challenges are team-seeded prompts (public read, service-role write). A user
enters by linking one of their OWN posts (read-public, write-own, scoped by the
JWT user_id since service-role bypasses RLS, §11). The entries feed filters
blocked users both ways, mirroring the social feed (§19).
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.challenge import (
    ChallengeEntryResponse,
    ChallengeJoin,
    ChallengeResponse,
)
from app.models.common import ErrorCode

router = APIRouter(tags=["challenges"])

# Challenge row + entry count + whether the current user ($1) has entered.
_CHALLENGE_SELECT = """
    select c.id, c.slug, c.title, c.prompt, c.cover_url, c.starts_at, c.ends_at,
           (select count(*) from public.challenge_entries e
             where e.challenge_id = c.id) as entry_count,
           exists(
             select 1 from public.challenge_entries e
              where e.challenge_id = c.id and e.user_id = $1::uuid
           ) as joined_by_me
      from public.challenges c
"""

# A challenge accepting entries right now.
_ACTIVE = "c.starts_at <= now() and (c.ends_at is null or c.ends_at >= now())"

_ENTRY_SELECT = """
    select e.id, e.challenge_id, e.post_id, e.user_id,
           pr.display_name as author_name, p.image_url, p.caption, e.created_at
      from public.challenge_entries e
      join public.posts p on p.id = e.post_id
      join public.profiles pr on pr.id = e.user_id
"""


def _challenge_from_row(row: asyncpg.Record) -> ChallengeResponse:
    return ChallengeResponse(
        id=str(row["id"]),
        slug=row["slug"],
        title=row["title"],
        prompt=row["prompt"],
        cover_url=row["cover_url"],
        starts_at=row["starts_at"],
        ends_at=row["ends_at"],
        entry_count=row["entry_count"],
        joined_by_me=row["joined_by_me"],
    )


def _entry_from_row(row: asyncpg.Record) -> ChallengeEntryResponse:
    return ChallengeEntryResponse(
        id=str(row["id"]),
        challenge_id=str(row["challenge_id"]),
        post_id=str(row["post_id"]),
        user_id=str(row["user_id"]),
        author_name=row["author_name"],
        image_url=row["image_url"],
        caption=row["caption"],
        created_at=row["created_at"],
    )


@router.get("/challenges", response_model=list[ChallengeResponse])
async def list_challenges(
    user: CurrentUser = Depends(get_current_user),
) -> list[ChallengeResponse]:
    """Active challenges, newest first."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _CHALLENGE_SELECT + f" where {_ACTIVE} order by c.starts_at desc",
            user.id,
        )
    return [_challenge_from_row(r) for r in rows]


@router.get("/challenges/{slug}", response_model=ChallengeResponse)
async def get_challenge(
    slug: str,
    user: CurrentUser = Depends(get_current_user),
) -> ChallengeResponse:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            _CHALLENGE_SELECT + " where c.slug = $2",
            user.id,
            slug,
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Challenge not found.", 404)
    return _challenge_from_row(row)


@router.post("/challenges/{challenge_id}/join", status_code=201, response_model=ChallengeResponse)
async def join_challenge(
    challenge_id: UUID,
    body: ChallengeJoin,
    user: CurrentUser = Depends(get_current_user),
) -> ChallengeResponse:
    """Enter a challenge by linking one of your own posts. Idempotent: re-joining
    the same post is a no-op. Returns the challenge with the updated counts."""
    async with get_pool().acquire() as conn:
        active = await conn.fetchval(
            f"select 1 from public.challenges c where id = $1::uuid and {_ACTIVE}",
            str(challenge_id),
        )
        if active is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Challenge not found or ended.", 404)
        owns = await conn.fetchval(
            "select 1 from public.posts where id = $1::uuid and user_id = $2::uuid",
            str(body.post_id),
            user.id,
        )
        if owns is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That post isn't yours.", 422)
        await conn.execute(
            """
            insert into public.challenge_entries (challenge_id, post_id, user_id)
            values ($1::uuid, $2::uuid, $3::uuid)
            on conflict (challenge_id, post_id) do nothing
            """,
            str(challenge_id),
            str(body.post_id),
            user.id,
        )
        row = await conn.fetchrow(
            _CHALLENGE_SELECT + " where c.id = $2::uuid",
            user.id,
            str(challenge_id),
        )
    return _challenge_from_row(row)


@router.delete("/challenges/{challenge_id}/entries/{post_id}", status_code=204)
async def leave_challenge(
    challenge_id: UUID,
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Withdraw one of your posts from a challenge."""
    async with get_pool().acquire() as conn:
        await conn.execute(
            "delete from public.challenge_entries "
            "where challenge_id = $1::uuid and post_id = $2::uuid and user_id = $3::uuid",
            str(challenge_id),
            str(post_id),
            user.id,
        )
    return Response(status_code=204)


@router.get("/challenges/{challenge_id}/entries", response_model=list[ChallengeEntryResponse])
async def list_entries(
    challenge_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(20, ge=1, le=50),
    before: datetime | None = Query(None),
) -> list[ChallengeEntryResponse]:
    """Newest-first entries for a challenge. Blocked users are filtered both ways
    (§19). Cursor by `before` (the created_at of the last entry seen)."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _ENTRY_SELECT
            + """
             where e.challenge_id = $2::uuid
               and ($3::timestamptz is null or e.created_at < $3::timestamptz)
               and not exists (
                 select 1 from public.blocks b
                  where (b.blocker_id = $1::uuid and b.blocked_id = e.user_id)
                     or (b.blocker_id = e.user_id and b.blocked_id = $1::uuid)
               )
             order by e.created_at desc
             limit $4
            """,
            user.id,
            str(challenge_id),
            before,
            limit,
        )
    return [_entry_from_row(r) for r in rows]
