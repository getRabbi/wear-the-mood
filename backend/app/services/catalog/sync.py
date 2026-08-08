"""One merchant, one run.

The order of operations matters and is deliberate:

  claim lock -> open run row -> fetch -> normalize -> upsert seen
              -> reconcile unseen -> health + backoff -> close run -> release lock

Fetching happens INSIDE the lock but OUTSIDE any transaction, because holding a
Postgres transaction open across somebody else's HTTP request is how a slow feed
becomes a database incident.
"""

from __future__ import annotations

import json
import logging
import time
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import asyncpg

from app.services.catalog.models import FeedProduct, SyncCounts, SyncOutcome
from app.services.catalog.normalize import (
    FeedRecordError,
    normalize,
    resolve_rights,
    resolve_tryon,
    usable_image_url,
)
from app.services.catalog.sources import FeedFetchError, get_source

log = logging.getLogger("fashionos.catalog.sync")

# A lock older than this is treated as abandoned. Longer than any healthy run,
# short enough that a crashed worker does not wedge a merchant until someone
# notices. Reclaiming is safe because the writer is idempotent.
LOCK_TIMEOUT_MINUTES = 30

# Exponential, capped. A feed that has been failing for a day is not fixed by
# asking it again in five minutes, and the cap keeps a recovered feed from
# waiting a week.
BACKOFF_BASE_MINUTES = 15
BACKOFF_MAX_MINUTES = 12 * 60

# How many consecutive failures before the merchant is reported `failed` rather
# than `degraded`. One blip is not an outage.
FAILURES_BEFORE_FAILED = 3


# ── lock ────────────────────────────────────────────────────────────────────


async def _claim_lock(conn: asyncpg.Connection, merchant_id: str, owner: str) -> bool:
    """Take the per-source lock, or report that someone else holds it.

    A single conditional UPDATE: the WHERE clause is the mutual exclusion, so
    two workers racing cannot both win. Postgres does the arbitration, which is
    the only place it can be done correctly.
    """
    row = await conn.fetchrow(
        """
        update public.merchant_feed_config
           set locked_at = now(), locked_by = $2, updated_at = now()
         where merchant_id = $1
           and (locked_at is null or locked_at < now() - ($3 || ' minutes')::interval)
        returning merchant_id
        """,
        merchant_id,
        owner,
        str(LOCK_TIMEOUT_MINUTES),
    )
    return row is not None


async def _release_lock(conn: asyncpg.Connection, merchant_id: str, owner: str) -> None:
    # Scoped to the owner so a run that overran its lock cannot release the lock
    # a different worker has since taken.
    await conn.execute(
        """
        update public.merchant_feed_config
           set locked_at = null, locked_by = null, updated_at = now()
         where merchant_id = $1 and locked_by = $2
        """,
        merchant_id,
        owner,
    )


# ── run bookkeeping ─────────────────────────────────────────────────────────


async def _open_run(
    conn: asyncpg.Connection,
    merchant_id: str,
    *,
    trigger_source: str,
    triggered_by: str | None,
    dry_run: bool,
) -> str:
    return str(
        await conn.fetchval(
            """
            insert into public.product_sync_runs
              (merchant_id, status, trigger_source, triggered_by, dry_run)
            values ($1, 'running', $2, $3, $4)
            returning id
            """,
            merchant_id,
            trigger_source,
            triggered_by,
            dry_run,
        )
    )


async def _close_run(
    conn: asyncpg.Connection, run_id: str, outcome: SyncOutcome, started: float
) -> None:
    counts = outcome.counts
    await conn.execute(
        """
        update public.product_sync_runs
           set status = $2, fetched = $3, created = $4, updated = $5, unchanged = $6,
               deactivated = $7, reactivated = $8, skipped = $9,
               errors = $10::jsonb, error_message = $11,
               finished_at = now(), duration_ms = $12
         where id = $1
        """,
        run_id,
        outcome.status,
        counts.fetched,
        counts.created,
        counts.updated,
        counts.unchanged,
        counts.deactivated,
        counts.reactivated,
        counts.skipped,
        json.dumps(outcome.errors),
        outcome.error_message,
        int((time.monotonic() - started) * 1000),
    )


# ── health + backoff ────────────────────────────────────────────────────────


def _backoff_minutes(failures: int) -> int:
    return min(BACKOFF_BASE_MINUTES * (2 ** max(0, failures - 1)), BACKOFF_MAX_MINUTES)


