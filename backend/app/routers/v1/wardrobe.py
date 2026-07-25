"""Wardrobe CRUD — the digital almira (CLAUDE.md §1, §5).

List / add / remove the user's owned items, always scoped by the JWT user_id
(§11) with RLS as defense-in-depth. No credits and no async job here, so no
idempotency key (§9) is required. Background removal, auto-tagging and
embeddings (§2.2) are gated on storage/AI keys and arrive in later steps; they
will fill cutout_url / thumbnail_url / tags / embedding server-side — for now
the client supplies `image_url` directly.
"""

from __future__ import annotations

import asyncio
import logging
from decimal import Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, File, Query, Response, UploadFile

from app.core.config import get_settings
from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.rate_limit import enforce_rate_limit
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.wardrobe import (
    WardrobeAnalyticsResponse,
    WardrobeGap,
    WardrobeItemCreate,
    WardrobeItemResponse,
    WardrobeItemStat,
    WardrobeItemUpdate,
)
from app.queues import KIND_REMBG, enqueue_signal
from app.services.llm import get_embedder
from app.services.media import get_storage_provider
from app.services.media.deletion import delete_content_media
from app.services.media.repo import (
    insert_asset,
    replace_cutout_assets,
    resolve_images,
    resolve_private_path,
)
from app.services.storage import download_image

log = logging.getLogger("fashionos.wardrobe")

router = APIRouter(tags=["wardrobe"])

# AI Studio outputs (enhanced covers) live in this private bucket in legacy mode;
# R2 mode resolves them via media_assets. Matches the ai_jobs worker / ai_studio.
_GENERATED_BUCKET = "tryon-results"

# Columns returned by every endpoint — static identifiers, no user input.
_COLUMNS = (
    "id, title, category, subcategory, color, pattern, brand, "
    "image_url, cutout_url, thumbnail_url, cover_image_url, ai_enhanced, ai_status, "
    "tags, cost, purchase_date, "
    "last_worn_at, wear_count, cutout_status, created_at"
)


def _to_response(row: asyncpg.Record) -> WardrobeItemResponse:
    return WardrobeItemResponse(
        id=str(row["id"]),
        title=row["title"],
        category=row["category"],
        subcategory=row["subcategory"],
        color=row["color"],
        pattern=row["pattern"],
        brand=row["brand"],
        image_url=row["image_url"],
        cutout_url=row["cutout_url"],
        thumbnail_url=row["thumbnail_url"],
        # cover_image_url holds a stored ref (R2 key / private path); _with_media
        # signs it for display. ai_enhanced/ai_status drive the closet badge.
        cover_image_url=row["cover_image_url"],
        ai_enhanced=row["ai_enhanced"],
        ai_status=row["ai_status"],
        tags=list(row["tags"] or []),
        cost=float(row["cost"]) if row["cost"] is not None else None,
        purchase_date=row["purchase_date"],
        last_worn_at=row["last_worn_at"],
        wear_count=row["wear_count"],
        cutout_status=row["cutout_status"],
        created_at=row["created_at"],
    )


async def _with_media(
    conn: asyncpg.Connection, rows: list[asyncpg.Record]
) -> list[WardrobeItemResponse]:
    """Overlay media_assets-resolved URLs onto a wardrobe page (INFRA point A):
    R2 items get signed URLs, legacy items pass through unchanged. One query +
    one batched signing pass; INERT until items actually live in R2."""
    items = [_to_response(r) for r in rows]
    if not items:
        return items
    assets = await resolve_images(
        conn, "wardrobe_item", [r["id"] for r in rows], ("original", "cutout")
    )
    # The enhanced cover lives as a private ref (R2 key / tryon-results path);
    # sign each present one for display (rare, so a per-item sign is fine).
    has_cover = any(r["cover_image_url"] for r in rows)
    if not assets and not has_cover:
        return items
    resolved: list[WardrobeItemResponse] = []
    for item in items:
        updates: dict[str, str] = {}
        original = assets.get((item.id, "original"))
        cutout = assets.get((item.id, "cutout"))
        if original and original.url:
            updates["image_url"] = original.url
        if cutout and cutout.url:
            updates["cutout_url"] = cutout.url
            if cutout.thumb_url:
                updates["thumbnail_url"] = cutout.thumb_url
        if item.cover_image_url:
            signed = await resolve_private_path(conn, item.cover_image_url, _GENERATED_BUCKET)
            updates["cover_image_url"] = signed if signed else item.cover_image_url
        resolved.append(item.model_copy(update=updates) if updates else item)
    return resolved


