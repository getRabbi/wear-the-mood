"""Social — OOTD posts, feed, likes, comments, follows (CLAUDE.md §1 pillar 4, §5).

Read-public, write-own (RLS mirrors this; the backend runs as service-role so
every write is scoped to the JWT user_id, §11). Post images are moderated before
they go public (§19). The denormalized posts.like_count / comment_count counters
have no DB trigger, so they're kept consistent here inside a transaction.
"""

from __future__ import annotations

import asyncio
import json
import logging
from base64 import b64encode
from collections.abc import Iterable
from datetime import UTC, datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response
from fastapi.responses import JSONResponse

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.idempotency import (
    get_stored_response,
    require_idempotency_key,
    reserve_key,
    store_response,
)
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.poll import PollResponse
from app.models.social import (
    CommentCreate,
    CommentResponse,
    LeaderboardEntry,
    LeaderboardResponse,
    PastWinner,
    PostCreate,
    PostResponse,
    PostUpdate,
    PublicClosetItem,
    PublicProfileResponse,
    PublicUserCard,
    ReportCreate,
)
from app.services.display import contains_email, public_display_name, redact_emails
from app.services.media.deletion import delete_content_media
from app.services.media.repo import resolve_images, resolve_private_path
from app.services.moderation import get_moderator
from app.services.notifications import actor_name, create_notification
from app.services.polls import load_polls_for_posts
from app.services.storage import download_image
from app.services.taste import record_like_signal

log = logging.getLogger("fashionos.social")

router = APIRouter(tags=["social"])

# Post row + author + whether the current user ($1) liked it. No user input.
# author_username is the public-name fallback; the raw email is never selected
# and the display name is scrubbed in [_post_from_row] (§10).
# Private Supabase bucket the profile pictures live in (legacy signing); an R2
# key is recognised via media_assets by resolve_private_path.
_PROFILE_PIC_BUCKET = "profile-pictures"

_FEED_SELECT = """
    select p.id, p.user_id, pr.display_name as author_name,
           pr.username as author_username,
           pr.is_official as author_is_official, pr.public_label as author_label,
           pr.profile_picture_url as author_avatar,
           p.caption,
           p.image_url, p.outfit_id, p.tags, p.like_count, p.comment_count,
           p.is_edited, p.edited_at, p.created_at,
           exists(
             select 1 from public.likes l
              where l.post_id = p.id and l.user_id = $1::uuid
           ) as liked_by_me
      from public.posts p
      join public.profiles pr on pr.id = p.user_id
"""

_COMMENT_SELECT = """
    select c.id, c.post_id, c.user_id, pr.display_name as author_name,
           pr.username as author_username, pr.profile_picture_url as author_avatar,
           c.body, c.created_at
      from public.comments c
      join public.profiles pr on pr.id = c.user_id
"""


async def _resolve_avatars(
    conn: asyncpg.Connection, paths: Iterable[str | None]
) -> dict[str, str | None]:
    """Sign each DISTINCT profile-picture path/key for display (R2 or legacy),
    keyed by the raw stored value. A page of feed/comment rows shares few authors,
    so we resolve each unique avatar once (never per-row). The DISPLAY picture only
    — never the private body/try-on photo (§10)."""
    unique = {p for p in paths if p}
    out: dict[str, str | None] = {}
    for path in unique:
        out[path] = await resolve_private_path(conn, path, _PROFILE_PIC_BUCKET)
    return out

# Moderation visibility filter for the public feed / a creator's posts (admin §13).
# Assumes the post alias `p` joined to its author profile alias `pr`, and that the
# VIEWER's id is bind parameter $1. Hides admin-hidden/deleted/archived posts and
# posts by deleted authors; a shadowbanned author's posts are visible only to the
# author themselves. (Active seed posts are 'published' → shown; archived → hidden.)
_FEED_MOD_WHERE = """
       and p.status = 'published'
       and pr.account_status <> 'deleted'
       and (pr.account_status <> 'shadowbanned' or p.user_id = $1::uuid)
"""


