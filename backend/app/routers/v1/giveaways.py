"""Giveaways (FEATURES_COMMUNITY_PLUS · Giveaway) — peer-to-peer free clothes.

Safety is the priority (§19, §10):
  * listing images + text are moderated before publish;
  * contact is in-app only via a private claim message — no address/phone in
    public listings;
  * one claim per user (idempotent); the owner accepts/declines and can close;
  * blocked owners are filtered out of browse; reuse the existing report/block.
"""

from __future__ import annotations

import json
import logging
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.giveaway import (
    ChatMessageCreate,
    ChatMessageResponse,
    ChatReportCreate,
    ClaimCreate,
    ClaimDecision,
    ClaimResponse,
    GiveawayCreate,
    GiveawayResponse,
    GiveawayStatusUpdate,
    PickupChatResponse,
    PickupPlanUpdate,
)
from app.services.display import public_display_name
from app.services.media.deletion import delete_content_media
from app.services.media.repo import resolve_image_list
from app.services.moderation import get_moderator
from app.services.notifications import actor_name, create_notification

log = logging.getLogger("fashionos.giveaways")

router = APIRouter(tags=["giveaways"])

_GIVEAWAY_SELECT = """
    select g.id, g.owner_id, pr.display_name as owner_name, g.wardrobe_item_id,
           g.title, g.description, g.images, g.size, g.category, g.condition,
           g.area_label, g.status, g.created_at,
           (select c.status from public.giveaway_claims c
             where c.giveaway_id = g.id and c.claimer_id = $1::uuid) as my_claim_status,
           (select count(*) from public.giveaway_claims c
             where c.giveaway_id = g.id) as claim_count
      from public.giveaways g
      join public.profiles pr on pr.id = g.owner_id
"""


def _jsonb(value: object) -> object:
    return json.loads(value) if isinstance(value, str) else value


async def _giveaway_from_row(
    conn: asyncpg.Connection, row: asyncpg.Record, caller_id: str
) -> GiveawayResponse:
    # Resolve the public images array via media_assets: R2 CDN url + a thumbnail
    # for the grid where available; legacy/new urls pass through unchanged.
    raw = [str(u) for u in (_jsonb(row["images"]) or [])]
    resolved = await resolve_image_list(conn, "giveaway", row["id"], "giveaway", raw)
    images = [r.url for r in resolved if r.url]
    thumbnails = [(r.thumb_url or r.url) for r in resolved if (r.thumb_url or r.url)]
    return GiveawayResponse(
        id=str(row["id"]),
        owner_id=str(row["owner_id"]),
        owner_name=row["owner_name"],
        wardrobe_item_id=str(row["wardrobe_item_id"]) if row["wardrobe_item_id"] else None,
        title=row["title"],
        description=row["description"],
        images=images,
        thumbnails=thumbnails,
        size=row["size"],
        category=row["category"],
        condition=row["condition"],
        area_label=row["area_label"],
        status=row["status"],
        is_mine=str(row["owner_id"]) == caller_id,
        my_claim_status=row["my_claim_status"],
        claim_count=row["claim_count"],
        created_at=row["created_at"],
    )


def _claim_from_row(row: asyncpg.Record) -> ClaimResponse:
    return ClaimResponse(
        id=str(row["id"]),
        giveaway_id=str(row["giveaway_id"]),
        claimer_id=str(row["claimer_id"]),
        claimer_name=row["claimer_name"],
        message=row["message"],
        status=row["status"],
        created_at=row["created_at"],
    )


async def _moderate_listing(user_id: str, body: GiveawayCreate) -> None:
    """Moderate every listing image + the title/description before publish (§19)."""
    moderator = get_moderator()
    for url in body.images:
        result = await moderator.check_image(url)
        if not result.allowed:
            log.warning("giveaway image blocked for %s (%s)", user_id, result.reason)
            raise ApiError(ErrorCode.MODERATION_BLOCKED, "That image can't be listed.", 422)
    for text in (body.title, body.description):
        if text and text.strip():
            result = await moderator.check_text(text)
            if not result.allowed:
                log.warning("giveaway text blocked for %s (%s)", user_id, result.reason)
                raise ApiError(ErrorCode.MODERATION_BLOCKED, "That text can't be listed.", 422)


