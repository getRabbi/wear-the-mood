"""Social — OOTD posts, feed, likes, comments, follows (CLAUDE.md §1 pillar 4, §5).

Read-public, write-own (RLS mirrors this; the backend runs as service-role so
every write is scoped to the JWT user_id, §11). Post images are moderated before
they go public (§19). The denormalized posts.like_count / comment_count counters
have no DB trigger, so they're kept consistent here inside a transaction.
"""

from __future__ import annotations

import logging
from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.social import (
    CommentCreate,
    CommentResponse,
    PostCreate,
    PostResponse,
    ReportCreate,
)
from app.services.moderation import get_moderator
from app.services.taste import record_like_signal

log = logging.getLogger("fashionos.social")

router = APIRouter(tags=["social"])

# Post row + author + whether the current user ($1) liked it. No user input.
_FEED_SELECT = """
    select p.id, p.user_id, pr.display_name as author_name, p.caption,
           p.image_url, p.outfit_id, p.like_count, p.comment_count, p.created_at,
           exists(
             select 1 from public.likes l
              where l.post_id = p.id and l.user_id = $1::uuid
           ) as liked_by_me
      from public.posts p
      join public.profiles pr on pr.id = p.user_id
"""

_COMMENT_SELECT = """
    select c.id, c.post_id, c.user_id, pr.display_name as author_name,
           c.body, c.created_at
      from public.comments c
      join public.profiles pr on pr.id = c.user_id
"""


def _post_from_row(row: asyncpg.Record) -> PostResponse:
    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        author_name=row["author_name"],
        caption=row["caption"],
        image_url=row["image_url"],
        outfit_id=str(row["outfit_id"]) if row["outfit_id"] else None,
        like_count=row["like_count"],
        comment_count=row["comment_count"],
        liked_by_me=row["liked_by_me"],
        created_at=row["created_at"],
    )


def _comment_from_row(row: asyncpg.Record) -> CommentResponse:
    return CommentResponse(
        id=str(row["id"]),
        post_id=str(row["post_id"]),
        user_id=str(row["user_id"]),
        author_name=row["author_name"],
        body=row["body"],
        created_at=row["created_at"],
    )


async def _moderate_post_image(user_id: str, image_url: str | None) -> None:
    """Reject abusive post images before they go public (§19). Runs outside any
    DB transaction (it's a network call)."""
    if not image_url:
        return
    result = await get_moderator().check_image(image_url)
    if not result.allowed:
        log.warning("post image blocked for user %s (%s)", user_id, result.reason)
        raise ApiError(ErrorCode.MODERATION_BLOCKED, "This image can't be posted.", 422)


async def _moderate_text(user_id: str, text: str | None, *, kind: str) -> None:
    """Reject abusive UGC text (captions/comments) before it goes public (§19).
    Runs outside any DB transaction (it's a network call)."""
    if not text or not text.strip():
        return
    result = await get_moderator().check_text(text)
    if not result.allowed:
        log.warning("%s text blocked for user %s (%s)", kind, user_id, result.reason)
        raise ApiError(ErrorCode.MODERATION_BLOCKED, f"This {kind} can't be posted.", 422)


# ── posts ────────────────────────────────────────────────────────────────────


@router.post("/social/posts", status_code=201, response_model=PostResponse)
async def create_post(
    body: PostCreate,
    user: CurrentUser = Depends(get_current_user),
) -> PostResponse:
    # A referenced outfit must be the caller's own (§11).
    if body.outfit_id is not None:
        async with get_pool().acquire() as conn:
            owns = await conn.fetchval(
                "select 1 from public.outfits where id = $1::uuid and user_id = $2::uuid",
                str(body.outfit_id),
                user.id,
            )
        if owns is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That outfit isn't yours.", 422)

    await _moderate_post_image(user.id, body.image_url)
    await _moderate_text(user.id, body.caption, kind="caption")

    async with get_pool().acquire() as conn:
        post_id = await conn.fetchval(
            """
            insert into public.posts (user_id, caption, image_url, outfit_id)
            values ($1::uuid, $2, $3, $4)
            returning id
            """,
            user.id,
            body.caption,
            body.image_url,
            str(body.outfit_id) if body.outfit_id else None,
        )
        row = await conn.fetchrow(_FEED_SELECT + " where p.id = $2::uuid", user.id, str(post_id))
    return _post_from_row(row)