async def _record_success(conn: asyncpg.Connection, merchant_id: str, run_id: str) -> None:
    await conn.execute(
        """
        update public.merchant_feed_config
           set consecutive_failures = 0, retry_after = null,
               last_run_id = $2, updated_at = now()
         where merchant_id = $1
        """,
        merchant_id,
        run_id,
    )
    await conn.execute(
        """
        update public.merchants
           set feed_health = 'ok', last_synced_at = now(), updated_at = now()
         where id = $1
        """,
        merchant_id,
    )


async def _record_failure(conn: asyncpg.Connection, merchant_id: str, run_id: str | None) -> None:
    failures = await conn.fetchval(
        """
        update public.merchant_feed_config
           set consecutive_failures = consecutive_failures + 1,
               last_run_id = coalesce($2, last_run_id), updated_at = now()
         where merchant_id = $1
        returning consecutive_failures
        """,
        merchant_id,
        run_id,
    )
    failures = int(failures or 1)
    await conn.execute(
        """
        update public.merchant_feed_config
           set retry_after = now() + ($2 || ' minutes')::interval
         where merchant_id = $1
        """,
        merchant_id,
        str(_backoff_minutes(failures)),
    )
    await conn.execute(
        """
        update public.merchants
           set feed_health = $2, updated_at = now()
         where id = $1
        """,
        merchant_id,
        "failed" if failures >= FAILURES_BEFORE_FAILED else "degraded",
    )


# ── writing ─────────────────────────────────────────────────────────────────


def _override_blocks(existing: asyncpg.Record | None, field: str) -> bool:
    """Whether a human has taken ownership of `field` on this row.

    `manual_override` with an empty field list freezes the whole row; with a
    list, only those fields. Either way the importer works around it rather
    than through it — the row is still counted, still marked seen, and simply
    not overwritten.
    """
    if existing is None or not existing["manual_override"]:
        return False
    fields = list(existing["manual_override_fields"] or [])
    return not fields or field in fields