# ── create + browse ──────────────────────────────────────────────────────────


@router.post("/giveaways", status_code=201, response_model=GiveawayResponse)
async def create_giveaway(
    body: GiveawayCreate,
    user: CurrentUser = Depends(get_current_user),
) -> GiveawayResponse:
    # A linked wardrobe item must be the caller's own (§11).
    if body.wardrobe_item_id is not None:
        async with get_pool().acquire() as conn:
            owns = await conn.fetchval(
                "select 1 from public.wardrobe_items where id = $1::uuid and user_id = $2::uuid",
                str(body.wardrobe_item_id),
                user.id,
            )
        if owns is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "That item isn't yours.", 422)

    await _moderate_listing(user.id, body)

    async with get_pool().acquire() as conn:
        gid = await conn.fetchval(
            """
            insert into public.giveaways
              (owner_id, wardrobe_item_id, title, description, images, size,
               category, condition, area_label)
            values ($1::uuid, $2, $3, $4, $5::jsonb, $6, $7, $8, $9)
            returning id
            """,
            user.id,
            str(body.wardrobe_item_id) if body.wardrobe_item_id else None,
            body.title,
            body.description,
            json.dumps(body.images),
            body.size,
            body.category,
            body.condition,
            body.area_label,
        )
        row = await conn.fetchrow(_GIVEAWAY_SELECT + " where g.id = $2::uuid", user.id, str(gid))
        return await _giveaway_from_row(conn, row, user.id)