def _post_from_row(
    row: asyncpg.Record,
    poll: PollResponse | None = None,
    *,
    image_url: str | None = None,
    thumbnail_url: str | None = None,
    avatar_url: str | None = None,
) -> PostResponse:
    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        # Never surface a raw email as the author (§10); fall back to the
        # username, then the client's neutral "Someone".
        author_name=public_display_name(row["author_name"], row["author_username"]),
        author_avatar_url=avatar_url,
        is_official=bool(row["author_is_official"]),
        official_label=row["author_label"],
        # Redact any email left in a LEGACY caption (new captions are rejected on
        # create/edit) so a raw email never shows in the public feed (§10).
        caption=redact_emails(row["caption"]),
        image_url=image_url if image_url is not None else row["image_url"],
        thumbnail_url=thumbnail_url,
        outfit_id=str(row["outfit_id"]) if row["outfit_id"] else None,
        tags=list(row["tags"]) if row["tags"] is not None else [],
        like_count=row["like_count"],
        comment_count=row["comment_count"],
        liked_by_me=row["liked_by_me"],
        is_edited=row["is_edited"],
        edited_at=row["edited_at"],
        poll=poll,
        created_at=row["created_at"],
    )


async def _posts_with_polls(
    conn: asyncpg.Connection, user_id: str, rows: list[asyncpg.Record]
) -> list[PostResponse]:
    """Build PostResponses for a page of feed rows, attaching each post's poll
    (one batched query for aggregate counts + the caller's own choice)."""
    polls = await load_polls_for_posts(conn, user_id, [str(r["id"]) for r in rows])
    # Resolve each post image via media_assets (R2 CDN url + thumbnail where
    # available); legacy/un-migrated posts pass through their stored image_url.
    assets = await resolve_images(conn, "post", [r["id"] for r in rows], ("post",))
    # Resolve each author's DISPLAY picture (the community avatar) once per author.
    avatars = await _resolve_avatars(conn, (r["author_avatar"] for r in rows))
    result: list[PostResponse] = []
    for r in rows:
        hit = assets.get((str(r["id"]), "post"))
        image_url = hit.url if (hit and hit.url) else r["image_url"]
        thumbnail_url = hit.thumb_url if hit else None
        result.append(
            _post_from_row(
                r,
                polls.get(str(r["id"])),
                image_url=image_url,
                thumbnail_url=thumbnail_url,
                avatar_url=avatars.get(r["author_avatar"]),
            )
        )
    return result


def _comment_from_row(row: asyncpg.Record, *, avatar_url: str | None = None) -> CommentResponse:
    return CommentResponse(
        id=str(row["id"]),
        post_id=str(row["post_id"]),
        user_id=str(row["user_id"]),
        author_name=public_display_name(row["author_name"], row["author_username"]),
        author_avatar_url=avatar_url,
        body=row["body"],
        created_at=row["created_at"],
    )


# Brief retry to cover a just-uploaded object the CDN may not serve for a beat.
_MOD_FETCH_ATTEMPTS = 3
_MOD_FETCH_DELAY = 0.5  # seconds, ×attempt


async def _fetch_for_moderation(image_url: str | None) -> str | None:
    """Download the image (retrying briefly) and return a base64 data URI.

    ROOT CAUSE of "couldn't share, works on 2nd try": a freshly-uploaded image
    URL isn't reliably servable for a beat, and we moderated by handing that URL
    to the provider to fetch — so the first attempt failed and a retry worked.
    Downloading the BYTES here (with a short retry) removes the provider's fetch
    dependency AND confirms the image is durably servable before the post goes
    live, so the feed never renders a broken image (CLAUDE.md §8, §19). Returns
    None when there's no image (outfit-only posts)."""
    if not image_url:
        return None
    last_exc: Exception | None = None
    for attempt in range(1, _MOD_FETCH_ATTEMPTS + 1):
        try:
            image = await download_image(image_url)
            ctype = (
                "image/png" if image_url.split("?")[0].lower().endswith(".png") else "image/jpeg"
            )
            return f"data:{ctype};base64,{b64encode(image).decode('ascii')}"
        except Exception as exc:  # not yet served / transient — retry
            last_exc = exc
            if attempt < _MOD_FETCH_ATTEMPTS:
                await asyncio.sleep(_MOD_FETCH_DELAY * attempt)
    log.warning("post image not fetchable after %d tries: %s", _MOD_FETCH_ATTEMPTS, last_exc)
    raise ApiError(
        ErrorCode.PROVIDER_ERROR,
        "We couldn't read that image yet. Please try again in a moment.",
        503,
    ) from last_exc


