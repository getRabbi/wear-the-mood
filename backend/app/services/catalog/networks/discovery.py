"""Reconcile a network account's advertisers and feeds into the catalog.

Discovery is deliberately inert: it records what the account can reach and
stops. It does not approve a merchant, does not enable a feed, and does not
import a product. Everything it creates is off.

That is the whole safety property. The live account used to build this returns
581 feed rows across hundreds of advertisers; a discovery pass that enabled what
it found would have imported several hundred catalogues nobody chose.
"""

from __future__ import annotations

import json
import logging
import time
import unicodedata
from typing import Any

import asyncpg

from app.services.catalog.networks.awin import (
    AwinClient,
    AwinCredentialsMissing,
    AwinDiscovery,
    AwinFeed,
    redact,
)
from app.services.catalog.networks.awin_adapter import AWIN_CLICK_HOSTS

log = logging.getLogger("fashionos.catalog.discovery")

MAX_ERRORS = 20

# The hosts a network's tracked links resolve to. Seeded onto every discovered
# merchant's allow-list, because the redirect service refuses to send a click
# anywhere the merchant has not declared — and a merchant nobody has hand-
# configured would otherwise import thousands of unclickable products.
#
# This is the ONLY place the network's click domain is stated, so a second Awin
# advertiser needs no code change and no manual SQL.
NETWORK_CLICK_HOSTS: tuple[str, ...] = AWIN_CLICK_HOSTS


async def _open_run(
    conn: asyncpg.Connection, network: str, trigger_source: str, triggered_by: str | None
) -> str:
    return str(
        await conn.fetchval(
            """
            insert into public.network_discovery_runs
              (network, status, trigger_source, triggered_by)
            values ($1, 'running', $2, $3) returning id
            """,
            network,
            trigger_source,
            triggered_by,
        )
    )


async def _close_run(
    conn: asyncpg.Connection,
    run_id: str,
    status: str,
    stats: dict[str, Any],
    errors: list[str],
    error_message: str | None,
    started: float,
) -> None:
    await conn.execute(
        """
        update public.network_discovery_runs
           set status = $2, advertisers_seen = $3, advertisers_added = $4,
               feeds_seen = $5, feeds_added = $6, feeds_updated = $7, feeds_removed = $8,
               errors = $9::jsonb, error_message = $10,
               finished_at = now(), duration_ms = $11
         where id = $1
        """,
        run_id,
        status,
        stats.get("advertisers_seen", 0),
        stats.get("advertisers_added", 0),
        stats.get("feeds_seen", 0),
        stats.get("feeds_added", 0),
        stats.get("feeds_updated", 0),
        stats.get("feeds_removed", 0),
        json.dumps([redact(e) for e in errors[:MAX_ERRORS]]),
        redact(error_message) if error_message else None,
        int((time.monotonic() - started) * 1000),
    )


def _slug(network: str, advertiser_id: str, name: str) -> str:
    """A stable, readable slug. The advertiser id is what makes it unique —
    two advertisers may legitimately share a display name.

    Folded to ASCII first. Advertiser names are third-party text and arrive with
    accents and trademark signs in them ("Zalando Österreich"); `str.isalnum()`
    happily accepts those, and a slug is an identifier that ends up in URLs.
    """
    folded = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode("ascii")
    base = "".join(c if c.isalnum() else "-" for c in folded.lower()).strip("-")
    base = "-".join(p for p in base.split("-") if p)[:40] or "merchant"
    return f"{network}-{advertiser_id}-{base}"