@router.get("/giveaways", response_model=list[GiveawayResponse])
async def browse_giveaways(
    user: CurrentUser = Depends(get_current_user),
    category: str | None = Query(None),
    size: str | None = Query(None),
    limit: int = Query(30, ge=1, le=60),
) -> list[GiveawayResponse]:
    """Available listings, newest first. Blocked owners are filtered out (§19)."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _GIVEAWAY_SELECT
            + """
             where g.status = 'available'
               and g.hidden_at is null and g.deleted_at is null
               and ($2::text is null or g.category = $2)
               and ($3::text is null or g.size = $3)
               and not exists (
                 select 1 from public.blocks b
                  where (b.blocker_id = $1::uuid and b.blocked_id = g.owner_id)
                     or (b.blocker_id = g.owner_id and b.blocked_id = $1::uuid)
               )
             order by g.created_at desc
             limit $4
            """,
            user.id,
            category,
            size,
            limit,
        )
        return [await _giveaway_from_row(conn, r, user.id) for r in rows]


@router.get("/giveaways/mine", response_model=list[GiveawayResponse])
async def my_giveaways(
    user: CurrentUser = Depends(get_current_user),
) -> list[GiveawayResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _GIVEAWAY_SELECT
            + " where g.owner_id = $1::uuid and g.deleted_at is null"
            + " order by g.created_at desc",
            user.id,
        )
        return [await _giveaway_from_row(conn, r, user.id) for r in rows]


@router.get("/giveaways/{giveaway_id}", response_model=GiveawayResponse)
async def get_giveaway(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> GiveawayResponse:
    async with get_pool().acquire() as conn:
        # An admin-hidden listing stays visible to its owner only; a soft-deleted
        # one is gone for everyone (moderation columns, migration 0038).
        row = await conn.fetchrow(
            _GIVEAWAY_SELECT
            + " where g.id = $2::uuid and g.deleted_at is null"
            + " and (g.hidden_at is null or g.owner_id = $1::uuid)",
            user.id,
            str(giveaway_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        return await _giveaway_from_row(conn, row, user.id)


# ── claims ───────────────────────────────────────────────────────────────────


@router.post("/giveaways/{giveaway_id}/claim", status_code=201, response_model=ClaimResponse)
async def claim_giveaway(
    giveaway_id: UUID,
    body: ClaimCreate,
    user: CurrentUser = Depends(get_current_user),
) -> ClaimResponse:
    """Request an item. One claim per user (idempotent via the unique key — a
    repeat returns the existing claim). Can't claim your own or a non-available
    listing. The message is private to the owner (in-app contact only, §10)."""
    if body.message and body.message.strip():
        result = await get_moderator().check_text(body.message)
        if not result.allowed:
            raise ApiError(ErrorCode.MODERATION_BLOCKED, "That message can't be sent.", 422)

    async with get_pool().acquire() as conn:
        giveaway = await conn.fetchrow(
            "select owner_id, status, hidden_at, deleted_at "
            "from public.giveaways where id = $1::uuid",
            str(giveaway_id),
        )
        if giveaway is None or giveaway["deleted_at"] is not None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        if str(giveaway["owner_id"]) == user.id:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't claim your own listing.", 422)
        # An admin-hidden listing can't collect new requests (0038).
        if giveaway["status"] != "available" or giveaway["hidden_at"] is not None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "This item is no longer available.", 422)

        # Idempotent: a repeat claim returns the existing one (no duplicate). A
        # previously CANCELLED request may be re-opened; declined/not_selected
        # ones stay settled (no nagging the owner).
        claim_id = await conn.fetchval(
            """
            insert into public.giveaway_claims (giveaway_id, claimer_id, message)
            values ($1::uuid, $2::uuid, $3)
            on conflict (giveaway_id, claimer_id) do update
              set status = 'requested', message = excluded.message,
                  updated_at = now()
            where giveaway_claims.status = 'cancelled'
            returning id
            """,
            str(giveaway_id),
            user.id,
            body.message,
        )
        if claim_id is not None:
            await create_notification(
                conn,
                user_id=str(giveaway["owner_id"]),
                actor_id=user.id,
                type="giveaway",
                title=f"{await actor_name(conn, user.id)} wants your giveaway",
                body=(body.message or "")[:140],
                target_type="giveaway",
                target_id=str(giveaway_id),
            )
        row = await conn.fetchrow(
            """
            select c.id, c.giveaway_id, c.claimer_id, pr.display_name as claimer_name,
                   c.message, c.status, c.created_at
              from public.giveaway_claims c
              join public.profiles pr on pr.id = c.claimer_id
             where c.giveaway_id = $1::uuid and c.claimer_id = $2::uuid
            """,
            str(giveaway_id),
            user.id,
        )
    return _claim_from_row(row)


@router.get("/giveaways/{giveaway_id}/claims", response_model=list[ClaimResponse])
async def list_claims(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> list[ClaimResponse]:
    """The claims on a listing — OWNER ONLY (§10)."""
    async with get_pool().acquire() as conn:
        owner_id = await conn.fetchval(
            "select owner_id from public.giveaways where id = $1::uuid", str(giveaway_id)
        )
        if owner_id is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        if str(owner_id) != user.id:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        rows = await conn.fetch(
            """
            select c.id, c.giveaway_id, c.claimer_id, pr.display_name as claimer_name,
                   c.message, c.status, c.created_at
              from public.giveaway_claims c
              join public.profiles pr on pr.id = c.claimer_id
             where c.giveaway_id = $1::uuid
             order by c.created_at
            """,
            str(giveaway_id),
        )
    return [_claim_from_row(r) for r in rows]


@router.patch("/giveaways/{giveaway_id}/claims/{claim_id}", response_model=ClaimResponse)
async def decide_claim(
    giveaway_id: UUID,
    claim_id: UUID,
    body: ClaimDecision,
    user: CurrentUser = Depends(get_current_user),
) -> ClaimResponse:
    """Owner accepts/declines a request. Accepting ONE requester reserves the
    listing, opens the 7-day secret pickup chat with them, and marks every other
    pending request `not_selected` (who was picked is never exposed, §10).
    Declining an already-accepted requester also cancels their chat and reopens
    the listing."""
    async with get_pool().acquire() as conn:
        giveaway = await conn.fetchrow(
            "select owner_id, status, hidden_at, deleted_at "
            "from public.giveaways where id = $1::uuid",
            str(giveaway_id),
        )
        if (
            giveaway is None
            or str(giveaway["owner_id"]) != user.id
            or giveaway["deleted_at"] is not None
        ):
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)

        claim = await conn.fetchrow(
            "select claimer_id, status from public.giveaway_claims "
            "where id = $1::uuid and giveaway_id = $2::uuid",
            str(claim_id),
            str(giveaway_id),
        )
        if claim is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Claim not found.", 404)
        claimer_id = str(claim["claimer_id"])

        async with conn.transaction():
            if body.status == "accepted":
                # A hidden listing can't start a new pickup (declines still work).
                if (
                    giveaway["status"] not in ("available", "reserved")
                    or giveaway["hidden_at"] is not None
                ):
                    raise ApiError(
                        ErrorCode.VALIDATION_ERROR, "This listing is no longer open.", 422
                    )
                if claim["status"] not in ("requested", "accepted"):
                    raise ApiError(
                        ErrorCode.VALIDATION_ERROR, "That request is no longer open.", 422
                    )
                # Only one live pickup at a time per listing.
                active_with = await conn.fetchval(
                    "select requester_id from public.giveaway_pickup_chats "
                    "where giveaway_id = $1::uuid and status = 'active'",
                    str(giveaway_id),
                )
                if active_with is not None and str(active_with) != claimer_id:
                    raise ApiError(
                        ErrorCode.VALIDATION_ERROR,
                        "Another pickup is already in progress — cancel it first.",
                        422,
                    )
                await conn.execute(
                    "update public.giveaway_claims set status = 'accepted', "
                    "updated_at = now() where id = $1::uuid",
                    str(claim_id),
                )
                # Everyone else still waiting quietly becomes not_selected.
                await conn.execute(
                    "update public.giveaway_claims set status = 'not_selected', "
                    "updated_at = now() "
                    "where giveaway_id = $1::uuid and id <> $2::uuid "
                    "and status = 'requested'",
                    str(giveaway_id),
                    str(claim_id),
                )
                await conn.execute(
                    "update public.giveaways set status = 'reserved', updated_at = now() "
                    "where id = $1::uuid",
                    str(giveaway_id),
                )
                await _open_pickup_chat(conn, str(giveaway_id), str(claim_id), user.id, claimer_id)
                if str(active_with or "") != claimer_id:  # don't re-notify on a repeat
                    await create_notification(
                        conn,
                        user_id=claimer_id,
                        actor_id=user.id,
                        type="giveaway",
                        title="You were picked! Open your secret pickup chat",
                        body="Arrange the pickup in-app within 7 days.",
                        target_type="giveaway",
                        target_id=str(giveaway_id),
                    )
            else:  # declined
                await conn.execute(
                    "update public.giveaway_claims set status = 'declined', "
                    "updated_at = now() where id = $1::uuid",
                    str(claim_id),
                )
                if claim["status"] == "accepted":
                    # Un-accepting: end their chat and put the listing back up.
                    await _resolve_active_chat(
                        conn, str(giveaway_id), "cancelled", requester_id=claimer_id
                    )
                    await conn.execute(
                        "update public.giveaways set status = 'available', "
                        "updated_at = now() where id = $1::uuid and status = 'reserved'",
                        str(giveaway_id),
                    )
                await create_notification(
                    conn,
                    user_id=claimer_id,
                    actor_id=user.id,
                    type="giveaway",
                    title="Your giveaway request was declined",
                    target_type="giveaway",
                    target_id=str(giveaway_id),
                )
        row = await conn.fetchrow(
            """
            select c.id, c.giveaway_id, c.claimer_id, pr.display_name as claimer_name,
                   c.message, c.status, c.created_at
              from public.giveaway_claims c
              join public.profiles pr on pr.id = c.claimer_id
             where c.id = $1::uuid
            """,
            str(claim_id),
        )
    return _claim_from_row(row)


@router.patch("/giveaways/{giveaway_id}", response_model=GiveawayResponse)
async def update_giveaway_status(
    giveaway_id: UUID,
    body: GiveawayStatusUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> GiveawayResponse:
    """Owner transitions the listing (e.g. close it). Owner-only (scoped UPDATE).
    Marking it given (`claimed`) completes any live pickup chat and tells the
    requester; closing or reopening cancels the chat instead — either way the
    chat locks immediately and the cleanup cron redacts it later."""
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            updated = await conn.fetchval(
                "update public.giveaways set status = $3, updated_at = now() "
                "where id = $1::uuid and owner_id = $2::uuid returning id",
                str(giveaway_id),
                user.id,
                body.status,
            )
            if updated is None:
                raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
            if body.status == "claimed":
                requester = await _resolve_active_chat(conn, str(giveaway_id), "completed")
                if requester is not None:
                    await create_notification(
                        conn,
                        user_id=requester,
                        actor_id=user.id,
                        type="giveaway",
                        title="Item marked as given — enjoy!",
                        target_type="giveaway",
                        target_id=str(giveaway_id),
                    )
            elif body.status in ("closed", "available"):
                requester = await _resolve_active_chat(conn, str(giveaway_id), "cancelled")
                if requester is not None:
                    # Their claim is settled too — the pickup is off.
                    await conn.execute(
                        "update public.giveaway_claims set status = 'not_selected', "
                        "updated_at = now() where giveaway_id = $1::uuid "
                        "and claimer_id = $2::uuid and status = 'accepted'",
                        str(giveaway_id),
                        requester,
                    )
                    await create_notification(
                        conn,
                        user_id=requester,
                        actor_id=user.id,
                        type="giveaway",
                        title="The pickup was cancelled by the owner",
                        target_type="giveaway",
                        target_id=str(giveaway_id),
                    )
        row = await conn.fetchrow(
            _GIVEAWAY_SELECT + " where g.id = $2::uuid", user.id, str(giveaway_id)
        )
        return await _giveaway_from_row(conn, row, user.id)


@router.delete("/giveaways/{giveaway_id}", status_code=204)
async def delete_giveaway(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Owner permanently removes a listing — deletes the row (claims cascade) and
    erases its public images (§10 / Phase 4A). Owner-only (scoped DELETE)."""
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            "delete from public.giveaways where id = $1::uuid and owner_id = $2::uuid "
            "returning images",
            str(giveaway_id),
            user.id,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        images = [str(u) for u in (_jsonb(row["images"]) or [])]
        await delete_content_media(
            conn, "giveaway", str(giveaway_id), [("giveaway", u) for u in images]
        )
    return Response(status_code=204)