async def _moderate_post_image(user_id: str, moderation_image: str | None) -> None:
    """Reject abusive post images before they go public (§19). Takes a data URI
    (the downloaded bytes from [_fetch_for_moderation]) so the moderator never has
    to fetch a fresh URL itself. Runs outside any DB transaction (network call)."""
    if not moderation_image:
        return
    result = await get_moderator().check_image(moderation_image)
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


def _reject_email_caption(caption: str | None) -> None:
    """Keep raw emails out of PUBLIC post captions (§10). A community caption is
    public, so an email there leaks contact info — reject it with a clear, fixable
    message rather than silently publishing or stripping it."""
    if contains_email(caption):
        raise ApiError(
            ErrorCode.VALIDATION_ERROR,
            "Please don't include email addresses in public posts.",
            422,
        )


async def _assert_can_write(conn: asyncpg.Connection, user_id: str) -> None:
    """Block UGC creation from a moderated account (admin §13). Banned/deleted →
    hard restriction; suspended → restricted until `banned_until` passes.
    Shadowbanned users CAN create (their content is just filtered from others'
    feeds by [_FEED_MOD_WHERE]) — silent shadowban, by design."""
    row = await conn.fetchrow(
        "select account_status, banned_until from public.profiles where id = $1::uuid",
        user_id,
    )
    if row is None:
        return  # no profile row yet — let the downstream FK handle it
    status = row["account_status"]
    if status in ("banned", "deleted"):
        raise ApiError(ErrorCode.ACCOUNT_RESTRICTED, "Your account has been restricted.", 403)
    if status == "suspended":
        until = row["banned_until"]
        if until is None or until > datetime.now(UTC):
            raise ApiError(
                ErrorCode.ACCOUNT_RESTRICTED, "Your account is temporarily restricted.", 403
            )


# ── posts ────────────────────────────────────────────────────────────────────


_CREATE_POST_ENDPOINT = "POST /v1/social/posts"


@router.post("/social/posts", status_code=201, response_model=PostResponse)
async def create_post(
    body: PostCreate,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    # Keep emails out of public captions (§10) — reject before ANY DB/upload work.
    _reject_email_caption(body.caption)
    async with get_pool().acquire() as conn:
        # A moderated account (banned/suspended/deleted) can't post (admin §13).
        await _assert_can_write(conn, user.id)
        # Replay an identical completed request (§9) — never create a duplicate
        # post on a double-tap / network retry.
        stored = await get_stored_response(conn, idempotency_key, user.id, _CREATE_POST_ENDPOINT)
        if stored is not None:
            return JSONResponse(status_code=stored.status_code, content=stored.response)

        # A referenced outfit must be the caller's own (§11).
        if body.outfit_id is not None:
            owns = await conn.fetchval(
                "select 1 from public.outfits where id = $1::uuid and user_id = $2::uuid",
                str(body.outfit_id),
                user.id,
            )
            if owns is None:
                raise ApiError(ErrorCode.VALIDATION_ERROR, "That outfit isn't yours.", 422)

    # Confirm the image is durably servable + moderate the actual bytes BEFORE
    # reserving the key, so a not-yet-served image fails cleanly and is retryable
    # without burning the idempotency key (§9, §19). Network calls, no txn.
    moderation_image = await _fetch_for_moderation(body.image_url)
    await _moderate_post_image(user.id, moderation_image)
    await _moderate_text(user.id, body.caption, kind="caption")
    # Moderate the attached poll's text with the post (§19) before it goes public.
    if body.poll is not None:
        await _moderate_text(user.id, body.poll.question, kind="poll")
        for option in body.poll.options:
            await _moderate_text(user.id, option, kind="poll option")

    async with get_pool().acquire() as conn:
        async with conn.transaction():
            # Reserve + create + store atomically: a concurrent duplicate hits the
            # reservation conflict; a completed one replays via get_stored_response.
            if not await reserve_key(conn, idempotency_key, user.id, _CREATE_POST_ENDPOINT):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)
            post_id = await conn.fetchval(
                """
                insert into public.posts (user_id, caption, image_url, outfit_id, tags)
                values ($1::uuid, $2, $3, $4, $5::text[])
                returning id
                """,
                user.id,
                body.caption,
                body.image_url,
                str(body.outfit_id) if body.outfit_id else None,
                body.tags,
            )
            if body.poll is not None:
                await conn.execute(
                    """
                    insert into public.post_polls (post_id, question, options, closes_at)
                    values ($1::uuid, $2, $3::jsonb, $4)
                    """,
                    str(post_id),
                    body.poll.question,
                    json.dumps([{"index": i, "label": o} for i, o in enumerate(body.poll.options)]),
                    body.poll.closes_at,
                )
            row = await conn.fetchrow(
                _FEED_SELECT + " where p.id = $2::uuid", user.id, str(post_id)
            )
            polls = await load_polls_for_posts(conn, user.id, [str(post_id)])
            avatar = await resolve_private_path(conn, row["author_avatar"], _PROFILE_PIC_BUCKET)
            response = _post_from_row(
                row, polls.get(str(post_id)), avatar_url=avatar
            ).model_dump(mode="json")
            await store_response(
                conn, idempotency_key, user.id, _CREATE_POST_ENDPOINT, 201, response
            )
    return JSONResponse(status_code=201, content=response)