async def _upsert_product(
    conn: asyncpg.Connection,
    merchant_id: str,
    run_id: str,
    product: FeedProduct,
    rights_default: str,
    counts: SyncCounts,
) -> None:
    existing = await conn.fetchrow(
        """
        select id, source_hash, active, manual_override, manual_override_fields,
               deactivated_by_sync_at, tryon_image_url, tryon_image_source
          from public.products
         where merchant_id = $1 and external_id = $2
        """,
        merchant_id,
        product.external_id,
    )

    content_hash = product.content_hash()
    rights = resolve_rights(rights_default)
    try_on_status, tryon_image = resolve_tryon(product, rights)

    # The whole row is frozen: mark it seen so absence-reconciliation does not
    # retire it, and change nothing else.
    if (
        existing is not None
        and existing["manual_override"]
        and not list(existing["manual_override_fields"] or [])
    ):
        await conn.execute(
            """
            update public.products
               set last_seen_in_feed_at = now(), missing_run_count = 0,
                   last_synced_at = now(), source_run_id = $2
             where id = $1
            """,
            existing["id"],
            run_id,
        )
        counts.unchanged += 1
        return

    # Unchanged: the short-circuit that keeps a second run from churning the
    # catalog. `last_synced_at` still moves, because "we confirmed this is
    # current" is exactly what it means and what staleness suppression reads.
    if existing is not None and existing["source_hash"] == content_hash and existing["active"]:
        await conn.execute(
            """
            update public.products
               set last_seen_in_feed_at = now(), missing_run_count = 0,
                   last_synced_at = now(), source_run_id = $2
             where id = $1
            """,
            existing["id"],
            run_id,
        )
        counts.unchanged += 1
        return

    # An admin-chosen try-on image is never replaced by the feed.
    keep_admin_image = (
        existing is not None
        and existing["tryon_image_source"] == "admin"
        and existing["tryon_image_url"]
    )
    final_tryon_image = existing["tryon_image_url"] if keep_admin_image else tryon_image
    final_tryon_source = "admin" if keep_admin_image else ("feed" if tryon_image else None)
    if keep_admin_image and usable_image_url(existing["tryon_image_url"]) and rights == "licensed":
        # A human picked a valid image, so readiness follows their choice rather
        # than the feed's opinion about the images it happened to send.
        try_on_status = "ready" if product.try_on_status != "pending" else "pending"

    if existing is None:
        await conn.execute(
            """
            insert into public.products
              (merchant_id, external_id, title, description, brand, category, subcategory,
               audience, colors, sizes, price_minor, original_price_minor, currency,
               image_urls, image_focal_x, image_focal_y, affiliate_ref,
               country_availability, stock_status, try_on_status, image_rights_status,
               active, starts_at, ends_at, sponsored, last_synced_at,
               source_run_id, source_hash, last_seen_in_feed_at, missing_run_count,
               tryon_image_url, tryon_image_source)
            values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,
                    true,$22,$23,$24, now(), $25,$26, now(), 0, $27,$28)
            """,
            merchant_id,
            product.external_id,
            product.title,
            product.description,
            product.brand,
            product.category,
            product.subcategory,
            product.audience,
            product.colors,
            product.sizes,
            product.price_minor,
            product.original_price_minor,
            product.currency,
            product.image_urls,
            product.image_focal_x,
            product.image_focal_y,
            product.affiliate_ref or product.external_id,
            product.country_availability,
            product.stock_status,
            try_on_status,
            rights,
            product.starts_at,
            product.ends_at,
            product.sponsored,
            run_id,
            content_hash,
            final_tryon_image,
            final_tryon_source,
        )
        counts.created += 1
        return

    # Field-level overrides: COALESCE keeps the human's value where they claimed
    # one, and takes the feed's everywhere else.
    keep_title = _override_blocks(existing, "title")
    keep_price = _override_blocks(existing, "price")
    keep_images = _override_blocks(existing, "image_urls")
    keep_stock = _override_blocks(existing, "stock_status")

    was_retired_by_sync = not existing["active"] and existing["deactivated_by_sync_at"] is not None
    await conn.execute(
        """
        update public.products
           set title = case when $3 then title else $4 end,
               description = $5, brand = $6, category = $7, subcategory = $8, audience = $9,
               colors = $10, sizes = $11,
               price_minor = case when $12 then price_minor else $13 end,
               original_price_minor = case when $12 then original_price_minor else $14 end,
               currency = case when $12 then currency else $15 end,
               image_urls = case when $16 then image_urls else $17 end,
               image_focal_x = case when $16 then image_focal_x else $18 end,
               image_focal_y = case when $16 then image_focal_y else $19 end,
               country_availability = $20,
               stock_status = case when $21 then stock_status else $22 end,
               try_on_status = $23,
               image_rights_status = $24,
               starts_at = $25, ends_at = $26, sponsored = $27,
               tryon_image_url = $28, tryon_image_source = $29,
               -- Reactivate ONLY what the importer itself retired. A product an
               -- admin unpublished stays unpublished no matter what the feed says.
               active = case when $30 then true else active end,
               deactivated_by_sync_at = case when $30 then null else deactivated_by_sync_at end,
               last_synced_at = now(), last_seen_in_feed_at = now(), missing_run_count = 0,
               source_run_id = $2, source_hash = $31, updated_at = now()
         where id = $1
        """,
        existing["id"],
        run_id,
        keep_title,
        product.title,
        product.description,
        product.brand,
        product.category,
        product.subcategory,
        product.audience,
        product.colors,
        product.sizes,
        keep_price,
        product.price_minor,
        product.original_price_minor,
        product.currency,
        keep_images,
        product.image_urls,
        product.image_focal_x,
        product.image_focal_y,
        product.country_availability,
        keep_stock,
        product.stock_status,
        try_on_status,
        rights,
        product.starts_at,
        product.ends_at,
        product.sponsored,
        final_tryon_image,
        final_tryon_source,
        was_retired_by_sync,
        content_hash,
    )
    if was_retired_by_sync:
        counts.reactivated += 1
    else:
        counts.updated += 1


async def _reconcile_absent(
    conn: asyncpg.Connection,
    merchant_id: str,
    run_id: str,
    seen: set[str],
    threshold: int,
    counts: SyncCounts,
) -> None:
    """Handle products the feed did not mention.

    Deliberately NOT a delete. Rows carry saves, interactions and try-on job
    references; removing one would break those and lose the product's identity
    if it comes back next week. Absence increments a counter, and only a
    sustained absence flips `active` — which `product_is_servable()` already
    treats as invisible.

    An admin-unpublished product is skipped: it is already inactive and not the
    importer's to account for.
    """
    rows = await conn.fetch(
        """
        select id, external_id, missing_run_count
          from public.products
         where merchant_id = $1 and active
        """,
        merchant_id,
    )
    for row in rows:
        if row["external_id"] in seen:
            continue
        missing = int(row["missing_run_count"] or 0) + 1
        if missing >= threshold:
            await conn.execute(
                """
                update public.products
                   set active = false, missing_run_count = $2,
                       deactivated_by_sync_at = now(), source_run_id = $3,
                       updated_at = now()
                 where id = $1
                """,
                row["id"],
                missing,
                run_id,
            )
            counts.deactivated += 1
        else:
            await conn.execute(
                "update public.products set missing_run_count = $2 where id = $1",
                row["id"],
                missing,
            )


# ── entry point ─────────────────────────────────────────────────────────────


