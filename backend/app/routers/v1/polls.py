"""Poll voting + results (FEATURES_COMMUNITY_PLUS · Poll).

A poll is created with its post (see social.create_post). Here a user casts ONE
vote per poll (changeable until it closes) and reads aggregate results. Voting is
idempotent via the (poll_id,user_id) primary key + upsert — re-voting the same
option is a no-op; a different option replaces it (§9). Results are aggregate
counts only; we never reveal who voted what beyond the caller's own choice (§10).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.poll import PollResponse, PollVote
from app.services.polls import load_poll

router = APIRouter(tags=["polls"])


@router.get("/polls/{poll_id}", response_model=PollResponse)
async def get_poll(
    poll_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> PollResponse:
    async with get_pool().acquire() as conn:
        poll = await load_poll(conn, user.id, str(poll_id))
    if poll is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Poll not found.", 404)
    return poll


@router.post("/polls/{poll_id}/vote", response_model=PollResponse)
async def vote_poll(
    poll_id: UUID,
    body: PollVote,
    user: CurrentUser = Depends(get_current_user),
) -> PollResponse:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            "select options, closes_at from public.post_polls where id = $1::uuid",
            str(poll_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Poll not found.", 404)

        options = row["options"]
        if isinstance(options, str):  # asyncpg returns jsonb as text
            options = json.loads(options)
        closes_at = row["closes_at"]
        if closes_at is not None and closes_at <= datetime.now(UTC):
            raise ApiError(ErrorCode.VALIDATION_ERROR, "This poll has closed.", 422)
        if not (0 <= body.option_index < len(options)):
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That option doesn't exist.", 422)

        # One vote per user; re-voting the same option is a no-op, a different
        # one replaces it (idempotent, §9).
        await conn.execute(
            """
            insert into public.poll_votes (poll_id, user_id, option_index)
            values ($1::uuid, $2::uuid, $3)
            on conflict (poll_id, user_id)
              do update set option_index = excluded.option_index, created_at = now()
            """,
            str(poll_id),
            user.id,
            body.option_index,
        )
        result = await load_poll(conn, user.id, str(poll_id))
    assert result is not None  # the poll existed above
    return result