@router.patch("/social/posts/{post_id}", response_model=PostResponse)
async def edit_post(
    post_id: UUID,
    body: PostUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> PostResponse:
    """Edit your OWN post (FEATURES_COMMUNITY_PLUS · Post Edit). Owner-only (the
    UPDATE is scoped to user_id, §11), the new image + caption are re-moderated
    before they go public (§19), and the post is stamped edited."""
    # Keep emails out of public captions on edit too (§10) — reject before any work.
    _reject_email_caption(body.caption)
    # A referenced outfit must still be the caller's own (§11).
    if body.outfit_id is not None:
        async with get_pool().acquire() as conn:
            owns = await conn.fetchval(
                "select 1 from public.outfits where id = $1::uuid and user_id = $2::uuid",
                str(body.outfit_id),
                user.id,
            )
        if owns is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That outfit isn't yours.", 422)

    # Same durable-fetch + byte-moderation as create (a replaced image may be
    # freshly uploaded), so an edit never fails on a not-yet-served image (§19).
    moderation_image = await _fetch_for_moderation(body.image_url)
    await _moderate_post_image(user.id, moderation_image)
    await _moderate_text(user.id, body.caption, kind="caption")

    async with get_pool().acquire() as conn:
        # A moderated account can't edit/republish either (admin §13).
        await _assert_can_write(conn, user.id)
        updated = await conn.fetchval(
            """
            update public.posts
               set caption = $3, image_url = $4, outfit_id = $5, tags = $6::text[],
                   is_edited = true, edited_at = now()
             where id = $1::uuid and user_id = $2::uuid
            returning id
            """,
            str(post_id),
            user.id,
            body.caption,
            body.image_url,
            str(body.outfit_id) if body.outfit_id else None,
            body.tags,
        )
        if updated is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Post not found.", 404)
        row = await conn.fetchrow(_FEED_SELECT + " where p.id = $2::uuid", user.id, str(post_id))
        polls = await load_polls_for_posts(conn, user.id, [str(post_id)])
        avatar = await resolve_private_path(conn, row["author_avatar"], _PROFILE_PIC_BUCKET)
    return _post_from_row(row, polls.get(str(post_id)), avatar_url=avatar)


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
            """
            + _FEED_MOD_WHERE
            + """
             order by p.created_at desc
             limit $3
            """,
            user.id,
            before,
            limit,
        )
        return await _posts_with_polls(conn, user.id, rows)


@router.delete("/social/posts/{post_id}", status_code=204)
async def delete_post(
    post_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            "delete from public.posts where id = $1::uuid and user_id = $2::uuid "
            "returning id, image_url",
            str(post_id),
            user.id,
        )
        if row is None:
            # Server-authoritative delete (§13): a real post id that affects 0 rows
            # means it doesn't exist or isn't owned by the caller — fail loudly and
            # log both ids so an id/user mismatch is debuggable, never a silent 204.
            log.warning(
                "delete_post affected 0 rows: post %s not found or not owned by user %s",
                post_id,
                user.id,
            )
            raise ApiError(ErrorCode.NOT_FOUND, "Post not found.", 404)
        # Erase the post image (removes public reachability at once, §10).
        await delete_content_media(conn, "post", str(post_id), [("post", row["image_url"])])
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
            # Notify the post owner of a new like (best-effort, not self).
            owner = await conn.fetchval(
                "select user_id from public.posts where id = $1::uuid", str(post_id)
            )
            if owner is not None:
                await create_notification(
                    conn,
                    user_id=str(owner),
                    actor_id=user.id,
                    type="like",
                    title=f"{await actor_name(conn, user.id)} liked your look",
                    target_type="post",
                    target_id=str(post_id),
                )
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
        # A moderated account (banned/suspended/deleted) can't comment (admin §13).
        await _assert_can_write(conn, user.id)
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
        # Notify the post owner of a new comment (best-effort, not self).
        owner = await conn.fetchval(
            "select user_id from public.posts where id = $1::uuid", str(post_id)
        )
        if owner is not None:
            await create_notification(
                conn,
                user_id=str(owner),
                actor_id=user.id,
                type="comment",
                title=f"{await actor_name(conn, user.id)} commented on your look",
                body=body.body[:140],
                target_type="post",
                target_id=str(post_id),
            )
        row = await conn.fetchrow(_COMMENT_SELECT + " where c.id = $1::uuid", str(comment_id))
        avatar = await resolve_private_path(conn, row["author_avatar"], _PROFILE_PIC_BUCKET)
    return _comment_from_row(row, avatar_url=avatar)


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
               and c.status = 'published'
               and ($2::timestamptz is null or c.created_at < $2::timestamptz)
             order by c.created_at desc
             limit $3
            """,
            str(post_id),
            before,
            limit,
        )
        avatars = await _resolve_avatars(conn, (r["author_avatar"] for r in rows))
    return [_comment_from_row(r, avatar_url=avatars.get(r["author_avatar"])) for r in rows]


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
            inserted = await conn.fetchval(
                "insert into public.follows (follower_id, followee_id) "
                "values ($1::uuid, $2::uuid) on conflict do nothing "
                "returning follower_id",
                user.id,
                str(followee_id),
            )
        except asyncpg.ForeignKeyViolationError as exc:
            raise ApiError(ErrorCode.NOT_FOUND, "User not found.", 404) from exc
        if inserted is not None:  # only on a genuinely new follow
            await create_notification(
                conn,
                user_id=str(followee_id),
                actor_id=user.id,
                type="follow",
                title=f"{await actor_name(conn, user.id)} started following you",
                target_type="user",
                target_id=user.id,
            )
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


