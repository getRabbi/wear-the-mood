"""Resolve a try-on request's garments to canonical roles (spec Phases 2, 5, 27).

The bridge between "what the client sent" and "what the planner needs". Its whole
job is to establish, for each selected piece, WHAT IT IS — from the most
trustworthy source available, and never by inference the app cannot defend.

Priority, highest first:

  1. the owning row (`wardrobe_items` / `products`) looked up server-side —
     including its stored `canonical_category` when the backfill has reached it;
  2. the client's category hint, used only for pieces we hold no row for
     (sample-rack garments, a community look's images);
  3. nothing — which becomes `needs_review`, not a default.

A shipped client that sends bare URLs is handled by (1) as well: a first-party
image URL still carries its object key, and the media ledger maps that back to
the wardrobe item it belongs to. That recovers the role for the overwhelming
majority of already-installed apps without asking them to update, and only a
genuinely unrecognisable URL falls through to the recorded legacy path.
"""

from __future__ import annotations

import hashlib
import logging
from urllib.parse import urlsplit

import asyncpg

from app.core.config import get_settings
from app.services.media.refresh import classify_url
from app.services.tryon import taxonomy as tax
from app.services.tryon.planner import SelectedGarment

log = logging.getLogger("fashionos.tryon.resolve")


def item_key_for(*, wardrobe_item_id: str | None, product_id: str | None, image_url: str) -> str:
    """A stable accounting identity for one selected piece.

    Prefers a real id. Falls back to a hash of the image REFERENCE (path only,
    query string dropped) so a re-signed URL still names the same piece across
    the submit -> plan -> worker -> result hops, and so no signature ever ends up
    stored in a plan.
    """
    if wardrobe_item_id:
        return f"w:{wardrobe_item_id}"
    if product_id:
        return f"p:{product_id}"
    try:
        path = urlsplit(image_url).path or image_url
    except ValueError:
        path = image_url
    return "u:" + hashlib.sha256(path.encode("utf-8", "ignore")).hexdigest()[:16]


def _object_key(url: str) -> str | None:
    """The storage object key behind a first-party URL, or None."""
    ref = classify_url(url, private_bucket=get_settings().active_private_bucket)
    return ref.object_key if ref else None


async def _wardrobe_rows(
    conn: asyncpg.Connection, user_id: str, item_ids: list[str]
) -> dict[str, asyncpg.Record]:
    if not item_ids:
        return {}
    rows = await conn.fetch(
        """
        select id, title, category, subcategory, canonical_category, classification_status,
               cutout_url
          from public.wardrobe_items
         where user_id = $1::uuid and id = any($2::uuid[])
        """,
        user_id,
        item_ids,
    )
    return {str(r["id"]): r for r in rows}


async def _product_rows(
    conn: asyncpg.Connection, product_ids: list[str]
) -> dict[str, asyncpg.Record]:
    if not product_ids:
        return {}
    rows = await conn.fetch(
        """
        select id, title, category, subcategory, canonical_category, classification_status
          from public.products
         where id = any($1::uuid[])
        """,
        product_ids,
    )
    return {str(r["id"]): r for r in rows}


async def _owner_by_object_key(
    conn: asyncpg.Connection, user_id: str, keys: list[str]
) -> dict[str, tuple[str, str]]:
    """object_key -> (wardrobe_item_id, role) for THIS user's media.

    Scoped by `user_id` even though an object key is already unguessable: an
    ownership question is answered by the database, never by the fact that
    somebody knew a key (§11).
    """
    if not keys:
        return {}
    rows = await conn.fetch(
        """
        select object_key, thumbnail_key, owner_id, role
          from public.media_assets
         where owner_kind = 'wardrobe_item'
           and user_id = $1::uuid
           and deleted_at is null
           and (object_key = any($2::text[]) or thumbnail_key = any($2::text[]))
        """,
        user_id,
        keys,
    )
    found: dict[str, tuple[str, str]] = {}
    for row in rows:
        for key in (row["object_key"], row["thumbnail_key"]):
            if key in keys:
                found[key] = (str(row["owner_id"]), row["role"])
    return found


async def _wardrobe_by_legacy_url(
    conn: asyncpg.Connection, user_id: str, urls: list[str]
) -> dict[str, asyncpg.Record]:
    """Pre-R2 items still hold their Supabase URL directly on the row."""
    if not urls:
        return {}
    rows = await conn.fetch(
        """
        select id, title, category, subcategory, canonical_category, classification_status,
               image_url, cutout_url
          from public.wardrobe_items
         where user_id = $1::uuid
           and (image_url = any($2::text[]) or cutout_url = any($2::text[]))
        """,
        user_id,
        urls,
    )
    found: dict[str, asyncpg.Record] = {}
    for row in rows:
        for candidate in (row["image_url"], row["cutout_url"]):
            if candidate in urls:
                found[candidate] = row
    return found


async def _product_by_image_url(
    conn: asyncpg.Connection, urls: list[str]
) -> dict[str, asyncpg.Record]:
    """A catalog image is a public URL stored verbatim, so it maps back exactly."""
    if not urls:
        return {}
    rows = await conn.fetch(
        """
        select id, title, category, subcategory, canonical_category, classification_status,
               tryon_image_url, image_urls
          from public.products
         where tryon_image_url = any($1::text[]) or image_urls && $1::text[]
        """,
        urls,
    )
    found: dict[str, asyncpg.Record] = {}
    for row in rows:
        for candidate in [row["tryon_image_url"], *(row["image_urls"] or [])]:
            if candidate in urls:
                found.setdefault(candidate, row)
    return found