async def sync_merchant(
    conn: asyncpg.Connection,
    merchant_id: str,
    *,
    trigger_source: str = "cron",
    triggered_by: str | None = None,
    dry_run: bool = False,
    source: Any | None = None,
    respect_interval: bool = True,
) -> SyncOutcome:
    """Run one merchant's feed. Never raises — every outcome is a run row."""
    owner = f"{trigger_source}:{uuid.uuid4().hex[:12]}"
    started = time.monotonic()

    config = await conn.fetchrow(
        """
        select c.merchant_id, c.feed_url, c.feed_format, c.enabled, c.min_interval_minutes,
               c.retry_after, c.image_rights_default, c.missing_runs_before_deactivate,
               m.approved, m.name
          from public.merchant_feed_config c
          join public.merchants m on m.id = c.merchant_id
         where c.merchant_id = $1
        """,
        merchant_id,
    )
    if config is None:
        return SyncOutcome(None, "skipped", error_message="no feed configured")
    # Approved AND enabled: "approved/configured merchant sources only" is two
    # separate decisions and both have to be yes.
    if not config["approved"]:
        return SyncOutcome(None, "skipped", error_message="merchant not approved")
    if not config["enabled"]:
        return SyncOutcome(None, "skipped", error_message="feed disabled")

    now = datetime.now(UTC)
    if respect_interval and config["retry_after"] and config["retry_after"] > now:
        return SyncOutcome(None, "skipped", error_message="in backoff window")
    if respect_interval:
        last = await conn.fetchval(
            """
            select max(started_at) from public.product_sync_runs
             where merchant_id = $1 and status in ('success', 'partial')
            """,
            merchant_id,
        )
        if last and last > now - timedelta(minutes=int(config["min_interval_minutes"])):
            return SyncOutcome(None, "skipped", error_message="within min interval")

    if not await _claim_lock(conn, merchant_id, owner):
        return SyncOutcome(None, "skipped", error_message="another run holds the lock")

    run_id = await _open_run(
        conn,
        merchant_id,
        trigger_source=trigger_source,
        triggered_by=triggered_by,
        dry_run=dry_run,
    )
    outcome = SyncOutcome(run_id, "running", dry_run=dry_run)

    try:
        feed = source or get_source(config["feed_format"])
        records = await feed.fetch(config["feed_url"])
        outcome.counts.fetched = len(records)

        seen: set[str] = set()
        normalized: list[FeedProduct] = []
        for record in records:
            try:
                product = normalize(record)
            except FeedRecordError as exc:
                outcome.counts.skipped += 1
                outcome.add_error(str(record.get("external_id") or "")[:200], str(exc))
                continue
            if product.external_id in seen:
                # A feed listing one product twice is one product.
                outcome.counts.skipped += 1
                continue
            seen.add(product.external_id)
            normalized.append(product)

        if dry_run:
            # Everything above ran — parsing, validation, per-record errors — so
            # a dry run genuinely tells you whether the feed is importable. It
            # simply stops before the first write.
            outcome.status = "success" if not outcome.errors else "partial"
            await _close_run(conn, run_id, outcome, started)
            return outcome

        # One transaction for the write phase: a run either moves the catalog to
        # a consistent state or leaves it exactly as it was.
        async with conn.transaction():
            for product in normalized:
                try:
                    await _upsert_product(
                        conn,
                        merchant_id,
                        run_id,
                        product,
                        config["image_rights_default"],
                        outcome.counts,
                    )
                except (asyncpg.PostgresError, ValueError) as exc:
                    outcome.counts.skipped += 1
                    outcome.add_error(product.external_id, str(exc))
            await _reconcile_absent(
                conn,
                merchant_id,
                run_id,
                seen,
                int(config["missing_runs_before_deactivate"]),
                outcome.counts,
            )

        outcome.status = "partial" if outcome.errors else "success"
        await _record_success(conn, merchant_id, run_id)

    except FeedFetchError as exc:
        outcome.status = "failed"
        outcome.error_message = str(exc)
        await _record_failure(conn, merchant_id, run_id)
    except Exception as exc:  # noqa: BLE001 - a run must always close its row
        log.exception("product sync failed for merchant %s", merchant_id)
        outcome.status = "failed"
        outcome.error_message = f"{exc.__class__.__name__}: {exc}"[:400]
        await _record_failure(conn, merchant_id, run_id)
    finally:
        await _close_run(conn, run_id, outcome, started)
        await _release_lock(conn, merchant_id, owner)

    log.info(
        "product sync %s merchant=%s %s", outcome.status, config["name"], outcome.counts.as_dict()
    )
    return outcome