async def _ensure_affiliate_config(conn: asyncpg.Connection, merchant_id: str) -> None:
    """Make the merchant redirectable, without asserting anything it did not say.

    A network deep link arrives complete and already carrying the publisher id,
    so there is no URL template to build and no tag to append — appending one
    would send two conflicting values, which some networks resolve by paying
    neither. What the redirect service still requires is a row saying the
    agreement is live; without it, every product from a discovered merchant is a
    dead "no_allowed_domains".

    `do nothing` on conflict: an operator who has configured this merchant by
    hand outranks a nightly listing read.
    """
    await conn.execute(
        """
        insert into public.merchant_affiliate_config
          (merchant_id, url_template, affiliate_tag, status)
        values ($1, null, null, 'ok')
        on conflict (merchant_id) do nothing
        """,
        merchant_id,
    )


async def _upsert_merchant(
    conn: asyncpg.Connection,
    network: str,
    advertiser_id: str,
    feeds: list[AwinFeed],
    click_hosts: tuple[str, ...] = NETWORK_CLICK_HOSTS,
) -> tuple[str, bool]:
    """Find or create the merchant for an advertiser. Returns (id, created)."""
    existing = await conn.fetchval(
        """
        select id from public.merchants
         where network = $1 and network_advertiser_id = $2
        """,
        network,
        advertiser_id,
    )
    head = feeds[0]
    metadata = {
        "primary_region": head.region,
        "vertical": head.vertical,
        "membership_status": head.membership_status,
        "feed_count": len(feeds),
        "languages": sorted({f.language for f in feeds if f.language}),
    }

    if existing:
        await conn.execute(
            """
            update public.merchants
               set name = $2, network_metadata = $3::jsonb,
                   -- UNION, never assignment: the network's click host is a fact
                   -- about the network and a merchant missing it cannot redirect
                   -- at all, but a domain an operator added by hand is theirs.
                   allowed_domains = (
                     select array(select distinct unnest(allowed_domains || $4::text[]))
                   ),
                   network_last_seen_at = now(), updated_at = now()
             where id = $1
            """,
            existing,
            head.advertiser_name or advertiser_id,
            json.dumps(metadata),
            list(click_hosts),
        )
        await _ensure_affiliate_config(conn, str(existing))
        return str(existing), False

    # Created UNAPPROVED. `approved` is what makes a merchant's products
    # visible and what lets its feed sync at all — discovery finding a
    # programme is not an operator choosing to sell it.
    merchant_id = await conn.fetchval(
        """
        insert into public.merchants
          (name, slug, approved, network, network_advertiser_id, network_metadata,
           network_last_seen_at, feed_health, allowed_domains)
        values ($1, $2, false, $3, $4, $5::jsonb, now(), 'ok', $6::text[])
        returning id
        """,
        head.advertiser_name or f"{network} {advertiser_id}",
        _slug(network, advertiser_id, head.advertiser_name),
        network,
        advertiser_id,
        json.dumps(metadata),
        list(click_hosts),
    )
    # A sync-policy row so the merchant is operable from admin the moment it is
    # approved — with everything off, and no feed_url, because URLs are built
    # server-side from the discovered feed ids.
    await conn.execute(
        """
        insert into public.merchant_feed_config
          (merchant_id, feed_url, feed_format, enabled, source_kind,
           image_rights_default, price_format, missing_runs_before_deactivate)
        values ($1, null, 'csv', false, $2, 'unknown', 'major', 2)
        on conflict (merchant_id) do nothing
        """,
        merchant_id,
        network,
    )
    await _ensure_affiliate_config(conn, str(merchant_id))
    return str(merchant_id), True