# ── secret pickup chat (0037) ────────────────────────────────────────────────
# Owner ↔ the ONE accepted requester, for 7 days from the accept. Everything is
# participant-scoped with 404 (never 403 — existence must not leak, §10/§11).

_CHAT_ACTIVE_DAYS = 7

_CHAT_SELECT = """
    select c.id, c.giveaway_id, g.title as giveaway_title, c.claim_id,
           c.owner_id, c.requester_id, c.status, c.report_flag, c.pickup_plan,
           c.approved_at, c.expires_at, c.locked_at, c.completed_at, c.created_at,
           po.display_name as owner_display, po.username as owner_username,
           pr.display_name as requester_display, pr.username as requester_username
      from public.giveaway_pickup_chats c
      join public.giveaways g on g.id = c.giveaway_id
      join public.profiles po on po.id = c.owner_id
      join public.profiles pr on pr.id = c.requester_id
"""


def _chat_from_row(row: asyncpg.Record, caller_id: str) -> PickupChatResponse:
    is_owner = str(row["owner_id"]) == caller_id
    other_name = (
        public_display_name(row["requester_display"], row["requester_username"])
        if is_owner
        else public_display_name(row["owner_display"], row["owner_username"])
    )
    return PickupChatResponse(
        id=str(row["id"]),
        giveaway_id=str(row["giveaway_id"]),
        giveaway_title=row["giveaway_title"],
        owner_id=str(row["owner_id"]),
        requester_id=str(row["requester_id"]),
        other_name=other_name,
        is_owner=is_owner,
        status=row["status"],
        report_flag=row["report_flag"],
        pickup_plan=_jsonb(row["pickup_plan"]) or {},
        approved_at=row["approved_at"],
        expires_at=row["expires_at"],
        locked_at=row["locked_at"],
        completed_at=row["completed_at"],
        created_at=row["created_at"],
    )