# ── public creator profiles (CLAUDE.md §1 pillar 4) ──────────────────────────
# Served by the backend (service-role) so only the SAFE public columns leave the
# DB — sensitive fields (phone/body_data/private photos) never appear here (§10).


async def _assert_visible(conn: asyncpg.Connection, caller_id: str, target_id: str) -> bool:
    """Raise 404 if the target can't be shown to the caller: missing, blocked
    either way, or private (and not the caller's own). Returns is_me."""
    is_me = target_id == caller_id
    row = await conn.fetchrow(
        "select is_public, account_status from public.profiles where id = $1::uuid",
        target_id,
    )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "User not found.", 404)
    if not is_me:
        blocked = await conn.fetchval(
            """
            select 1 from public.blocks b
             where (b.blocker_id = $1::uuid and b.blocked_id = $2::uuid)
                or (b.blocker_id = $2::uuid and b.blocked_id = $1::uuid)
            """,
            caller_id,
            target_id,
        )
        # Deleted users are gone from discovery/public profiles (admin §13); blocked
        # either way or private profiles stay hidden too.
        if blocked is not None or not row["is_public"] or row["account_status"] == "deleted":
            raise ApiError(ErrorCode.NOT_FOUND, "User not found.", 404)
    return is_me


def _card_from_row(
    row: asyncpg.Record, caller_id: str, *, avatar_url: str | None = None
) -> PublicUserCard:
    return PublicUserCard(
        user_id=str(row["user_id"]),
        display_name=public_display_name(row["display_name"]),
        username=public_display_name(row["username"]),
        style_tags=list(row["style_tags"]) if row["style_tags"] is not None else [],
        is_following=row["is_following"],
        is_me=str(row["user_id"]) == caller_id,
        avatar_url=avatar_url,
    )


