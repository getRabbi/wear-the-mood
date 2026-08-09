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

from app.services.catalog.mapping import apply_mapping, validate_field_map
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


def _redacted(value: object) -> str:
    """Strip network credentials from anything headed for a run row or a log.

    An error message becomes a database column, a log line and a Sentry event.
    A network feed URL carries its API key in the path, so any exception that
    quotes one would leak the key into all three at once.
    """
    try:
        from app.services.catalog.networks.awin import redact

        return redact(value)
    except Exception:  # noqa: BLE001 - redaction must never be the thing that fails
        return str(value)


def may_reconcile(outcome: SyncOutcome) -> bool:
    """THE GATE: whether products the feed did not mention may be retired.

    Only when the WHOLE merchant source was read. Anything else — a feed that
    timed out, hit a byte or row cap, served corrupt gzip, or ended mid-stream —
    means "products I did not see" is a statement about our network, not about
    the merchant's catalogue. With twenty-one feeds, one failing while twenty
    succeed looks exactly like a delisted category.

    The asymmetry is the argument. Skipping a retire is always recoverable: the
    next complete run does it. Retiring wrongly is not — it hides real products
    from every user until somebody notices.
    """
    return outcome.source_complete


def completed_status(outcome: SyncOutcome) -> str:
    """A run that finished, graded. An incomplete source is never a clean
    success, even when every row it did return imported perfectly — otherwise
    the history says "fine" about the runs most worth looking at."""
    return "partial" if outcome.errors or not outcome.source_complete else "success"


def _as_dict(value: Any) -> dict[str, Any]:
    """A jsonb column as a dict.

    asyncpg hands `jsonb` back as a STRING unless a codec is registered, and
    this pool is shared with the rest of the app — so decoding here is safer
    than changing a global codec other queries already depend on.
    """
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


async def _build_source(conn: asyncpg.Connection, config: asyncpg.Record) -> Any:
    """The right source for this merchant.

    `source_kind` decides. 'url' is the 0057 behaviour and is untouched; 'awin'
    assembles the merchant's enabled, non-removed feeds and reads them all as
    one source. The importer downstream cannot tell the difference — which is
    the point, because everything after "here are some records" is already
    proven.
    """
    if (config["source_kind"] or "url") != "awin":
        return get_source(config["feed_format"])

    from app.services.catalog.networks import AwinClient, AwinMultiFeedSource

    feeds = await conn.fetch(
        """
        select network_feed_id, language, product_count
          from public.merchant_feeds
         where merchant_id = $1 and enabled and removed_at is null
         order by network_feed_id
        """,
        config["merchant_id"],
    )
    return AwinMultiFeedSource(AwinClient(), [dict(f) for f in feeds])


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
               finished_at = now(), duration_ms = $12,
               source_complete = $13, truncated = $14,
               feeds_completed = $15, feeds_failed = $16, source_count = $17
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
        outcome.source_complete,
        outcome.truncated,
        outcome.feeds_completed,
        outcome.feeds_failed,
        outcome.source_count,
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


async def _load_existing(conn: asyncpg.Connection, merchant_id: str) -> dict[str, asyncpg.Record]:
    """Every existing product for this merchant, in ONE query, keyed by external_id.

    The importer used to SELECT once per feed row. That is fine for a 30-row
    fixture and ruinous for a real catalogue: the first live merchant returned
    4,210 rows across five feeds, which meant 4,210 sequential round trips to a
    database on another continent — roughly seventeen minutes of latency, on a
    single connection held open the whole time. It failed exactly the way that
    setup fails, with the server closing the connection out from under the run.
    """
    rows = await conn.fetch(
        """
        select id, external_id, source_hash, active, manual_override, manual_override_fields,
               deactivated_by_sync_at, tryon_image_url, tryon_image_source
          from public.products
         where merchant_id = $1
        """,
        merchant_id,
    )
    return {r["external_id"]: r for r in rows}