@router.get("/social/feed", response_model=list[PostResponse])
async def get_feed(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(20, ge=1, le=50),
    before: datetime | None = Query(None),
) -> list[PostResponse]:
    """Newest-first public feed. Cursor by `before` (the created_at of the last
    item seen) for stable paging."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _FEED_SELECT
            + """
             where p.visibility = 'public'
               and ($2::timestamptz is null or p.created_at < $2::timestamptz)
               and not exists (
                 select 1 from public.blocks b
                  where (b.blocker_id = $1::uuid and b.blocked_id = p.user_id)
                     or (b.blocker_id = p.user_id and b.blocked_id = $1::uuid)
               )
             order by p.created_at desc
             limit $3
            """,
            user.id,
            before,
            limit,
        )
    return [_post_from_row(r) for r in rows]


@router.delete("/social/posts/{post_id}", status_code=204)
async def delete_post(
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        deleted = await conn.fetchval(
            "delete from public.posts where id = $1::uuid and user_id = $2::uuid returning id",
            str(post_id),
            user.id,
        )
    if deleted is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Post not found.", 404)
    return Response(status_code=204)


# ── likes (idempotent; keep posts.like_count consistent) ─────────────────────


@router.post("/social/posts/{post_id}/like", status_code=204)
async def like_post(
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        try:
            async with conn.transaction():
                inserted = await conn.fetchval(
                    """
                    insert into public.likes (user_id, post_id)
                    values ($1::uuid, $2::uuid)
                    on conflict do nothing
                    returning post_id
                    """,
                    user.id,
                    str(post_id),
                )
                if inserted is not None:  # only count a genuinely new like
                    await conn.execute(
                        "update public.posts set like_count = like_count + 1 where id = $1::uuid",
                        str(post_id),
                    )
        except asyncpg.ForeignKeyViolationError as exc:
            raise ApiError(ErrorCode.NOT_FOUND, "Post not found.", 404) from exc
        if inserted is not None:  # a like is a positive taste signal (§24)
            await record_like_signal(conn, user.id, str(post_id))
    return Response(status_code=204)


@router.delete("/social/posts/{post_id}/like", status_code=204)
async def unlike_post(
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            removed = await conn.fetchval(
                "delete from public.likes where user_id = $1::uuid and post_id = $2::uuid "
                "returning post_id",
                user.id,
                str(post_id),
            )
            if removed is not None:
                await conn.execute(
                    "update public.posts set like_count = greatest(like_count - 1, 0) "
                    "where id = $1::uuid",
                    str(post_id),
                )
    return Response(status_code=204)


# ── comments ─────────────────────────────────────────────────────────────────


@router.post(
    "/social/posts/{post_id}/comments",
    status_code=201,
    response_model=CommentResponse,
)
async def add_comment(
    post_id: UUID,
    body: CommentCreate,
    user: CurrentUser = Depends(get_current_user),
) -> CommentResponse:
    await _moderate_text(user.id, body.body, kind="comment")
    async with get_pool().acquire() as conn:
        try:
            async with conn.transaction():
                comment_id = await conn.fetchval(
                    "insert into public.comments (post_id, user_id, body) "
                    "values ($1::uuid, $2::uuid, $3) returning id",
                    str(post_id),
                    user.id,
                    body.body,
                )
                await conn.execute(
                    "update public.posts set comment_count = comment_count + 1 where id = $1::uuid",
                    str(post_id),
                )
        except asyncpg.ForeignKeyViolationError as exc:
            raise ApiError(ErrorCode.NOT_FOUND, "Post not found.", 404) from exc
        row = await conn.fetchrow(_COMMENT_SELECT + " where c.id = $1::uuid", str(comment_id))
    return _comment_from_row(row)


@router.get(
    "/social/posts/{post_id}/comments",
    response_model=list[CommentResponse],
)
async def list_comments(
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
    before: datetime | None = Query(None),
) -> list[CommentResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _COMMENT_SELECT
            + """
             where c.post_id = $1::uuid
               and ($2::timestamptz is null or c.created_at < $2::timestamptz)
             order by c.created_at desc
             limit $3
            """,
            str(post_id),
            before,
            limit,
        )
    return [_comment_from_row(r) for r in rows]


# ── follows ──────────────────────────────────────────────────────────────────


@router.post("/social/follow/{followee_id}", status_code=204)
async def follow_user(
    followee_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    if str(followee_id) == user.id:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't follow yourself.", 422)
    async with get_pool().acquire() as conn:
        try:
            await conn.execute(
                "insert into public.follows (follower_id, followee_id) "
                "values ($1::uuid, $2::uuid) on conflict do nothing",
                user.id,
                str(followee_id),
            )
        except asyncpg.ForeignKeyViolationError as exc:
            raise ApiError(ErrorCode.NOT_FOUND, "User not found.", 404) from exc
    return Response(status_code=204)


@router.delete("/social/follow/{followee_id}", status_code=204)
async def unfollow_user(
    followee_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        await conn.execute(
            "delete from public.follows where follower_id = $1::uuid and followee_id = $2::uuid",
            user.id,
            str(followee_id),
        )
    return Response(status_code=204)


# ── reports + blocks (UGC safety, §19) ───────────────────────────────────────


@router.post("/social/reports", status_code=201)
async def file_report(
    body: ReportCreate,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """File a UGC report. Stored for moderation review (service-role only reads
    the queue); the reporter only ever sees their own reports (RLS)."""
    async with get_pool().acquire() as conn:
        await conn.execute(
            "insert into public.reports (reporter_id, subject_type, subject_id, reason) "
            "values ($1::uuid, $2, $3::uuid, $4)",
            user.id,
            body.subject_type,
            str(body.subject_id),
            body.reason,
        )
    return Response(status_code=201)


@router.post("/social/block/{blocked_id}", status_code=204)
async def block_user(
    blocked_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Block a user: they're filtered out of the feed both ways (§19)."""
    if str(blocked_id) == user.id:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't block yourself.", 422)
    async with get_pool().acquire() as conn:
        try:
            await conn.execute(
                "insert into public.blocks (blocker_id, blocked_id) "
                "values ($1::uuid, $2::uuid) on conflict do nothing",
                user.id,
                str(blocked_id),
            )
        except asyncpg.ForeignKeyViolationError as exc:
            raise ApiError(ErrorCode.NOT_FOUND, "User not found.", 404) from exc
    return Response(status_code=204)


@router.delete("/social/block/{blocked_id}", status_code=204)
async def unblock_user(
    blocked_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        await conn.execute(
            "delete from public.blocks where blocker_id = $1::uuid and blocked_id = $2::uuid",
            user.id,
            str(blocked_id),
        )
    return Response(status_code=204)
