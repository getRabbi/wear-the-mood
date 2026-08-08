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
import time
from decimal import Decimal
from typing import TYPE_CHECKING
from uuid import UUID

import asyncpg
import httpx
from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile

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
from app.queues import KIND_ENRICHMENT, KIND_REMBG, enqueue_signal
from app.services.llm import get_embedder
from app.services.media import get_storage_provider
from app.services.media.base import StoredObject
from app.services.media.deletion import delete_content_media
from app.services.media.repo import (
    discard_uploaded_objects,
    insert_asset,
    replace_cutout_assets,
    resolve_images,
    resolve_private_path,
)
from app.services.storage import download_image

if TYPE_CHECKING:  # Pillow-backed; imported lazily at call time, typed eagerly here.
    from app.services.bg.mask_ingest import ComposedCutout

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


def _apply_uploaded_mask(
    original: bytes, mask_bytes: bytes, max_edge: int
) -> tuple[bytes, bytes, str]:
    """Normalize the stored original with the SAME helper as automatic removal,
    decode + validate the uploaded mask, require an exact dimension match, preserve
    the soft alpha, and return ``(cutout, mask_png, cutout_content_type)``. The
    content type travels with the bytes because the cutout is lossless WebP, not
    PNG — the storage key, extension and stored MIME type must all match what was
    actually encoded. Pure/CPU — run in a
    thread. Raises imaging.ImageValidationError on any invalid input (§11).

    The logic now lives in ``app.services.bg.mask_ingest`` so the local-first
    ingestion endpoint composites through the EXACT same path (local BG §5/§6);
    this thin wrapper keeps the editor's call site and behaviour unchanged. Imported
    lazily so the light api/cron/CI paths never pull Pillow at module import."""
    from app.services.bg.mask_ingest import compose_from_uploaded_mask

    composed = compose_from_uploaded_mask(original, mask_bytes, max_edge=max_edge)
    return composed.cutout, composed.mask_png, composed.cutout_content_type


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
            cutout_bytes, mask_png, cutout_content_type = await asyncio.to_thread(
                _apply_uploaded_mask, original, raw, settings.bg_max_image_edge
            )
        except ValueError as exc:  # imaging.ImageValidationError is a ValueError
            raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc

        # Upload the new objects (private) BEFORE changing any DB reference: cutout
        # with the existing 512px WebP thumbnail, mask without.
        provider = get_storage_provider()
        cutout_obj = await provider.put(
            cutout_bytes,
            visibility="private",
            prefix=f"{user.id}/cutout",
            content_type=cutout_content_type,
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


# ── local-first cutout ingestion (local BG §6) ───────────────────────────────
# The DEVICE segmented the garment (Apple Vision / Google ML Kit) and uploaded the
# original straight to R2; it now sends only the soft MASK. We re-composite from
# the stored original with the same helper the rembg worker uses, so a locally
# created cutout is indistinguishable from a BiRefNet one and the free editor can
# re-edit it. Zero credits, no AI call, and — crucially — NO rembg queue signal:
# the item is born `done`, so the Azure worker can never race this row.

# Generous but bounded: no credits are spent, so this only stops rapid-fire abuse.
_LOCAL_CUTOUT_LIMIT = 30
_LOCAL_CUTOUT_WINDOW_SECONDS = 60

# Namespace for the two-int form of pg_advisory_xact_lock, keeping this feature's
# locks in their own space. The key is `hashtext(object_key)` computed BY POSTGRES,
# never Python's hash() — that is salted per process (PYTHONHASHSEED), so two API
# dynos would take different locks and the mutual exclusion would silently vanish.
_LOCAL_CUTOUT_LOCK_NAMESPACE = 90210

# Server-side coverage sanity. Deliberately WIDER than the client's 0.01..0.995
# policy: the device rejects marginal masks first, and this is only the backstop
# against a buggy or hostile client (§5 — never trust a client metric), not a
# second opinion on quality.
_MIN_LOCAL_ALPHA_AREA = 0.005
_MAX_LOCAL_ALPHA_AREA = 0.998

_LOCAL_ENGINES = {"apple_vision", "google_mlkit"}
_LOCAL_PLATFORMS = {"ios", "android"}

# The private sector a wardrobe original must live in — set server-side by
# /v1/media/upload-url, which builds keys as `{user_id}/wardrobe/{uuid4hex}.ext`.
_WARDROBE_SECTOR = "wardrobe"

_LOCAL_ITEM_INSERT = f"""
    insert into public.wardrobe_items
      (user_id, title, category, image_url, cutout_url, thumbnail_url, cutout_status)
    values ($1::uuid, $2, $3, $4, $5, $5, 'done')
    returning {_COLUMNS}
"""

# The natural request identity: the ORIGINAL object key. It is server-minted,
# uuid4-random and user-scoped, so it is a single-use token for one picked photo.
_LOCAL_EXISTING_ITEM = """
    select w.id
      from public.media_assets m
      join public.wardrobe_items w on w.id = m.owner_id
     where m.owner_kind = 'wardrobe_item'
       and m.role = 'original'
       and m.object_key = $1
       and m.deleted_at is null
       and w.user_id = $2::uuid
     limit 1
"""


def _validated_original_key(object_key: str, user_id: str) -> str:
    """The key must be one THIS user minted for the private ``wardrobe`` sector.

    Returns 404 rather than 403 on every failure so the endpoint can never be used
    to probe whether another user's object exists (§11).
    """
    key = (object_key or "").strip()
    prefix = f"{user_id}/{_WARDROBE_SECTOR}/"
    suspicious = ".." in key or "//" in key or "\\" in key or "\x00" in key
    if not key.startswith(prefix) or len(key) <= len(prefix) or len(key) > 512 or suspicious:
        raise ApiError(ErrorCode.NOT_FOUND, "Upload not found.", 404)
    return key


def _elapsed_ms(start: float) -> int:
    return int((time.monotonic() - start) * 1000)


class _UndecodableOriginal(Exception):
    """The STORED ORIGINAL will not decode — terminal, not a mask problem (§6.3)."""


def _ingest_local_mask(
    original: bytes, mask_bytes: bytes, max_edge: int
) -> tuple[ComposedCutout, float]:
    """Compose the cutout from the stored original + the device mask, and measure
    the server's OWN coverage. One thread hop for all of it (pure/CPU).

    The original is normalized FIRST and on its own, so the two failure modes stay
    distinguishable: an undecodable original raises [_UndecodableOriginal] (terminal
    — the worker would choke on the same bytes), whereas anything wrong with the
    MASK raises imaging.ImageValidationError (recoverable via the cloud path). The
    normalized image is then reused, so the original is decoded exactly once.
    """
    from app.services.bg import imaging
    from app.services.bg.mask_ingest import (
        compose_with_normalized_source,
        mask_alpha_area_ratio,
    )

    try:
        norm = imaging.normalize_source_image(original, max_edge=max_edge)
    except imaging.ImageValidationError as exc:
        raise _UndecodableOriginal(str(exc)) from exc

    composed = compose_with_normalized_source(norm, mask_bytes, max_edge=max_edge)
    return composed, mask_alpha_area_ratio(composed.mask_png, max_edge=max_edge)


# HTTP statuses from a presigned GET that mean "this object is not there".
# R2/S3 answer a presigned GET for an absent key with 404 (NoSuchKey); some
# configurations answer 403 when listing is denied, which is indistinguishable
# from absent and equally terminal for us.
_SOURCE_ABSENT_STATUSES = frozenset({403, 404, 410})


async def _fetch_local_original(object_key: str) -> bytes:
    """Download the exact stored original by key, with a THREE-WAY outcome (§6.3).

    The distinction matters because the BiRefNet worker reads the same object:

      * **definitively absent** → ``SOURCE_MISSING`` 422. Terminal. Queuing a cloud
        attempt would create an item certain to fail, so the app asks the user to
        reselect instead.
      * **transient storage/network failure** → ``PROVIDER_ERROR`` 503. Retryable;
        the object is probably fine, just unreadable right now, so the cloud path
        (and the worker's own recovery) can still succeed.
      * anything else unexpected → treated as transient, because guessing
        "terminal" would strand a recoverable add.

    Never logs the object key, the signed URL, or the underlying error text.
    """
    provider = get_storage_provider()
    try:
        url = await provider.view_url(object_key=object_key, visibility="private")
        return await download_image(url)
    except ApiError:
        raise
    except httpx.HTTPStatusError as exc:
        status = exc.response.status_code
        if status in _SOURCE_ABSENT_STATUSES:
            log.warning("local cutout: original absent (storage status %d)", status)
            raise ApiError(
                ErrorCode.SOURCE_MISSING, "That photo is no longer available.", 422
            ) from exc
        log.warning("local cutout: original read failed (storage status %d)", status)
        raise ApiError(
            ErrorCode.PROVIDER_ERROR, "Couldn't read that photo right now.", 503
        ) from exc
    except Exception as exc:  # noqa: BLE001 - network/timeout/signing
        # Category only: never the exception text, which can carry a signed URL.
        log.warning("local cutout: original read error (%s)", type(exc).__name__)
        raise ApiError(
            ErrorCode.PROVIDER_ERROR, "Couldn't read that photo right now.", 503
        ) from exc


@router.post("/wardrobe/local-cutout", status_code=201, response_model=WardrobeItemResponse)
async def create_item_from_local_cutout(
    response: Response,
    original_object_key: str = Form(...),
    mask: UploadFile = File(...),
    engine: str = Form(...),
    platform: str = Form(...),
    engine_version: str = Form(default=""),
    local_latency_ms: int = Form(default=0, ge=0, le=600_000),
    subject_count: int = Form(default=0, ge=0, le=64),
    title: str | None = Form(default=None, max_length=200),
    category: str | None = Form(default=None, max_length=80),
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Create a wardrobe item from an on-device cutout (local BG §6.1).

    Idempotent on ``original_object_key``: a retry after a lost response returns
    the already-created item instead of a duplicate, and concurrent duplicates are
    serialised by a transaction-scoped advisory lock. Spends no credits, runs no
    AI, touches no membership logic, and never enqueues the rembg worker.
    """
    settings = get_settings()
    # Feature gate: invisible (404) when local ingestion is off — the app then uses
    # the existing POST /v1/wardrobe -> BiRefNet flow (§7).
    if not settings.local_cutout_upload_enabled:
        raise ApiError(ErrorCode.NOT_FOUND, "Not found.", 404)
    # The emergency kill-switch is deliberately a DIFFERENT answer from the gate.
    # 404 means "this build has no such feature"; 503 means "it exists and is
    # switched off right now", which is what an incident actually is. The client
    # maps both to a cloud fallback, so the user is unaffected either way — but the
    # two are distinguishable in telemetry, and an outage that reads as
    # "feature was never here" is how the last one stayed invisible.
    if settings.local_cutout_emergency_disable:
        log.warning("local cutout: refused, emergency disable engaged")
        raise ApiError(ErrorCode.PROVIDER_ERROR, "Local cutouts are not available right now.", 503)
    # The cutout + mask are PRIVATE objects; without R2 private writes there is no
    # safe home for them → clear feature-unavailable so the app falls back (§6.1.2).
    if not settings.r2_writes_enabled:
        raise ApiError(ErrorCode.PROVIDER_ERROR, "Local cutouts are not available right now.", 503)
    if engine not in _LOCAL_ENGINES or platform not in _LOCAL_PLATFORMS:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Unknown local cutout engine.", 422)

    object_key = _validated_original_key(original_object_key, user.id)
    # Cap BEFORE decoding — a decompression bomb must never be rasterised (§6.1.4).
    raw_mask = await _read_capped(mask, settings.bg_mask_upload_max_bytes)
    # Bounded, non-identifying; only ever used for logging.
    engine_version = (engine_version or "unknown")[:64]

    started = time.monotonic()
    async with get_pool().acquire() as conn:
        await enforce_rate_limit(
            conn,
            bucket=f"local_cutout:{user.id}",
            limit=_LOCAL_CUTOUT_LIMIT,
            window_seconds=_LOCAL_CUTOUT_WINDOW_SECONDS,
        )

        # Fast path for a plain retry: if this key already produced an item, skip
        # the download/composite/upload entirely. The authoritative check is the
        # locked one below; this is purely an optimisation.
        existing = await conn.fetchval(_LOCAL_EXISTING_ITEM, object_key, user.id)
        if existing is not None:
            return await _local_cutout_response(conn, existing, user.id, response)

        t0 = time.monotonic()
        original = await _fetch_local_original(object_key)
        download_ms = _elapsed_ms(t0)

        # Exact dimensions, soft alpha preserved, server-measured coverage (§6.1.5-9).
        t0 = time.monotonic()
        try:
            composed, coverage = await asyncio.to_thread(
                _ingest_local_mask, original, raw_mask, settings.bg_max_image_edge
            )
        except _UndecodableOriginal as exc:
            # The stored original itself is unusable. The worker reads the same
            # object, so a cloud fallback would fail too — terminal (§6.3).
            log.warning("local cutout: stored original will not decode")
            raise ApiError(ErrorCode.SOURCE_MISSING, "That photo could not be read.", 422) from exc
        except ValueError as exc:  # imaging.ImageValidationError is a ValueError
            # A MASK problem: recoverable, the app retries through the cloud create
            # with the same object key.
            raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc
        if not _MIN_LOCAL_ALPHA_AREA <= coverage <= _MAX_LOCAL_ALPHA_AREA:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "The cutout mask does not look usable.", 422)
        compose_ms = _elapsed_ms(t0)

        # Upload BEFORE touching the DB, so an item is never marked done pointing at
        # bytes that do not exist. Same prefixes and content types as the rembg worker.
        t0 = time.monotonic()
        provider = get_storage_provider()
        # Concurrent: the cutout and the mask are independent objects, and this is
        # where the request actually spends its time — measured 6297 ms of 8178 ms
        # on a real device ingest, against 900 ms download and 774 ms compose.
        # Sequentially the small mask waited behind a multi-megabyte cutout for no
        # reason.
        cutout_task = asyncio.create_task(
            provider.put(
                composed.cutout,
                visibility="private",
                prefix=f"{user.id}/cutout",
                content_type=composed.cutout_content_type,
                make_thumbnail=True,
            )
        )
        mask_task = asyncio.create_task(
            provider.put(
                composed.mask_png,
                visibility="private",
                prefix=f"{user.id}/cutout-mask",
                content_type="image/png",
                make_thumbnail=False,
            )
        )
        results = await asyncio.gather(cutout_task, mask_task, return_exceptions=True)
        cutout_result, mask_result = results
        if isinstance(cutout_result, BaseException) or isinstance(mask_result, BaseException):
            # Either half may have landed. Discard whatever DID succeed so a retry
            # does not leak an orphan object, then re-raise the original failure so
            # the app falls back or retries cleanly.
            landed = [
                obj for obj in (cutout_result, mask_result) if not isinstance(obj, BaseException)
            ]
            if landed:
                await discard_uploaded_objects(*landed)
            raise cutout_result if isinstance(cutout_result, BaseException) else mask_result
        cutout_obj, mask_obj = cutout_result, mask_result
        store_ms = _elapsed_ms(t0)

        t0 = time.monotonic()
        created_id, item_row = await _commit_local_cutout(
            conn,
            user_id=user.id,
            object_key=object_key,
            title=title,
            category=category,
            cutout=cutout_obj,
            cutout_mime=composed.cutout_content_type,
            mask=mask_obj,
        )
        db_ms = _elapsed_ms(t0)

        if item_row is None:  # lost an idempotency race — the winner's item stands
            return await _local_cutout_response(conn, created_id, user.id, response)

        # Zero-cost, zero-credit observability (§6.1.14). Best-effort: a logging
        # failure must never undo a committed item.
        try:
            await conn.execute(
                """
                insert into public.ai_usage_log
                  (user_id, provider, task, images, estimated_usd, latency_ms, success)
                values ($1::uuid, $2, 'bg_removal', 1, 0, $3, true)
                """,
                user.id,
                f"local:{engine}",
                local_latency_ms,
            )
        except Exception as exc:  # noqa: BLE001
            log.warning("local cutout usage log failed for item %s: %s", created_id, exc)

        resolved = await _with_media(conn, [item_row])

    # Structured timing, no bytes/urls/keys (§10).
    log.info(
        "local cutout ingested item=%s engine=%s version=%s platform=%s "
        "dims=%dx%d coverage=%.3f subjects=%d device_ms=%d download_ms=%d "
        "compose_ms=%d store_ms=%d db_ms=%d total_ms=%d",
        created_id,
        engine,
        engine_version,
        platform,
        composed.width,
        composed.height,
        coverage,
        subject_count,
        local_latency_ms,
        download_ms,
        compose_ms,
        store_ms,
        db_ms,
        _elapsed_ms(started),
    )
    # Tagging + embedding stay off the visual critical path (§3.1) — the SAME
    # enrichment signal the rembg worker emits on success. Never KIND_REMBG:
    # the item is already `done`, and a cutout signal would let Azure re-process it.
    await enqueue_signal(KIND_ENRICHMENT, str(created_id))
    return resolved[0]


async def _commit_local_cutout(
    conn: asyncpg.Connection,
    *,
    user_id: str,
    object_key: str,
    title: str | None,
    category: str | None,
    cutout: StoredObject,
    cutout_mime: str,
    mask: StoredObject,
) -> tuple[object, asyncpg.Record | None]:
    """Create the item + its three ledger rows under an advisory lock.

    Returns ``(item_id, row)``. A ``None`` row means a concurrent request won the
    race for this object key: the freshly uploaded objects have been discarded and
    the caller must serve the WINNER's item. On any DB error the new objects are
    discarded and the error re-raised — the original is never touched (§6.3).
    """
    try:
        async with conn.transaction():
            # Serialise same-key requests for the whole transaction. Postgres
            # computes the hash, so the key is stable across processes and dynos.
            await conn.execute(
                "select pg_advisory_xact_lock($1::int, hashtext($2)::int)",
                _LOCAL_CUTOUT_LOCK_NAMESPACE,
                object_key,
            )
            # Authoritative re-check now that nobody else can be mid-insert.
            winner = await conn.fetchval(_LOCAL_EXISTING_ITEM, object_key, user_id)
            if winner is not None:
                await discard_uploaded_objects(cutout, mask)
                return winner, None

            row = await conn.fetchrow(
                _LOCAL_ITEM_INSERT,
                user_id,
                title,
                category,
                object_key,
                cutout.object_key,
            )
            item_id = row["id"]
            # The original the client already uploaded, plus what we just made.
            await insert_asset(
                conn,
                owner_kind="wardrobe_item",
                owner_id=item_id,
                role="original",
                user_id=user_id,
                visibility="private",
                storage_provider="r2",
                object_key=object_key,
            )
            await insert_asset(
                conn,
                owner_kind="wardrobe_item",
                owner_id=item_id,
                role="cutout",
                user_id=user_id,
                visibility="private",
                storage_provider="r2",
                object_key=cutout.object_key,
                thumbnail_key=cutout.thumbnail_key,
                content_hash=cutout.content_hash,
                # Derived from the object that was actually stored, not assumed.
                # The cutout is lossless WebP; recording it as PNG would leave the
                # ledger disagreeing with the bytes and the key's extension.
                mime_type=cutout_mime,
            )
            # The editable soft mask, so the free Erase/Restore editor can re-edit
            # a locally created cutout exactly like a BiRefNet one.
            await insert_asset(
                conn,
                owner_kind="wardrobe_item",
                owner_id=item_id,
                role="cutout_mask",
                user_id=user_id,
                visibility="private",
                storage_provider="r2",
                object_key=mask.object_key,
                content_hash=mask.content_hash,
                mime_type="image/png",
            )
            return item_id, row
    except Exception:
        await discard_uploaded_objects(cutout, mask)
        raise


async def _local_cutout_response(
    conn: asyncpg.Connection, item_id: object, user_id: str, response: Response
) -> WardrobeItemResponse:
    """Serve an already-existing item for an idempotent replay (200, not 201)."""
    row = await conn.fetchrow(
        f"select {_COLUMNS} from public.wardrobe_items where id = $1::uuid and user_id = $2::uuid",
        str(item_id),
        user_id,
    )
    if row is None:  # the item was deleted between the lookup and now
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    response.status_code = 200
    resolved = await _with_media(conn, [row])
    return resolved[0]


# ── free user-requested BiRefNet improvement (local BG §6.4) ─────────────────
# "Improve edges": re-run the automatic cutout on an item the user is not happy
# with. FREE — no credits, no membership check, no AI beyond the existing worker.
#
# THE INVARIANT: the current cutout stays live and visible for the whole
# round trip. This endpoint touches only the fields a fresh rembg attempt needs
# and leaves `cutout_url`, `thumbnail_url` and every `media_assets` row alone, so
# the closet keeps rendering the old cutout while the new one is computed — and
# still renders it if the worker fails.
_IMPROVE_LIMIT = 6
_IMPROVE_WINDOW_SECONDS = 600

# Re-queue for a NEW attempt, and only when one is not already in flight:
#   * `attempt_count = 0` is mandatory. The worker fails a row outright when
#     attempt_count > max_attempts, so an item that already burnt its budget
#     would be marked 'failed' the instant the user tapped Improve edges.
#   * `cutout_locked_at = null` clears any stale lease so the claim is clean.
#   * `cutout_last_signal_at = null` means recovery's stranded-queued scan will
#     heal this row if the enqueue below fails — the same backstop the normal
#     create path relies on.
#   * `cutout_error_code = null` clears a previous failure marker.
#   * `cutout_url` / `thumbnail_url` are DELIBERATELY not touched.
# The status guard is also the duplicate-tap guard: a second tap while the first
# is queued/processing matches no row and creates no work.
_IMPROVE_REQUEUE = f"""
    update public.wardrobe_items
       set cutout_status = 'queued',
           attempt_count = 0,
           cutout_locked_at = null,
           cutout_last_signal_at = null,
           cutout_error_code = null
     where id = $1::uuid
       and user_id = $2::uuid
       and coalesce(cutout_status, '') not in ('queued', 'processing')
    returning {_COLUMNS}
"""


@router.post("/wardrobe/{item_id}/improve-cutout", status_code=202)
async def improve_cutout(
    item_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Re-run the automatic BiRefNet cutout for an owned item (local BG §6.4).

    Free and idempotent-ish by design: duplicate taps while an attempt is in
    flight are no-ops that return the current item, so a fidgety user can never
    create concurrent work for the same row.
    """
    settings = get_settings()
    # Feature gate: invisible (404) when the improvement path is off (§7).
    if not settings.local_cutout_improve_enabled:
        raise ApiError(ErrorCode.NOT_FOUND, "Not found.", 404)

    async with get_pool().acquire() as conn:
        # Ownership first: 404 for missing or non-owned, never a hint either way.
        current = await conn.fetchrow(
            f"select {_COLUMNS} from public.wardrobe_items "
            "where id = $1::uuid and user_id = $2::uuid",
            str(item_id),
            user.id,
        )
        if current is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
        # No credits and no entitlement check — only an abuse bound.
        await enforce_rate_limit(
            conn,
            bucket=f"improve_cutout:{user.id}",
            limit=_IMPROVE_LIMIT,
            window_seconds=_IMPROVE_WINDOW_SECONDS,
        )
        if not current["image_url"]:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "This item has no source image.", 422)

        row = await conn.fetchrow(_IMPROVE_REQUEUE, str(item_id), user.id)
        if row is None:
            # Already queued or processing: return the item unchanged rather than
            # queueing a second attempt for the same row.
            resolved = await _with_media(conn, [current])
            return resolved[0]

        resolved = await _with_media(conn, [row])

    # Best-effort wake AFTER commit, exactly like the create path. Stamp the
    # signal only when the enqueue actually succeeded, so a failed enqueue leaves
    # NULL and recovery's stranded scan heals it on the next pass (§11.5).
    if await enqueue_signal(KIND_REMBG, str(item_id)):
        async with get_pool().acquire() as conn:
            await conn.execute(
                "update public.wardrobe_items set cutout_last_signal_at = now() "
                "where id = $1::uuid",
                str(item_id),
            )
    log.info("cutout improvement queued item=%s", item_id)
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