def _classify_row(row: asyncpg.Record) -> tax.Classification:
    """A row's role, honouring an explicit `needs_review` verdict.

    `needs_review` is a decision somebody (or the backfill) already made about
    this exact row, so re-deriving a role from its title here would quietly
    overturn it — which is the behaviour the flag exists to prevent.
    """
    if row["classification_status"] == tax.STATUS_NEEDS_REVIEW:
        return tax.Classification(None, None)
    return tax.classify(
        canonical=row["canonical_category"],
        category=row["category"],
        subcategory=row["subcategory"],
        title=row["title"],
    )


class GarmentRef:
    """One garment as the client described it, before resolution."""

    __slots__ = ("image_url", "wardrobe_item_id", "product_id", "category_hint", "legacy")

    def __init__(
        self,
        image_url: str,
        *,
        wardrobe_item_id: str | None = None,
        product_id: str | None = None,
        category_hint: str | None = None,
        legacy: bool = False,
    ) -> None:
        self.image_url = image_url
        self.wardrobe_item_id = wardrobe_item_id
        self.product_id = product_id
        self.category_hint = category_hint
        #: True for a payload shape that predates structured garments, i.e. one
        #: whose client had no way to say what a piece is.
        self.legacy = legacy


async def resolve_garments(
    conn: asyncpg.Connection,
    user_id: str,
    refs: list[GarmentRef],
    *,
    strict: bool = False,
) -> list[SelectedGarment]:
    """Resolve every reference to a `SelectedGarment` for the planner.

    `strict` removes the legacy provider-auto escape hatch entirely. It is driven
    by the `tryon_strict_categories` flag so the founder can close the hatch the
    moment the structured client has rolled out, without a deploy.
    """
    wardrobe = await _wardrobe_rows(
        conn, user_id, [r.wardrobe_item_id for r in refs if r.wardrobe_item_id]
    )
    products = await _product_rows(conn, [r.product_id for r in refs if r.product_id])

    # Only the references we could not identify from an id need the URL lookups.
    unknown = [r for r in refs if not r.wardrobe_item_id and not r.product_id]
    keys = {k: r for r in unknown if (k := _object_key(r.image_url))}
    by_key = await _owner_by_object_key(conn, user_id, list(keys))
    recovered_ids = [item_id for item_id, _role in by_key.values()]
    wardrobe.update(await _wardrobe_rows(conn, user_id, recovered_ids))

    plain = [r.image_url for r in unknown if _object_key(r.image_url) is None]
    by_legacy_url = await _wardrobe_by_legacy_url(conn, user_id, plain)
    by_product_url = await _product_by_image_url(conn, plain)

    resolved: list[SelectedGarment] = []
    for ref in refs:
        row: asyncpg.Record | None = None
        wardrobe_item_id = ref.wardrobe_item_id
        product_id = ref.product_id
        is_cutout = False

        if wardrobe_item_id:
            row = wardrobe.get(wardrobe_item_id)
        elif product_id:
            row = products.get(product_id)
        else:
            key = _object_key(ref.image_url)
            hit = by_key.get(key) if key else None
            if hit is not None:
                wardrobe_item_id, role = hit
                row = wardrobe.get(wardrobe_item_id)
                is_cutout = role == "cutout"
            elif ref.image_url in by_legacy_url:
                row = by_legacy_url[ref.image_url]
                wardrobe_item_id = str(row["id"])
                is_cutout = row["cutout_url"] == ref.image_url
            elif ref.image_url in by_product_url:
                row = by_product_url[ref.image_url]
                product_id = str(row["id"])

        if row is not None and wardrobe_item_id and "cutout_url" in row:
            is_cutout = is_cutout or row["cutout_url"] == ref.image_url

        if row is not None:
            classification = _classify_row(row)
        else:
            # No row of ours: a sample-rack garment or a community image. The
            # client's hint is all anyone has, and it is the same hint that drew
            # the piece into the picker, so it is used rather than discarded.
            hit = tax.classify_value(ref.category_hint)
            classification = tax.Classification(hit, "client_hint" if hit else None)

        resolved.append(
            SelectedGarment(
                item_key=item_key_for(
                    wardrobe_item_id=wardrobe_item_id,
                    product_id=product_id,
                    image_url=ref.image_url,
                ),
                image_url=ref.image_url,
                canonical=classification.canonical,
                classification_source=classification.source,
                is_cutout=is_cutout,
                wardrobe_item_id=wardrobe_item_id,
                product_id=product_id,
                # The escape hatch is offered ONLY where it is actually needed:
                # a legacy-shaped request whose garment we could not identify
                # from any of our own records. A legacy URL we DID trace back to
                # a row has a real role, so it is not a candidate — which keeps
                # "how often does provider-auto still happen" an honest number.
                allow_auto_fallback=(
                    ref.legacy and not strict and classification.canonical is None
                ),
            )
        )

    unresolved = [g.item_key for g in resolved if g.canonical is None]
    if unresolved:
        log.info(
            "tryon: %d/%d garment(s) unresolved (strict=%s)", len(unresolved), len(refs), strict
        )
    return resolved