# Lean column set for analytics — only what cost-per-wear needs.
_STAT_COLUMNS = "id, title, image_url, cutout_url, thumbnail_url, cost, wear_count"


def _item_stat(row: asyncpg.Record) -> WardrobeItemStat:
    cost = float(row["cost"]) if row["cost"] is not None else None
    wears = row["wear_count"] or 0
    cpw = round(cost / wears, 2) if (cost is not None and wears > 0) else None
    return WardrobeItemStat(
        id=str(row["id"]),
        title=row["title"],
        image_url=row["thumbnail_url"] or row["cutout_url"] or row["image_url"],
        cost=cost,
        wear_count=wears,
        cost_per_wear=cpw,
    )


def _analytics(rows: list[asyncpg.Record]) -> WardrobeAnalyticsResponse:
    """Cost-per-wear + ROI insights over the user's closet (§24). Pure function so
    it's unit-testable without a DB."""
    if not rows:
        return WardrobeAnalyticsResponse()

    priced = [r for r in rows if r["cost"] is not None]
    worn_priced = [r for r in priced if (r["wear_count"] or 0) > 0]
    never_worn_priced = [r for r in priced if (r["wear_count"] or 0) == 0]

    total_spend = round(sum(float(r["cost"]) for r in priced), 2) if priced else None
    priced_wears = sum((r["wear_count"] or 0) for r in priced)
    avg_cpw = (
        round(sum(float(r["cost"]) for r in priced) / priced_wears, 2) if priced_wears > 0 else None
    )

    most_worn_row = max(rows, key=lambda r: r["wear_count"] or 0)
    best_value_row = (
        min(worn_priced, key=lambda r: float(r["cost"]) / r["wear_count"]) if worn_priced else None
    )
    # Biggest waste: priciest never-worn piece, else worst cost-per-wear.
    if never_worn_priced:
        waste_row = max(never_worn_priced, key=lambda r: float(r["cost"]))
    elif worn_priced:
        waste_row = max(worn_priced, key=lambda r: float(r["cost"]) / r["wear_count"])
    else:
        waste_row = None

    return WardrobeAnalyticsResponse(
        item_count=len(rows),
        total_spend=total_spend,
        total_wears=sum((r["wear_count"] or 0) for r in rows),
        never_worn_count=sum(1 for r in rows if (r["wear_count"] or 0) == 0),
        avg_cost_per_wear=avg_cpw,
        most_worn=_item_stat(most_worn_row) if (most_worn_row["wear_count"] or 0) > 0 else None,
        best_value=_item_stat(best_value_row) if best_value_row else None,
        biggest_waste=_item_stat(waste_row) if waste_row else None,
    )


@router.get("/wardrobe/analytics", response_model=WardrobeAnalyticsResponse)
async def wardrobe_analytics(
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeAnalyticsResponse:
    """Cost-per-wear, wardrobe ROI, most/least worn (CLAUDE.md §24)."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"select {_STAT_COLUMNS} from public.wardrobe_items where user_id = $1::uuid",
            user.id,
        )
    return _analytics(rows)


# Capsule-wardrobe essentials (category, title, shop query). A gap is an
# essential the user owns none of — shoppable via /v1/shop/link (§24).
_ESSENTIALS = [
    ("Tops", "A versatile top", "versatile wardrobe tops"),
    ("Bottoms", "A go-to bottom", "versatile trousers"),
    ("Outerwear", "A layering jacket", "lightweight jacket"),
    ("Shoes", "Neutral shoes", "versatile neutral shoes"),
]


def _gaps(counts: dict[str, int]) -> list[WardrobeGap]:
    """Essentials the closet is missing (owns none of). Pure + unit-testable."""
    return [
        WardrobeGap(
            category=category,
            title=title,
            suggestion=query,
            owned_count=counts.get(category.lower(), 0),
        )
        for category, title, query in _ESSENTIALS
        if counts.get(category.lower(), 0) == 0
    ]


@router.get("/wardrobe/gaps", response_model=list[WardrobeGap])
async def wardrobe_gaps(
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeGap]:
    """Closet-gap analysis (CLAUDE.md §24): essentials the user is missing, each
    shoppable through shop-the-look."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            "select lower(category) as category, count(*) as n "
            "from public.wardrobe_items "
            "where user_id = $1::uuid and category is not null "
            "group by lower(category)",
            user.id,
        )
    counts = {r["category"]: r["n"] for r in rows}
    return _gaps(counts)