async def discover_awin(
    conn: asyncpg.Connection,
    *,
    trigger_source: str = "cron",
    triggered_by: str | None = None,
    client: AwinClient | None = None,
    discovery: AwinDiscovery | None = None,
    run_id: str | None = None,
) -> dict[str, Any]:
    """One discovery pass. Never raises — the outcome is a run row.

    `run_id` adopts a row an admin request already queued, so the button the
    operator pressed becomes the run they then watch, rather than a queued row
    and a separate cron row describing the same work.
    """
    network = "awin"
    started = time.monotonic()
    run_id = run_id or await _open_run(conn, network, trigger_source, triggered_by)
    stats = {
        "advertisers_seen": 0,
        "advertisers_added": 0,
        "feeds_seen": 0,
        "feeds_added": 0,
        "feeds_updated": 0,
        "feeds_removed": 0,
    }
    errors: list[str] = []
    status = "success"
    error_message: str | None = None

    try:
        awin = client or AwinClient()
        result = discovery if discovery is not None else await awin.discover()
        errors.extend(result.errors)

        by_advertiser = result.advertisers()
        stats["advertisers_seen"] = len(by_advertiser)
        stats["feeds_seen"] = sum(len(v) for v in by_advertiser.values())

        seen_feed_keys: set[tuple[str, str]] = set()

        for advertiser_id, feeds in by_advertiser.items():
            merchant_id, created = await _upsert_merchant(conn, network, advertiser_id, feeds)
            if created:
                stats["advertisers_added"] += 1

            for feed in feeds:
                seen_feed_keys.add((merchant_id, feed.feed_id))
                row = await conn.fetchrow(
                    """
                    insert into public.merchant_feeds
                      (merchant_id, network, network_feed_id, name, language, region,
                       vertical, product_count, source_updated_at, enabled,
                       last_seen_at, removed_at, raw_metadata)
                    values ($1,$2,$3,$4,$5,$6,$7,$8,$9,false,now(),null,$10::jsonb)
                    on conflict (merchant_id, network, network_feed_id) do update set
                      name = excluded.name,
                      language = excluded.language,
                      region = excluded.region,
                      vertical = excluded.vertical,
                      product_count = excluded.product_count,
                      source_updated_at = excluded.source_updated_at,
                      last_seen_at = now(),
                      -- A feed that came back is no longer removed. `enabled` is
                      -- deliberately NOT touched: an operator's decision to run
                      -- a feed, or not to, survives every discovery pass.
                      removed_at = null,
                      raw_metadata = excluded.raw_metadata,
                      updated_at = now()
                    returning (xmax = 0) as inserted
                    """,
                    merchant_id,
                    network,
                    feed.feed_id,
                    feed.feed_name,
                    feed.language,
                    feed.region,
                    feed.vertical,
                    feed.product_count,
                    feed.last_imported,
                    json.dumps(
                        {
                            "membership_status": feed.membership_status,
                            "last_checked": feed.last_checked.isoformat()
                            if feed.last_checked
                            else None,
                        }
                    ),
                )
                if row and row["inserted"]:
                    stats["feeds_added"] += 1
                else:
                    stats["feeds_updated"] += 1

        # Feeds that were not in this listing. MARKED, never deleted: the
        # products they produced still exist, and a feed that returns next week
        # should return to the same row with its enabled flag intact.
        if seen_feed_keys:
            removed = await conn.fetchval(
                """
                with gone as (
                  update public.merchant_feeds f
                     set removed_at = now(), enabled = false, updated_at = now()
                   from public.merchants m
                  where m.id = f.merchant_id
                    and f.network = $1 and m.network = $1
                    and f.removed_at is null
                    and (f.merchant_id::text || ':' || f.network_feed_id) <> all($2::text[])
                  returning 1
                ) select count(*) from gone
                """,
                network,
                [f"{m}:{f}" for m, f in seen_feed_keys],
            )
            stats["feeds_removed"] = int(removed or 0)

        if errors:
            status = "partial"

    except AwinCredentialsMissing as exc:
        status = "skipped"
        error_message = str(exc)
    except Exception as exc:  # noqa: BLE001 - discovery must always close its row
        log.exception("awin discovery failed")
        status = "failed"
        error_message = redact(f"{exc.__class__.__name__}: {exc}")[:400]
    finally:
        await _close_run(conn, run_id, status, stats, errors, error_message, started)

    log.info("awin discovery %s %s", status, stats)
    return {"run_id": run_id, "status": status, **stats}
