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
from fastapi import APIRouter, Depends, Query

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.giveaway import (
    ClaimCreate,
    ClaimDecision,
    ClaimResponse,
    GiveawayCreate,
    GiveawayResponse,
    GiveawayStatusUpdate,
)
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


def _giveaway_from_row(row: asyncpg.Record, caller_id: str) -> GiveawayResponse:
    return GiveawayResponse(
        id=str(row["id"]),
        owner_id=str(row["owner_id"]),
        owner_name=row["owner_name"],
        wardrobe_item_id=str(row["wardrobe_item_id"]) if row["wardrobe_item_id"] else None,
        title=row["title"],
        description=row["description"],
        images=[str(u) for u in (_jsonb(row["images"]) or [])],
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
    return _giveaway_from_row(row, user.id)


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
    return [_giveaway_from_row(r, user.id) for r in rows]


@router.get("/giveaways/mine", response_model=list[GiveawayResponse])
async def my_giveaways(
    user: CurrentUser = Depends(get_current_user),
) -> list[GiveawayResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _GIVEAWAY_SELECT + " where g.owner_id = $1::uuid order by g.created_at desc",
            user.id,
        )
    return [_giveaway_from_row(r, user.id) for r in rows]


@router.get("/giveaways/{giveaway_id}", response_model=GiveawayResponse)
async def get_giveaway(
    giveaway_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> GiveawayResponse:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            _GIVEAWAY_SELECT + " where g.id = $2::uuid", user.id, str(giveaway_id)
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
    return _giveaway_from_row(row, user.id)


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
            "select owner_id, status from public.giveaways where id = $1::uuid",
            str(giveaway_id),
        )
        if giveaway is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        if str(giveaway["owner_id"]) == user.id:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "You can't claim your own listing.", 422)
        if giveaway["status"] != "available":
            raise ApiError(ErrorCode.VALIDATION_ERROR, "This item is no longer available.", 422)

        # Idempotent: a repeat claim returns the existing one (no duplicate).
        claim_id = await conn.fetchval(
            """
            insert into public.giveaway_claims (giveaway_id, claimer_id, message)
            values ($1::uuid, $2::uuid, $3)
            on conflict (giveaway_id, claimer_id) do nothing
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


@router.patch(
    "/giveaways/{giveaway_id}/claims/{claim_id}", response_model=ClaimResponse
)
async def decide_claim(
    giveaway_id: UUID,
    claim_id: UUID,
    body: ClaimDecision,
    user: CurrentUser = Depends(get_current_user),
) -> ClaimResponse:
    """Owner accepts/declines a claim. Accepting reserves the listing and notifies
    the claimer so they can arrange pickup in-app."""
    async with get_pool().acquire() as conn:
        owner_id = await conn.fetchval(
            "select owner_id from public.giveaways where id = $1::uuid", str(giveaway_id)
        )
        if owner_id is None or str(owner_id) != user.id:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)

        async with conn.transaction():
            updated = await conn.fetchval(
                """
                update public.giveaway_claims set status = $3
                 where id = $1::uuid and giveaway_id = $2::uuid
                returning claimer_id
                """,
                str(claim_id),
                str(giveaway_id),
                body.status,
            )
            if updated is None:
                raise ApiError(ErrorCode.NOT_FOUND, "Claim not found.", 404)
            if body.status == "accepted":
                await conn.execute(
                    "update public.giveaways set status = 'reserved', updated_at = now() "
                    "where id = $1::uuid",
                    str(giveaway_id),
                )
            await create_notification(
                conn,
                user_id=str(updated),
                actor_id=user.id,
                type="giveaway",
                title=(
                    "Your giveaway claim was accepted"
                    if body.status == "accepted"
                    else "Your giveaway claim was declined"
                ),
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
    """Owner transitions the listing (e.g. close it). Owner-only (scoped UPDATE)."""
    async with get_pool().acquire() as conn:
        updated = await conn.fetchval(
            "update public.giveaways set status = $3, updated_at = now() "
            "where id = $1::uuid and owner_id = $2::uuid returning id",
            str(giveaway_id),
            user.id,
            body.status,
        )
        if updated is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Giveaway not found.", 404)
        row = await conn.fetchrow(
            _GIVEAWAY_SELECT + " where g.id = $2::uuid", user.id, str(giveaway_id)
        )
    return _giveaway_from_row(row, user.id)
