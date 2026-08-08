"""Source-driven news ingestion, on top of the existing fetch/summarize path.

This is NOT a second newsroom. It reuses `RssFetcher`, the summarizer resolver
and its fallback chain, `news_items` and `ai_usage_log` exactly as they are.
What it adds is the operator layer the original lacked:

* sources are ROWS, so one can be disabled at 2am without a deploy;
* each source runs independently, so a dead feed is a failed run row rather
  than a silent end to the whole ingest;
* items dedup on `canonical_url`, so the same story under a tracking-tagged URL
  does not become a second row;
* items land in a LIFECYCLE — an unvetted source produces `review_required`,
  never a live post, which is what "do not blindly auto-publish unknown
  sources" has to mean in code;
* every run leaves counts and errors behind.

Only a SUMMARY and a link are ever stored. There is deliberately no column for
article body text, so "no full copyrighted article copying" is enforced by the
schema rather than by discipline.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import asyncpg

from app.core.config import get_settings
from app.services.news.base import NewsArticle, NewsSummarizer, NewsSummary, fallback_summary
from app.services.news.canonical import canonical_url, display_url

log = logging.getLogger("fashionos.news.pipeline")

MAX_RUN_ERRORS = 25

# Hard ceiling on a stored summary, applied at INGEST.
#
# The prompt asks for one or two sentences, and the models mostly comply — but
# "mostly" is not a guarantee, and the length of what we store is the whole of
# our exposure on "a summary, never the article". A short source article with a
# talkative model is exactly the case where a summary stops being one. The
# admin editor enforces 1200; ingest is stricter because nobody reviewed it.
MAX_SUMMARY_CHARS = 600

# Same shape as the product feeds: exponential, capped.
BACKOFF_BASE_MINUTES = 30
BACKOFF_MAX_MINUTES = 24 * 60
FAILURES_BEFORE_FAILED = 3

_USD_PER_INPUT_TOK = Decimal("1") / Decimal("1000000")
_USD_PER_OUTPUT_TOK = Decimal("5") / Decimal("1000000")

# Upsert on the CANONICAL url. `url` still stores what the feed said.
#
# The status is only set on INSERT: a re-ingest must never drag a story an
# editor already published — or archived — back to `review_required`. Editorial
# state belongs to the editor, and the feed does not get a vote after the fact.
_UPSERT = """
    insert into public.news_items
      (title, summary, source, url, canonical_url, image_url, published_at,
       source_id, status, author, attribution, sync_run_id)
    values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    on conflict (canonical_url) where canonical_url is not null
    do update set title = excluded.title,
                  summary = excluded.summary,
                  source = excluded.source,
                  url = excluded.url,
                  image_url = excluded.image_url,
                  published_at = excluded.published_at,
                  source_id = excluded.source_id,
                  author = excluded.author,
                  attribution = excluded.attribution,
                  sync_run_id = excluded.sync_run_id
    returning (xmax = 0) as inserted
"""

_USAGE = """
    insert into public.ai_usage_log
      (user_id, provider, model, task, input_tokens, output_tokens, images,
       estimated_usd, success)
    values (null, $1, $2, 'news_summary', $3, $4, 0, $5, true)