@router.get("/wardrobe", response_model=list[WardrobeItemResponse])
async def list_wardrobe(
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeItemResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"""
            select {_COLUMNS}
              from public.wardrobe_items
             where user_id = $1::uuid
             order by created_at desc
             limit 500
            """,
            user.id,
        )
        return await _with_media(conn, rows)


async def _semantic_search(
    conn: asyncpg.Connection, user_id: str, query: str, limit: int
) -> list[asyncpg.Record] | None:
    """Cosine-nearest items by embedding (§2.1). Returns None if no embedder is
    configured or the query embed fails, so the caller can fall back to keyword."""
    embedder = get_embedder()
    if embedder.name == "stub":
        return None
    try:
        vector = await embedder.embed(query)
    except Exception as exc:  # provider/network error -> graceful keyword fallback
        log.warning("search embed failed, falling back to keyword: %s", exc)
        return None
    vec_literal = "[" + ",".join(repr(float(x)) for x in vector) + "]"
    rows = await conn.fetch(
        f"""
        select {_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid and embedding is not null
         order by embedding <=> $2::vector
         limit $3
        """,
        user_id,
        vec_literal,
        limit,
    )
    # Cheap, but still an AI call — record it (§14).
    await conn.execute(
        """
        insert into public.ai_usage_log (user_id, provider, task, images, success)
        values ($1::uuid, $2, 'search_query', 0, true)
        """,
        user_id,
        embedder.name,
    )
    return rows


async def _keyword_search(
    conn: asyncpg.Connection, user_id: str, query: str, limit: int
) -> list[asyncpg.Record]:
    """Fallback when embeddings aren't available: match title/category/color or
    an exact tag."""
    return await conn.fetch(
        f"""
        select {_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid
           and (title ilike $2 or category ilike $2 or subcategory ilike $2
                or color ilike $2 or $3 = any(tags))
         order by created_at desc
         limit $4
        """,
        user_id,
        f"%{query}%",
        query.lower(),
        limit,
    )


@router.get("/wardrobe/search", response_model=list[WardrobeItemResponse])
async def search_wardrobe(
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=20, ge=1, le=100),
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeItemResponse]:
    """Semantic closet search (§2.1, §24). Embeds the query and ranks owned items
    by cosine similarity; falls back to keyword match when embeddings aren't
    available (no OpenAI key, or nothing embedded yet)."""
    async with get_pool().acquire() as conn:
        rows = await _semantic_search(conn, user.id, q, limit)
        if not rows:
            rows = await _keyword_search(conn, user.id, q, limit)
        return await _with_media(conn, rows)


@router.post("/wardrobe", status_code=201, response_model=WardrobeItemResponse)
async def add_wardrobe_item(
    body: WardrobeItemCreate,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    # asyncpg binds the numeric column from Decimal, not float.
    cost = Decimal(str(body.cost)) if body.cost is not None else None
    # R2 path: the client uploaded to R2 and sent an object_key. The column stores
    # the key; the read endpoints sign it on serve (§8). Legacy path: image_url.
    use_r2 = bool(body.object_key) and get_settings().r2_writes_enabled
    stored_image = body.object_key if use_r2 else body.image_url
    # Queue background removal only when there's an image to process (§2.2).
    cutout_status = "queued" if stored_image else None
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                f"""
                insert into public.wardrobe_items
                  (user_id, title, category, subcategory, color, pattern, brand,
                   image_url, cost, purchase_date, tags, cutout_status)
                values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                returning {_COLUMNS}
                """,
                user.id,
                body.title,
                body.category,
                body.subcategory,
                body.color,
                body.pattern,
                body.brand,
                stored_image,
                cost,
                body.purchase_date,
                body.tags,
                cutout_status,
            )
            if use_r2:
                await insert_asset(
                    conn,
                    owner_kind="wardrobe_item",
                    owner_id=row["id"],
                    role="original",
                    user_id=user.id,
                    visibility="private",
                    storage_provider="r2",
                    object_key=body.object_key,
                )
        # Resolve the (private) original to a signed URL for the response.
        resolved = await _with_media(conn, [row])
    # Wake the rembg worker for the cutout AFTER commit (§11.5, best-effort — the DO
    # bridge polls the DB, so the stub queue is harmless there; recovery re-signals).
    if cutout_status == "queued":
        if await enqueue_signal(KIND_REMBG, str(row["id"])):
            async with get_pool().acquire() as conn:
                await conn.execute(
                    "update public.wardrobe_items set cutout_last_signal_at = now() "
                    "where id = $1::uuid",
                    str(row["id"]),
                )
    return resolved[0]