@router.get("/social/users/{user_id}", response_model=PublicProfileResponse)
async def get_public_profile(
    user_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> PublicProfileResponse:
    async with get_pool().acquire() as conn:
        is_me = await _assert_visible(conn, user.id, str(user_id))
        row = await conn.fetchrow(
            """
            select pr.id, pr.display_name, pr.username, pr.bio, pr.style_tags,
                   pr.is_official, pr.public_label, pr.profile_picture_url,
                   (select count(*) from public.follows f where f.followee_id = pr.id)
                     as follower_count,
                   (select count(*) from public.follows f where f.follower_id = pr.id)
                     as following_count,
                   (select count(*) from public.posts p
                     where p.user_id = pr.id and p.visibility = 'public'
                       and p.status = 'published') as post_count,
                   exists(
                     select 1 from public.follows f
                      where f.follower_id = $1::uuid and f.followee_id = pr.id
                   ) as is_following
              from public.profiles pr
             where pr.id = $2::uuid
            """,
            user.id,
            str(user_id),
        )
        # The DISPLAY picture (the user's chosen public photo — never the try-on
        # photo, §10), signed for serving like GET /v1/profile does.
        avatar_url = await resolve_private_path(
            conn, row["profile_picture_url"], "profile-pictures"
        )
    return PublicProfileResponse(
        user_id=str(row["id"]),
        # Public profile must never leak an email if one was saved as the name (§10).
        display_name=public_display_name(row["display_name"]),
        username=public_display_name(row["username"]),
        is_official=bool(row["is_official"]),
        official_label=row["public_label"],
        bio=row["bio"],
        style_tags=list(row["style_tags"]) if row["style_tags"] is not None else [],
        follower_count=row["follower_count"],
        following_count=row["following_count"],
        post_count=row["post_count"],
        is_following=row["is_following"],
        is_me=is_me,
        avatar_url=avatar_url,
    )


@router.get("/social/users/{user_id}/posts", response_model=list[PostResponse])
async def get_user_posts(
    user_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(30, ge=1, le=50),
    before: datetime | None = Query(None),
) -> list[PostResponse]:
    """A creator's own public posts, newest first (their profile "Looks" tab)."""
    async with get_pool().acquire() as conn:
        await _assert_visible(conn, user.id, str(user_id))
        rows = await conn.fetch(
            _FEED_SELECT
            + """
             where p.user_id = $2::uuid
               and p.visibility = 'public'
               and ($3::timestamptz is null or p.created_at < $3::timestamptz)
            """
            + _FEED_MOD_WHERE
            + """
             order by p.created_at desc
             limit $4
            """,
            user.id,
            str(user_id),
            before,
            limit,
        )
        return await _posts_with_polls(conn, user.id, rows)


# user this user follows / is followed by — safe public cards only.
_FOLLOW_LIST_SELECT = """
    select pr.id as user_id, pr.display_name, pr.username, pr.style_tags,
           pr.profile_picture_url as avatar,
           exists(
             select 1 from public.follows me
              where me.follower_id = $1::uuid and me.followee_id = pr.id
           ) as is_following
      from public.follows f
      join public.profiles pr on pr.id = {join_col}
     where f.{filter_col} = $2::uuid
     order by f.created_at desc
     limit $3
"""


@router.get("/social/users/{user_id}/followers", response_model=list[PublicUserCard])
async def get_followers(
    user_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
) -> list[PublicUserCard]:
    async with get_pool().acquire() as conn:
        await _assert_visible(conn, user.id, str(user_id))
        rows = await conn.fetch(
            _FOLLOW_LIST_SELECT.format(join_col="f.follower_id", filter_col="followee_id"),
            user.id,
            str(user_id),
            limit,
        )
        avatars = await _resolve_avatars(conn, (r["avatar"] for r in rows))
    return [_card_from_row(r, user.id, avatar_url=avatars.get(r["avatar"])) for r in rows]


@router.get("/social/users/{user_id}/following", response_model=list[PublicUserCard])
async def get_following(
    user_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(50, ge=1, le=100),
) -> list[PublicUserCard]:
    async with get_pool().acquire() as conn:
        await _assert_visible(conn, user.id, str(user_id))
        rows = await conn.fetch(
            _FOLLOW_LIST_SELECT.format(join_col="f.followee_id", filter_col="follower_id"),
            user.id,
            str(user_id),
            limit,
        )
        avatars = await _resolve_avatars(conn, (r["avatar"] for r in rows))
    return [_card_from_row(r, user.id, avatar_url=avatars.get(r["avatar"])) for r in rows]


@router.get("/social/users/{user_id}/closet", response_model=list[PublicClosetItem])
async def get_user_closet(
    user_id: UUID,
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(60, ge=1, le=200),
) -> list[PublicClosetItem]:
    """A creator's PUBLIC closet — returned ONLY when they've opted in via
    profiles.show_public_closet (else an empty list). Safe item fields only —
    never cost/brand/wear data or any private profile data (§10)."""
    async with get_pool().acquire() as conn:
        await _assert_visible(conn, user.id, str(user_id))
        shows = await conn.fetchval(
            "select show_public_closet from public.profiles where id = $1::uuid",
            str(user_id),
        )
        if not shows:
            return []  # closet not shared — safe empty/locked state
        rows = await conn.fetch(
            """
            select id, title, category, color, image_url, cutout_url, thumbnail_url
              from public.wardrobe_items
             where user_id = $1::uuid
             order by created_at desc
             limit $2
            """,
            str(user_id),
            limit,
        )
        # Wardrobe is private (F2): R2 items resolve to signed URLs, legacy items
        # pass through. Batched so the page isn't fetched one image at a time (§8).
        assets = await resolve_images(
            conn, "wardrobe_item", [r["id"] for r in rows], ("original", "cutout")
        )
    items: list[PublicClosetItem] = []
    for r in rows:
        original = assets.get((str(r["id"]), "original"))
        cutout = assets.get((str(r["id"]), "cutout"))
        items.append(
            PublicClosetItem(
                id=str(r["id"]),
                title=r["title"],
                category=r["category"],
                color=r["color"],
                image_url=original.url if (original and original.url) else r["image_url"],
                cutout_url=cutout.url if (cutout and cutout.url) else r["cutout_url"],
                thumbnail_url=(
                    cutout.thumb_url if (cutout and cutout.thumb_url) else r["thumbnail_url"]
                ),
            )
        )
    return items


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


# ── Style-Score leaderboard (CLAUDE.md §1 pillar 4, §24) ─────────────────────

# Per user, over THIS month's posts: likes*1 + comments*3 + 5 per post, counting
# only OTHER users' likes/comments (no self-engagement — anti-gaming).
_RANKED_CTE = """
with post_scores as (
  select p.user_id,
         5
         + (select count(*) from public.likes l
              where l.post_id = p.id and l.user_id <> p.user_id)
         + 3 * (select count(*) from public.comments c
                  where c.post_id = p.id and c.user_id <> p.user_id) as score
    from public.posts p
   where p.created_at >= date_trunc('month', now())
),
ranked as (
  select us.user_id, pr.display_name, pr.username, us.score,
         rank() over (order by us.score desc) as rnk
    from (select user_id, sum(score)::int as score
            from post_scores group by user_id) us
    join public.profiles pr on pr.id = us.user_id
)
"""


@router.get("/social/leaderboard", response_model=LeaderboardResponse)
async def leaderboard(
    limit: int = Query(default=20, ge=1, le=100),
    user: CurrentUser = Depends(get_current_user),
) -> LeaderboardResponse:
    async with get_pool().acquire() as conn:
        top = await conn.fetch(
            _RANKED_CTE + " select user_id, display_name, username, score, rnk from ranked"
            " order by rnk, display_name limit $1",
            limit,
        )
        mine = await conn.fetchrow(
            _RANKED_CTE + " select rnk, score from ranked where user_id = $1::uuid",
            user.id,
        )
        winners = await conn.fetch(
            """
            select to_char(a.period_month, 'YYYY-MM') as month,
                   pr.display_name, pr.username, a.score
              from public.community_awards a
              join public.profiles pr on pr.id = a.user_id
             order by a.period_month desc
             limit 6
            """
        )
        month = await conn.fetchval("select to_char(date_trunc('month', now()), 'YYYY-MM')")

    return LeaderboardResponse(
        month=month,
        entries=[
            LeaderboardEntry(
                rank=r["rnk"],
                user_id=str(r["user_id"]),
                display_name=public_display_name(r["display_name"], r["username"]),
                score=r["score"],
                is_me=str(r["user_id"]) == user.id,
            )
            for r in top
        ],
        my_rank=mine["rnk"] if mine else None,
        my_score=mine["score"] if mine else 0,
        recent_winners=[
            PastWinner(
                month=w["month"],
                display_name=public_display_name(w["display_name"], w["username"]),
                score=w["score"],
            )
            for w in winners
        ],
    )