async def _mark_seen(conn: asyncpg.Connection, run_id: str, ids: list[Any]) -> None:
    """Mark unchanged products as confirmed-present, in one statement.

    The common steady-state run changes nothing at all, so this is the whole
    write phase for it: `last_synced_at` moves (freshness IS confirmed) while
    `updated_at` does not (nothing about the product changed).
    """
    if not ids:
        return
    await conn.execute(
        """
        update public.products
           set last_seen_in_feed_at = now(), missing_run_count = 0,
               last_synced_at = now(), source_run_id = $2
         where id = any($1::uuid[])
        """,
        ids,
        run_id,
    )


async def _upsert_product(
    conn: asyncpg.Connection,
    merchant_id: str,
    run_id: str,
    product: FeedProduct,
    rights_default: str,
    counts: SyncCounts,
    existing: asyncpg.Record | None = None,
    unchanged_ids: list[Any] | None = None,
) -> None:
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
        # Batched by the caller into one statement rather than a round trip
        # each: at real catalogue size this is the difference between a run
        # that finishes and one whose connection is closed underneath it.
        if unchanged_ids is not None:
            unchanged_ids.append(existing["id"])
        else:
            await _mark_seen(conn, run_id, [existing["id"]])
        counts.unchanged += 1
        return

    # Unchanged: the short-circuit that keeps a second run from churning the
    # catalog. `last_synced_at` still moves, because "we confirmed this is
    # current" is exactly what it means and what staleness suppression reads.
    if existing is not None and existing["source_hash"] == content_hash and existing["active"]:
        # Batched by the caller into one statement rather than a round trip
        # each: at real catalogue size this is the difference between a run
        # that finishes and one whose connection is closed underneath it.
        if unchanged_ids is not None:
            unchanged_ids.append(existing["id"])
        else:
            await _mark_seen(conn, run_id, [existing["id"]])
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
               tryon_image_url, tryon_image_source, country_eligibility)
            values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,
                    true,$22,$23,$24, now(), $25,$26, now(), 0, $27,$28,$29)
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
            product.country_eligibility,
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
               country_availability = $20, country_eligibility = $32,
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
        product.country_eligibility,
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
    # Two statements regardless of how many products went missing. A merchant
    # that drops an entire feed is exactly when this list is longest, and
    # exactly when a round trip per row would take the run down.
    retire: list[Any] = []
    bump: list[Any] = []
    for row in rows:
        if row["external_id"] in seen:
            continue
        if int(row["missing_run_count"] or 0) + 1 >= threshold:
            retire.append(row["id"])
        else:
            bump.append(row["id"])

    if retire:
        await conn.execute(
            """
            update public.products
               set active = false, missing_run_count = missing_run_count + 1,
                   deactivated_by_sync_at = now(), source_run_id = $2,
                   updated_at = now()
             where id = any($1::uuid[])
            """,
            retire,
            run_id,
        )
        counts.deactivated += len(retire)
    if bump:
        await conn.execute(
            "update public.products set missing_run_count = missing_run_count + 1"
            " where id = any($1::uuid[])",
            bump,
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
               c.field_map, c.price_format, c.default_currency, c.stock_map, c.source_kind,
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
        feed = source or await _build_source(conn, config)
        records = await feed.fetch(config["feed_url"])
        outcome.counts.fetched = len(records)
        outcome.processed_count = len(records)

        # Completeness, as reported by the source itself. A plain single-URL
        # source has no opinion and stays complete: it either fetched or raised.
        # A multi-feed source knows whether every feed finished, and that answer
        # is the only thing allowed to authorise retiring products.
        outcome.source_complete = bool(getattr(feed, "complete", True))
        outcome.truncated = bool(getattr(feed, "truncated", False))
        outcome.feeds_completed = list(getattr(feed, "feeds_completed", []) or [])
        outcome.feeds_failed = list(getattr(feed, "feeds_failed", []) or [])
        outcome.source_count = getattr(feed, "source_count", None)
        for err in getattr(feed, "errors", []) or []:
            outcome.add_error(err.get("feed_id"), err.get("error", ""))

        seen: set[str] = set()
        normalized: list[FeedProduct] = []
        # The merchant's declared shape -> the canonical shape, before anything
        # is validated. Unconfigured merchants get the identity mapping, so this
        # changes nothing for a feed that already speaks our field names.
        mapping_config = {
            "field_map": _as_dict(config["field_map"]),
            "price_format": config["price_format"],
            "default_currency": config["default_currency"],
            "stock_map": _as_dict(config["stock_map"]),
        }
        unknown = validate_field_map(mapping_config["field_map"])
        if unknown:
            # A typo in a field map silently maps nothing, which looks exactly
            # like a feed that changed. Say so once, on the run.
            outcome.add_error(None, f"field_map targets unknown fields: {', '.join(unknown)}")

        # An Awin row is turned into the canonical shape by code rather than by
        # per-merchant config: Awin's column names are fixed and known, so
        # asking an operator to hand-write a field map for every Awin merchant
        # would be busywork with a typo in it. Merchant-specific config still
        # applies afterwards, so an unusual merchant can still override.
        awin = (config["source_kind"] or "url") == "awin"
        if awin:
            from app.services.catalog.networks.awin_adapter import awin_row_to_canonical

        for record in records:
            if awin:
                record = awin_row_to_canonical(record)
            mapped = apply_mapping(record, mapping_config)
            try:
                product = normalize(mapped)
            except FeedRecordError as exc:
                outcome.counts.skipped += 1
                outcome.add_error(str(mapped.get("external_id") or "")[:200], str(exc))
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

        # One read for the whole merchant, and one write for everything the run
        # leaves untouched. What remains is a round trip per product that
        # genuinely changed — which on a steady-state run is close to none.
        existing_by_id = await _load_existing(conn, merchant_id)
        unchanged_ids: list[Any] = []

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
                        existing=existing_by_id.get(product.external_id),
                        unchanged_ids=unchanged_ids,
                    )
                except (asyncpg.PostgresError, ValueError) as exc:
                    outcome.counts.skipped += 1
                    outcome.add_error(product.external_id, str(exc))
            await _mark_seen(conn, run_id, unchanged_ids)
            if may_reconcile(outcome):
                await _reconcile_absent(
                    conn,
                    merchant_id,
                    run_id,
                    seen,
                    int(config["missing_runs_before_deactivate"]),
                    outcome.counts,
                )
            else:
                log.warning(
                    "merchant %s: source incomplete (%d feed(s) failed, truncated=%s) — "
                    "absence reconciliation skipped",
                    merchant_id,
                    len(outcome.feeds_failed),
                    outcome.truncated,
                )

        outcome.status = completed_status(outcome)
        await _record_success(conn, merchant_id, run_id)

    except FeedFetchError as exc:
        outcome.status = "failed"
        # A run that never read the source is the definition of incomplete. It
        # matters even though this path cannot reach reconciliation: the run row
        # is what a later question ("was the catalogue fully seen on Tuesday?")
        # is answered from.
        outcome.source_complete = False
        outcome.error_message = _redacted(exc)
        await _record_failure(conn, merchant_id, run_id)
    except Exception as exc:  # noqa: BLE001 - a run must always close its row
        log.exception("product sync failed for merchant %s", merchant_id)
        outcome.status = "failed"
        outcome.source_complete = False
        outcome.error_message = _redacted(f"{exc.__class__.__name__}: {exc}")[:400]
        await _record_failure(conn, merchant_id, run_id)
    finally:
        await _close_run(conn, run_id, outcome, started)
        await _release_lock(conn, merchant_id, owner)

    log.info(
        "product sync %s merchant=%s %s", outcome.status, config["name"], outcome.counts.as_dict()
    )
    return outcome