"""


def _cost(summary: NewsSummary) -> Decimal:
    if summary.input_tokens is None:
        return Decimal("0")
    return (
        Decimal(summary.input_tokens) * _USD_PER_INPUT_TOK
        + Decimal(summary.output_tokens or 0) * _USD_PER_OUTPUT_TOK
    )


def _backoff_minutes(failures: int) -> int:
    return min(BACKOFF_BASE_MINUTES * (2 ** max(0, failures - 1)), BACKOFF_MAX_MINUTES)


def clamp_summary(text: str | None, *, limit: int = MAX_SUMMARY_CHARS) -> str:
    """Bound a summary, cutting on a word boundary.

    Applies to EVERY path — the model's output and the non-LLM fallback alike —
    because the guarantee has to hold regardless of which one produced the text.
    """
    cleaned = " ".join((text or "").split()).strip()
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[:limit].rsplit(" ", 1)[0].rstrip(",.;:") + "…"


def initial_status(auto_publish: bool) -> str:
    """Where a newly ingested item lands.

    `review_required` unless the source has been explicitly trusted. This is the
    whole of "do not blindly auto-publish unknown sources": a source added
    carelessly cannot publish itself, because `news_sources.auto_publish`
    defaults false and only an admin can change it.
    """
    return "published" if auto_publish else "review_required"


async def _open_run(
    conn: asyncpg.Connection,
    source_id: str | None,
    *,
    trigger_source: str,
    triggered_by: str | None,
    dry_run: bool,
) -> str:
    return str(
        await conn.fetchval(
            """
            insert into public.news_sync_runs
              (source_id, status, trigger_source, triggered_by, dry_run)
            values ($1, 'running', $2, $3, $4)
            returning id
            """,
            source_id,
            trigger_source,
            triggered_by,
            dry_run,
        )
    )


async def _close_run(
    conn: asyncpg.Connection,
    run_id: str,
    *,
    status: str,
    counts: dict[str, int],
    errors: list[dict[str, str]],
    error_message: str | None,
    started: float,
) -> None:
    await conn.execute(
        """
        update public.news_sync_runs
           set status = $2, fetched = $3, created = $4, updated = $5,
               duplicates = $6, skipped = $7, errors = $8::jsonb,
               error_message = $9, finished_at = now(), duration_ms = $10
         where id = $1
        """,
        run_id,
        status,
        counts.get("fetched", 0),
        counts.get("created", 0),
        counts.get("updated", 0),
        counts.get("duplicates", 0),
        counts.get("skipped", 0),
        json.dumps(errors),
        error_message,
        int((time.monotonic() - started) * 1000),
    )


async def _record_success(conn: asyncpg.Connection, source_id: str, run_id: str) -> None:
    await conn.execute(
        """
        update public.news_sources
           set consecutive_failures = 0, retry_after = null, health = 'ok',
               last_run_id = $2, last_success_at = now(), updated_at = now()
         where id = $1
        """,
        source_id,
        run_id,
    )


async def _record_failure(conn: asyncpg.Connection, source_id: str, run_id: str) -> None:
    failures = int(
        await conn.fetchval(
            """
            update public.news_sources
               set consecutive_failures = consecutive_failures + 1,
                   last_run_id = $2, updated_at = now()
             where id = $1
            returning consecutive_failures
            """,
            source_id,
            run_id,
        )
        or 1
    )
    await conn.execute(
        """
        update public.news_sources
           set retry_after = now() + ($2 || ' minutes')::interval, health = $3
         where id = $1
        """,
        source_id,
        str(_backoff_minutes(failures)),
        "failed" if failures >= FAILURES_BEFORE_FAILED else "degraded",
    )


async def ingest_source(
    conn: asyncpg.Connection,
    source: asyncpg.Record,
    summarizer: NewsSummarizer,
    *,
    fetcher_factory=None,
    trigger_source: str = "cron",
    triggered_by: str | None = None,
    dry_run: bool = False,
) -> dict[str, int]:
    """Ingest ONE source. Never raises — every outcome is a run row."""
    started = time.monotonic()
    source_id = str(source["id"])
    counts = {"fetched": 0, "created": 0, "updated": 0, "duplicates": 0, "skipped": 0}
    errors: list[dict[str, str]] = []
    run_id = await _open_run(
        conn, source_id, trigger_source=trigger_source, triggered_by=triggered_by, dry_run=dry_run
    )
    status = "success"
    error_message: str | None = None

    try:
        if fetcher_factory is not None:
            fetcher = fetcher_factory(source)
        else:
            from app.services.news.rss import RssFetcher

            # strict: this is ONE source, so an unreadable feed is this run's
            # failure and must reach `health` and the backoff. Without it a dead
            # source reports success with zero articles forever.
            fetcher = RssFetcher([source["feed_url"]], strict=True)

        articles: list[NewsArticle] = await fetcher.fetch()
        counts["fetched"] = len(articles)
        model = get_settings().anthropic_model_news
        seen_canonical: set[str] = set()

        for article in articles:
            canonical = canonical_url(article.url)
            link = display_url(article.url)
            if not canonical or not link:
                # No stable key means it would be re-created on every run.
                counts["skipped"] += 1
                continue
            if canonical in seen_canonical:
                # The same story twice within one feed pull.
                counts["duplicates"] += 1
                continue
            seen_canonical.add(canonical)

            if dry_run:
                continue

            try:
                summary = await summarizer.summarize(article.title, article.content)
            except Exception as exc:  # noqa: BLE001 - one bad item must not stop a run
                log.warning("summarize failed for %s: %s", canonical, exc)
                summary = NewsSummary(summary=fallback_summary(article.title, article.content))

            inserted = await conn.fetchval(
                _UPSERT,
                article.title,
                clamp_summary(summary.summary),
                article.source or source["publisher"] or source["name"],
                link,
                canonical,
                article.image_url,
                article.published_at,
                source_id,
                initial_status(bool(source["auto_publish"])),
                getattr(article, "author", None),
                source["publisher"] or source["name"],
                run_id,
            )
            if inserted:
                counts["created"] += 1
            else:
                counts["updated"] += 1

            if summarizer.name != "stub" and summary.input_tokens is not None:
                await conn.execute(
                    _USAGE,
                    summarizer.name,
                    model,
                    summary.input_tokens,
                    summary.output_tokens,
                    _cost(summary),
                )

        if not dry_run:
            await _record_success(conn, source_id, run_id)

    except Exception as exc:  # noqa: BLE001 - isolation is the point
        log.exception("news ingest failed for source %s", source["slug"])
        status = "failed"
        error_message = f"{exc.__class__.__name__}: {exc}"[:400]
        if len(errors) < MAX_RUN_ERRORS:
            errors.append({"source": source["slug"], "error": error_message})
        if not dry_run:
            await _record_failure(conn, source_id, run_id)
    finally:
        await _close_run(
            conn,
            run_id,
            status=status,
            counts=counts,
            errors=errors,
            error_message=error_message,
            started=started,
        )

    return counts


_DUE_SOURCES = """
    select id, slug, name, feed_url, feed_kind, publisher, auto_publish, priority
      from public.news_sources
     where enabled
       and (retry_after is null or retry_after <= now())
     order by priority asc, created_at asc