async def _open_pickup_chat(
    conn: asyncpg.Connection,
    giveaway_id: str,
    claim_id: str,
    owner_id: str,
    requester_id: str,
) -> None:
    """Create the pickup chat for an accept (fresh 7-day window). Re-accepting
    the same pair after a cancel re-arms their existing row instead."""
    created = await conn.fetchval(
        f"""
        insert into public.giveaway_pickup_chats
          (giveaway_id, claim_id, owner_id, requester_id, expires_at)
        values ($1::uuid, $2::uuid, $3::uuid, $4::uuid,
                now() + interval '{_CHAT_ACTIVE_DAYS} days')
        on conflict (giveaway_id, requester_id) do nothing
        returning id
        """,
        giveaway_id,
        claim_id,
        owner_id,
        requester_id,
    )
    if created is None:
        await conn.execute(
            f"""
            update public.giveaway_pickup_chats
               set status = 'active', claim_id = $2::uuid, approved_at = now(),
                   expires_at = now() + interval '{_CHAT_ACTIVE_DAYS} days',
                   locked_at = null, completed_at = null, cancelled_at = null,
                   expiry_notified = false, updated_at = now()
             where giveaway_id = $1::uuid and requester_id = $3::uuid
               and status <> 'active'
            """,
            giveaway_id,
            claim_id,
            requester_id,
        )