# Columns the categorize/edit flow may write — a fixed allow-list so building the
# dynamic SET clause from field names can never inject (names are never user input).
_EDITABLE_COLUMNS = ("title", "category", "subcategory", "color")


@router.patch("/wardrobe/{item_id}", response_model=WardrobeItemResponse)
async def update_wardrobe_item(
    item_id: UUID,
    body: WardrobeItemUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Edit/categorize an owned item — name, category, subcategory, color
    (real-device polish). Only the fields the client actually sent are written
    (partial update), always scoped to the JWT user (§11)."""
    changes = body.model_dump(include=set(_EDITABLE_COLUMNS), exclude_unset=True)

    async with get_pool().acquire() as conn:
        if not changes:
            # Nothing to change — return the current row (still ownership-scoped).
            row = await conn.fetchrow(
                f"select {_COLUMNS} from public.wardrobe_items "
                "where id = $1::uuid and user_id = $2::uuid",
                str(item_id),
                user.id,
            )
        else:
            # $1 = id, $2 = user_id, then one placeholder per changed column.
            sets = ", ".join(f"{col} = ${i}" for i, col in enumerate(changes, start=3))
            row = await conn.fetchrow(
                f"""
                update public.wardrobe_items
                   set {sets}
                 where id = $1::uuid and user_id = $2::uuid
                returning {_COLUMNS}
                """,
                str(item_id),
                user.id,
                *changes.values(),
            )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    return _to_response(row)


@router.post("/wardrobe/{item_id}/wear", response_model=WardrobeItemResponse)
async def mark_worn(
    item_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Log a wear: +1 wear_count and stamp last_worn_at (feeds cost-per-wear, §24)."""
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            f"""
            update public.wardrobe_items
               set wear_count = wear_count + 1, last_worn_at = now()
             where id = $1::uuid and user_id = $2::uuid
            returning {_COLUMNS}
            """,
            str(item_id),
            user.id,
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    return _to_response(row)


# ── free cutout correction (Erase/Restore editor, § BG upgrade Phase 7) ──────
# Generous per-user cap: this endpoint spends NO credits and no AI, so it only
# needs to bound abusive rapid-fire uploads. Reuses the shared DB limiter (§12).
_CUTOUT_MASK_LIMIT = 40
_CUTOUT_MASK_WINDOW_SECONDS = 60


async def _read_capped(upload: UploadFile, cap: int) -> bytes:
    """Read an UploadFile into memory, aborting past ``cap`` bytes BEFORE decoding."""
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(64 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > cap:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "Mask upload is too large.", 413)
        chunks.append(chunk)
    return b"".join(chunks)


def _apply_uploaded_mask(original: bytes, mask_bytes: bytes, max_edge: int) -> tuple[bytes, bytes]:
    """Normalize the stored original with the SAME helper as automatic removal,
    decode + validate the uploaded mask, require an exact dimension match, preserve
    the soft alpha, and return ``(cutout_png, mask_png)``. Pure/CPU — run in a
    thread. Raises imaging.ImageValidationError on any invalid input (§11)."""
    from app.services.bg import imaging

    norm = imaging.normalize_source_image(original, max_edge=max_edge)
    mask = imaging.decode_uploaded_mask(mask_bytes, max_edge=max_edge)
    if mask.size != (norm.width, norm.height):
        raise imaging.ImageValidationError(
            f"Mask dimensions {mask.size} must match the image {(norm.width, norm.height)}."
        )
    mask = imaging.sanitize_soft_mask(mask)
    return imaging.compose_cutout_png(norm.image, mask), imaging.encode_mask_png(mask)


@router.put("/wardrobe/{item_id}/cutout-mask", response_model=WardrobeItemResponse)
async def replace_cutout_mask(
    item_id: UUID,
    mask: UploadFile = File(...),
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Free manual cutout correction (§ BG upgrade Phase 7). The client uploads a
    hand-edited PNG mask; the server re-composites the cutout from the ORIGINAL and
    atomically replaces the item's active cutout + editable mask. Spends NO credits,
    runs NO AI, and touches NO membership/paywall logic — purely a deterministic
    fix for rare automatic-segmentation errors."""
    settings = get_settings()
    # Feature gate: invisible (404) when the editor is off (§11).
    if not settings.cutout_editor_enabled:
        raise ApiError(ErrorCode.NOT_FOUND, "Not found.", 404)
    # The editor stores a PRIVATE cutout + mask; without R2 private writes there is
    # no safe home for them → clear feature-unavailable error (§11).
    if not settings.r2_writes_enabled:
        raise ApiError(ErrorCode.PROVIDER_ERROR, "Cutout editing is not available right now.", 503)

    raw = await _read_capped(mask, settings.bg_mask_upload_max_bytes)

    async with get_pool().acquire() as conn:
        # Ownership: fetch by BOTH id and user_id — 404 for missing or non-owned.
        row = await conn.fetchrow(
            f"select {_COLUMNS} from public.wardrobe_items "
            "where id = $1::uuid and user_id = $2::uuid",
            str(item_id),
            user.id,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
        await enforce_rate_limit(
            conn,
            bucket=f"cutout_mask:{user.id}",
            limit=_CUTOUT_MASK_LIMIT,
            window_seconds=_CUTOUT_MASK_WINDOW_SECONDS,
        )

        # Resolve + fetch the stored original (signed R2 key or legacy URL).
        orig_map = await resolve_images(conn, "wardrobe_item", [item_id], ("original",))
        orig_hit = orig_map.get((str(item_id), "original"))
        fetch_url = orig_hit.url if (orig_hit and orig_hit.url) else row["image_url"]
        if not fetch_url:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "This item has no source image.", 422)
        original = await download_image(fetch_url)

        # Compose off the event loop; malformed/oversized/wrong-dims → 422.
        try:
            cutout_png, mask_png = await asyncio.to_thread(
                _apply_uploaded_mask, original, raw, settings.bg_max_image_edge
            )
        except ValueError as exc:  # imaging.ImageValidationError is a ValueError
            raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc

        # Upload the new objects (private) BEFORE changing any DB reference: cutout
        # with the existing 512px WebP thumbnail, mask without.
        provider = get_storage_provider()
        cutout_obj = await provider.put(
            cutout_png,
            visibility="private",
            prefix=f"{user.id}/cutout",
            content_type="image/png",
            make_thumbnail=True,
        )
        mask_obj = await provider.put(
            mask_png,
            visibility="private",
            prefix=f"{user.id}/cutout-mask",
            content_type="image/png",
            make_thumbnail=False,
        )
        # Atomically swap the active cutout + cutout_mask; keeps cutout_status=done.
        await replace_cutout_assets(
            conn, item_id=item_id, user_id=user.id, cutout=cutout_obj, mask=mask_obj
        )

        fresh = await conn.fetchrow(
            f"select {_COLUMNS} from public.wardrobe_items "
            "where id = $1::uuid and user_id = $2::uuid",
            str(item_id),
            user.id,
        )
        resolved = await _with_media(conn, [fresh])
    return resolved[0]


@router.delete("/wardrobe/{item_id}", status_code=204)
async def delete_wardrobe_item(
    item_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            delete from public.wardrobe_items
             where id = $1::uuid and user_id = $2::uuid
            returning id, image_url, cutout_url, thumbnail_url
            """,
            str(item_id),
            user.id,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
        # Erase the item's image, cutout, and thumbnail (R2 + legacy Supabase).
        await delete_content_media(
            conn,
            "wardrobe_item",
            str(item_id),
            [
                ("original", row["image_url"]),
                ("cutout", row["cutout_url"]),
                ("thumbnail", row["thumbnail_url"]),
            ],
        )
    return Response(status_code=204)