"""


async def run_enabled_sources(
    conn: asyncpg.Connection,
    summarizer: NewsSummarizer,
    *,
    fetcher_factory=None,
    trigger_source: str = "cron",
    triggered_by: str | None = None,
    dry_run: bool = False,
    source_id: str | None = None,
) -> dict[str, int]:
    """Ingest every enabled source, one at a time.

    Sequential and individually guarded on purpose: a failing feed must produce
    a failed run row for ITSELF and leave the others to import. Disabled sources
    are excluded by the query, so "disabled means no ingest" is a property of
    the SQL rather than of remembering to check.
    """
    if source_id is None:
        rows = await conn.fetch(_DUE_SOURCES)
    else:
        # An admin "Sync Now" for one source. Still requires `enabled`: a
        # disabled source must not ingest by any route, including a button.
        rows = await conn.fetch(
            """
            select id, slug, name, feed_url, feed_kind, publisher, auto_publish, priority
              from public.news_sources
             where enabled and id = $1
            """,
            source_id,
        )

    totals = {"sources": 0, "fetched": 0, "created": 0, "updated": 0, "duplicates": 0, "skipped": 0}
    for row in rows:
        counts = await ingest_source(
            conn,
            row,
            summarizer,
            fetcher_factory=fetcher_factory,
            trigger_source=trigger_source,
            triggered_by=triggered_by,
            dry_run=dry_run,
        )
        totals["sources"] += 1
        for key in ("fetched", "created", "updated", "duplicates", "skipped"):
            totals[key] += counts.get(key, 0)

    log.info("news ingest across %d source(s): %s", totals["sources"], totals)
    return totals


async def purge_stale_drafts(conn: asyncpg.Connection, *, older_than_days: int = 30) -> int:
    """Archive review items nobody acted on.

    Not a delete: an archived row still answers "did we see this story", which
    is what stops it being re-created as new the next time it appears in a feed.
    """
    cutoff = datetime.now(UTC) - timedelta(days=older_than_days)
    return int(
        await conn.fetchval(
            """
            with archived as (
              update public.news_items
                 set status = 'archived', published_state_at = now()
               where status = 'review_required' and created_at < $1
              returning 1
            ) select count(*) from archived
            """,
            cutoff,
        )
        or 0
    )