async def _resolve_active_chat(
    conn: asyncpg.Connection,
    giveaway_id: str,
    outcome: str,  # 'completed' | 'cancelled'
    requester_id: str | None = None,
) -> str | None:
    """Lock the listing's active chat as [outcome] (immediately — the cron only
    redacts bodies later). Returns the requester to notify, or None."""
    return await conn.fetchval(
        f"""
        update public.giveaway_pickup_chats
           set status = $2,
               {"completed_at" if outcome == "completed" else "cancelled_at"} = now(),
               locked_at = coalesce(locked_at, now()), updated_at = now()
         where giveaway_id = $1::uuid and status = 'active'
           and ($3::uuid is null or requester_id = $3::uuid)
        returning requester_id
        """,
        giveaway_id,
        outcome,
        requester_id,
    )


async def _touch_chat_expiry(conn: asyncpg.Connection, chat_id: str) -> None:
    """Lazy expiry: flip a chat past its 7-day window to `expired` at read time,
    so locking is exact even between cleanup-cron runs."""
    await conn.execute(
        "update public.giveaway_pickup_chats set status = 'expired', "
        "locked_at = coalesce(locked_at, now()), updated_at = now() "
        "where id = $1::uuid and status = 'active' and now() >= expires_at",
        chat_id,
    )


async def _chat_row_for(conn: asyncpg.Connection, chat_id: str, user_id: str) -> asyncpg.Record:
    """The chat, participant-scoped — anyone else gets 404 (no existence leak)."""
    await _touch_chat_expiry(conn, chat_id)
    row = await conn.fetchrow(
        _CHAT_SELECT
        + " where c.id = $1::uuid and (c.owner_id = $2::uuid or c.requester_id = $2::uuid)",
        chat_id,
        user_id,
    )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Chat not found.", 404)
    return row


