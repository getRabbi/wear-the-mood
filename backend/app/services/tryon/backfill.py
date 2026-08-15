"""Canonical-category backfill for legacy items and products (spec Phase 5).

Classification happens in PYTHON, not in SQL, because `taxonomy.py` is the single
source of truth for what a garment is and a second copy of that table in a
migration would be a second answer waiting to disagree. The trade is that this
reads rows in batches instead of doing one `update ... from`, which for a
catalogue this size is measured in seconds.

The rules it will not break:

* It never invents a role. A row it cannot read from its own metadata becomes
  `needs_review` — visible everywhere in the app, and simply not try-on eligible
  until somebody says what it is (§29).
* It never overwrites a row that already has a canonical category, and never
  overturns an existing `needs_review` verdict.
* `--dry-run` touches nothing and is the only way to see the numbers first.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

import asyncpg

from app.services.tryon import taxonomy as tax

log = logging.getLogger("fashionos.tryon.backfill")

#: Rows per round trip. Small enough to keep memory flat on a big catalogue,
#: large enough that the classification cost dominates the network cost.
_BATCH = 500


@dataclass
class BackfillReport:
    """What a dry run found, in the language the spec asks the report to use."""

    table: str
    total: int = 0
    already_valid: int = 0
    backfillable: int = 0
    needs_review: int = 0
    unresolvable: int = 0
    #: canonical -> how many rows the classifier would assign to it. This is the
    #: number a human actually checks: "1,900 products became tops" is either
    #: obviously right or obviously wrong at a glance.
    by_category: dict[str, int] = field(default_factory=dict)
    #: A few examples per resolved category, so a wrong rule is visible BEFORE it
    #: is written rather than after. Titles only — never an image or a user id.
    samples: dict[str, list[str]] = field(default_factory=dict)

    def note(self, canonical: str, label: str | None) -> None:
        self.by_category[canonical] = self.by_category.get(canonical, 0) + 1
        bucket = self.samples.setdefault(canonical, [])
        if label and len(bucket) < 3:
            bucket.append(label[:60])

    def render(self) -> str:
        lines = [
            f"{self.table}:",
            f"  total                      {self.total:>8}",
            f"  already valid              {self.already_valid:>8}",
            f"  deterministically backfill {self.backfillable:>8}",
            f"  needs_review               {self.needs_review:>8}",
            f"  unresolvable (no metadata) {self.unresolvable:>8}",
        ]
        if self.by_category:
            lines.append("  would assign:")
            for canonical, count in sorted(self.by_category.items(), key=lambda kv: -kv[1]):
                examples = ", ".join(self.samples.get(canonical, []))
                lines.append(f"    {canonical:<14}{count:>7}   {examples}")
        return "\n".join(lines)


_WARDROBE_SELECT = """
    select id, title, category, subcategory, canonical_category, classification_status
      from public.wardrobe_items
     where canonical_category is null
       and (classification_status is distinct from 'needs_review')
     order by id
     limit $1 offset $2
"""

_PRODUCT_SELECT = """
    select id, title, category, subcategory, canonical_category, classification_status
      from public.products
     where canonical_category is null
       and (classification_status is distinct from 'needs_review')
     order by id
     limit $1 offset $2
"""

_TABLES = {
    "wardrobe_items": _WARDROBE_SELECT,
    "products": _PRODUCT_SELECT,
}


async def _totals(conn: asyncpg.Connection, table: str) -> tuple[int, int]:
    """(all rows, rows already carrying a valid canonical category)."""
    total = await conn.fetchval(f"select count(*) from public.{table}")
    valid = await conn.fetchval(
        f"select count(*) from public.{table} "
        "where canonical_category is not null "
        "  and coalesce(classification_status, 'valid') = 'valid'"
    )
    return int(total or 0), int(valid or 0)


def _has_metadata(row: asyncpg.Record) -> bool:
    """Whether there was anything to read at all.

    The difference between "we could not classify this" and "there was nothing
    here to classify" is the difference between a rule to improve and a row to
    ask a human about, so the report keeps them apart.
    """
    return any((row[field] or "").strip() for field in ("title", "category", "subcategory"))


async def report(conn: asyncpg.Connection, table: str) -> BackfillReport:
    """DRY RUN. Reads every unclassified row and reports what would happen."""
    if table not in _TABLES:
        raise ValueError(f"unknown table {table!r}")
    result = BackfillReport(table=table)
    result.total, result.already_valid = await _totals(conn, table)

    offset = 0
    while True:
        rows = await conn.fetch(_TABLES[table], _BATCH, offset)
        if not rows:
            break
        for row in rows:
            classification = tax.classify(
                category=row["category"], subcategory=row["subcategory"], title=row["title"]
            )
            if classification.resolved:
                result.backfillable += 1
                result.note(classification.canonical or "", row["title"])
            elif _has_metadata(row):
                result.needs_review += 1
            else:
                result.unresolvable += 1
        offset += len(rows)
    return result


async def apply(
    conn: asyncpg.Connection, table: str, *, limit: int | None = None
) -> dict[str, int]:
    """WRITE. Same classification as `report`, persisted.

    Idempotent: it only ever touches rows with a NULL canonical category that are
    not already marked `needs_review`, so re-running it is a no-op and a partial
    run can simply be resumed. Never deletes, never rewrites a human's decision.
    """
    if table not in _TABLES:
        raise ValueError(f"unknown table {table!r}")
    counts = {"classified": 0, "needs_review": 0}
    processed = 0

    while True:
        take = _BATCH if limit is None else min(_BATCH, limit - processed)
        if take <= 0:
            break
        # Offset stays 0: every row this pass updates stops matching the WHERE
        # clause, so the next fetch naturally returns the next unprocessed batch.
        rows = await conn.fetch(_TABLES[table], take, 0)
        if not rows:
            break

        resolved: list[tuple[str, str]] = []
        review: list[str] = []
        for row in rows:
            classification = tax.classify(
                category=row["category"], subcategory=row["subcategory"], title=row["title"]
            )
            if classification.resolved and classification.canonical:
                resolved.append((str(row["id"]), classification.canonical))
            else:
                review.append(str(row["id"]))

        async with conn.transaction():
            for canonical in {c for _id, c in resolved}:
                ids = [i for i, c in resolved if c == canonical]
                await conn.execute(
                    f"update public.{table} "
                    "   set canonical_category = $1, classification_status = 'valid' "
                    " where id = any($2::uuid[])",
                    canonical,
                    ids,
                )
            if review:
                await conn.execute(
                    f"update public.{table} "
                    "   set classification_status = 'needs_review' "
                    " where id = any($1::uuid[])",
                    review,
                )
        counts["classified"] += len(resolved)
        counts["needs_review"] += len(review)
        processed += len(rows)
        log.info(
            "backfill %s: +%d classified, +%d needs_review (%d processed)",
            table,
            len(resolved),
            len(review),
            processed,
        )
    return counts


async def rollback(conn: asyncpg.Connection, table: str) -> int:
    """Undo the backfill: clear both derived columns.

    Only the DERIVED fields. `title`, `category` and `subcategory` are the source
    data and were never touched, so this restores the exact pre-backfill state —
    which is what makes the whole change reversible without a restore.
    """
    if table not in _TABLES:
        raise ValueError(f"unknown table {table!r}")
    result = await conn.execute(
        f"update public.{table} "
        "   set canonical_category = null, classification_status = null "
        " where canonical_category is not null or classification_status is not null"
    )
    return int(result.rsplit(" ", 1)[-1] or 0)