@router.delete("/giveaways/{giveaway_id}/claim", status_code=204)
async def cancel_claim(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Requester withdraws their own request. If it was the accepted one, the
    pickup chat locks immediately and the listing goes back up. Idempotent."""
    async with get_pool().acquire() as conn:
        claim = await conn.fetchrow(
            "select id, status from public.giveaway_claims "
            "where giveaway_id = $1::uuid and claimer_id = $2::uuid",
            str(giveaway_id),
            user.id,
        )
        if claim is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Request not found.", 404)
        if claim["status"] not in ("requested", "accepted"):
            return Response(status_code=204)  # already settled — nothing to do
        async with conn.transaction():
            await conn.execute(
                "update public.giveaway_claims set status = 'cancelled', "
                "updated_at = now() where id = $1::uuid",
                str(claim["id"]),
            )
            if claim["status"] == "accepted":
                await _resolve_active_chat(
                    conn, str(giveaway_id), "cancelled", requester_id=user.id
                )
                owner_id = await conn.fetchval(
                    "update public.giveaways set status = 'available', "
                    "updated_at = now() where id = $1::uuid and status = 'reserved' "
                    "returning owner_id",
                    str(giveaway_id),
                )
                if owner_id is not None:
                    await create_notification(
                        conn,
                        user_id=str(owner_id),
                        actor_id=user.id,
                        type="giveaway",
                        title=f"{await actor_name(conn, user.id)} withdrew from the pickup",
                        body="Your listing is available again.",
                        target_type="giveaway",
                        target_id=str(giveaway_id),
                    )
    return Response(status_code=204)


@router.get("/giveaways/{giveaway_id}/chat", response_model=PickupChatResponse)
async def get_pickup_chat(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> PickupChatResponse:
    """The caller's pickup chat on this listing (owner or accepted requester).
    Prefers the live chat, else the most recent locked one. 404 for everyone
    else — non-participants can't even learn a chat exists."""
    async with get_pool().acquire() as conn:
        chat_id = await conn.fetchval(
            """
            select id from public.giveaway_pickup_chats
             where giveaway_id = $1::uuid
               and (owner_id = $2::uuid or requester_id = $2::uuid)
             order by (status = 'active') desc, created_at desc
             limit 1
            """,
            str(giveaway_id),
            user.id,
        )
        if chat_id is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Chat not found.", 404)
        row = await _chat_row_for(conn, str(chat_id), user.id)
        return _chat_from_row(row, user.id)


@router.get("/giveaways/chats/{chat_id}/messages", response_model=list[ChatMessageResponse])
async def list_chat_messages(
    chat_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> list[ChatMessageResponse]:
    """All messages, oldest first (a 7-day two-person chat stays small; the app
    simply re-polls this). Redacted bodies come back null."""
    async with get_pool().acquire() as conn:
        await _chat_row_for(conn, str(chat_id), user.id)  # participant gate
        rows = await conn.fetch(
            "select id, chat_id, sender_id, body, body_deleted, created_at "
            "from public.giveaway_chat_messages where chat_id = $1::uuid "
            "order by created_at, id limit 500",
            str(chat_id),
        )
    return [
        ChatMessageResponse(
            id=str(r["id"]),
            chat_id=str(r["chat_id"]),
            sender_id=str(r["sender_id"]),
            is_mine=str(r["sender_id"]) == user.id,
            body=None if r["body_deleted"] else r["body"],
            body_deleted=r["body_deleted"],
            created_at=r["created_at"],
        )
        for r in rows
    ]


@router.post(
    "/giveaways/chats/{chat_id}/messages",
    status_code=201,
    response_model=ChatMessageResponse,
)
async def send_chat_message(
    chat_id: UUID,
    body: ChatMessageCreate,
    user: CurrentUser = Depends(get_current_user),
) -> ChatMessageResponse:
    """Send a text message (≤500 chars, moderated §19). Locked, completed,
    cancelled, or expired chats reject sends — the insert itself re-checks the
    active window so a race with expiry can't slip a message in."""
    result = await get_moderator().check_text(body.body)
    if not result.allowed:
        raise ApiError(ErrorCode.MODERATION_BLOCKED, "That message can't be sent.", 422)

    async with get_pool().acquire() as conn:
        chat = await _chat_row_for(conn, str(chat_id), user.id)  # participant gate
        row = await conn.fetchrow(
            """
            insert into public.giveaway_chat_messages (chat_id, sender_id, body)
            select $1::uuid, $2::uuid, $3
             where exists (
               select 1 from public.giveaway_pickup_chats c
                where c.id = $1::uuid and c.status = 'active' and now() < c.expires_at
                  and (c.owner_id = $2::uuid or c.requester_id = $2::uuid)
             )
            returning id, created_at
            """,
            str(chat_id),
            user.id,
            body.body,
        )
        if row is None:
            raise ApiError(
                ErrorCode.VALIDATION_ERROR, "This chat is locked — pickup time is over.", 422
            )
        recipient = (
            str(chat["requester_id"]) if str(chat["owner_id"]) == user.id else str(chat["owner_id"])
        )
        # Nudge the other side, but never stack unread pings for the same chat.
        unread = await conn.fetchval(
            "select 1 from public.notifications where user_id = $1::uuid "
            "and type = 'giveaway_message' and target_id = $2 and is_read = false",
            recipient,
            str(chat["giveaway_id"]),
        )
        if unread is None:
            await create_notification(
                conn,
                user_id=recipient,
                actor_id=user.id,
                type="giveaway_message",
                title=f"{await actor_name(conn, user.id)} sent a pickup message",
                body=body.body[:140],
                target_type="giveaway",
                target_id=str(chat["giveaway_id"]),
            )
    return ChatMessageResponse(
        id=str(row["id"]),
        chat_id=str(chat_id),
        sender_id=user.id,
        is_mine=True,
        body=body.body,
        body_deleted=False,
        created_at=row["created_at"],
    )


@router.post("/giveaways/chats/{chat_id}/plan", response_model=PickupChatResponse)
async def update_pickup_plan(
    chat_id: UUID,
    body: PickupPlanUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> PickupChatResponse:
    """Either participant updates the pickup plan card (general area, public
    landmark, time slot, confirmed) while the chat is active. Text is moderated —
    the card must stay free of addresses/phones like everything else (§10)."""
    for text in (body.area, body.landmark, body.time_slot):
        if text and text.strip():
            result = await get_moderator().check_text(text)
            if not result.allowed:
                raise ApiError(ErrorCode.MODERATION_BLOCKED, "That plan can't be saved.", 422)
    plan = {
        "area": (body.area or "").strip() or None,
        "landmark": (body.landmark or "").strip() or None,
        "time_slot": (body.time_slot or "").strip() or None,
        "confirmed": body.confirmed,
    }
    async with get_pool().acquire() as conn:
        await _chat_row_for(conn, str(chat_id), user.id)  # participant gate
        updated = await conn.fetchval(
            "update public.giveaway_pickup_chats set pickup_plan = $2::jsonb, "
            "updated_at = now() where id = $1::uuid and status = 'active' "
            "and now() < expires_at returning id",
            str(chat_id),
            json.dumps(plan),
        )
        if updated is None:
            raise ApiError(
                ErrorCode.VALIDATION_ERROR, "This chat is locked — pickup time is over.", 422
            )
        row = await _chat_row_for(conn, str(chat_id), user.id)
        return _chat_from_row(row, user.id)


@router.post("/giveaways/chats/{chat_id}/report", status_code=204)
async def report_pickup_chat(
    chat_id: UUID,
    body: ChatReportCreate,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Either participant reports the chat. Files a moderation report AND
    freezes the transcript: a reported chat is never redacted by cleanup until
    review clears the flag (§19)."""
    async with get_pool().acquire() as conn:
        await _chat_row_for(conn, str(chat_id), user.id)  # participant gate
        async with conn.transaction():
            await conn.execute(
                "update public.giveaway_pickup_chats set report_flag = true, "
                "updated_at = now() where id = $1::uuid",
                str(chat_id),
            )
            await conn.execute(
                "insert into public.reports (reporter_id, subject_type, subject_id, reason) "
                "values ($1::uuid, 'giveaway_chat', $2::uuid, $3)",
                user.id,
                str(chat_id),
                body.reason,
            )
    return Response(status_code=204)
