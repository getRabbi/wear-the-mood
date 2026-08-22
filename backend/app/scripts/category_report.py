"""Read-only census of wardrobe categories, eligibility and duplicate candidates.

    python -m app.scripts.category_report

STRICTLY READ-ONLY. There is no `--apply`, no backfill and no delete, and that is
deliberate rather than an omission:

  * A CATEGORY BACKFILL would need something to backfill FROM, and the only
    remaining sources are the garment's own photograph (an AI call this work
    exists to remove) or its title (guessing). Neither is a person saying what
    their own clothes are, so neither happens. Legacy rows are repaired inline,
    one at a time, by the person who owns them.
  * NOTHING IS DELETED. Duplicate candidates are reported with the evidence that
    makes them candidates, and stop there. Two identical dresses in a closet may
    be two identical dresses.

No signed URL, no token, no email and no title is ever printed — a duplicate
report is a list of ids and counts, not a catalogue of what somebody owns. The
one exception is the stored CATEGORY string, which is a taxonomy value rather
than personal content, and is the whole subject of the report.

Reads its DSN from `MIGRATION_DSN` / `CONNECTION_STRING_DIRECT` /
`CONNECTION_STRING`, the same resolution the migration runner uses.
"""

from __future__ import annotations

import os
import sys

from app.services.tryon import taxonomy as tax

try:
    import psycopg
except ImportError:  # pragma: no cover
    psycopg = None  # type: ignore[assignment]


TOTAL = "select count(*) from public.wardrobe_items"

BY_CATEGORY = """
select coalesce(nullif(btrim(category), ''), '(blank)') as category,
       count(*) as n
  from public.wardrobe_items
 group by 1
 order by n desc, 1
"""

BY_STATUS = """
select coalesce(classification_status, '(null)') as status,
       coalesce(canonical_category, '(null)')    as canonical,
       count(*) as n
  from public.wardrobe_items
 group by 1, 2
 order by n desc
"""

BLANK = """
select count(*) from public.wardrobe_items
 where category is null or btrim(category) = ''
"""

# ELIGIBLE = the server's own rule: a renderable canonical role and no
# `needs_review` verdict. Mirrors `_to_response`'s `try_on_ready`.
#
# The capable list is inlined FROM PYTHON rather than calling
# `public.tryon_capable_category()`, even though that function exists and says
# the same thing. This is a diagnostic, and the first database it was ever
# pointed at turned out not to have 0070 applied — so depending on that function
# would make the report die precisely on the databases it is most needed for.
# One source of truth either way: `taxonomy.TRYON_CAPABLE_CATEGORIES`, which
# `test_sql_mirror_of_capable_categories_matches_python` pins to the SQL.
_CAPABLE = ", ".join(f"'{c}'" for c in tax.TRYON_CAPABLE_CATEGORIES if c != tax.LOOK_REFERENCE)

ELIGIBLE = f"""
select
  count(*) filter (
    where canonical_category in ({_CAPABLE})
      and coalesce(classification_status, 'valid') <> 'needs_review'
  ) as eligible,
  count(*) filter (
    where canonical_category is null
  ) as no_role,
  count(*) filter (
    where classification_status = 'needs_review'
  ) as needs_review,
  count(*) filter (
    where canonical_category is not null
      and canonical_category not in ({_CAPABLE})
  ) as unsupported_role
  from public.wardrobe_items
"""

# EXACT duplicates only, and only on evidence the storage ledger already holds:
# two items of the SAME owner whose cutouts are byte-identical (same content
# hash) or which were built from the same uploaded original.
#
# Deliberately NOT perceptual or near-match. A perceptual score is advisory at
# best, and a cleanup driven by one deletes somebody's second black dress.
DUPLICATES = """
with owned as (
  select m.user_id, m.owner_id as item_id, m.role, m.content_hash, m.object_key
    from public.media_assets m
   where m.owner_kind = 'wardrobe_item'
     and m.deleted_at is null
     and m.role in ('original', 'cutout')
),
grouped as (
  select user_id,
         role,
         coalesce(content_hash, object_key) as fingerprint,
         count(distinct item_id)            as items,
         array_agg(distinct item_id)        as item_ids
    from owned
   where coalesce(content_hash, object_key) is not null
   group by 1, 2, 3
)
select role, items, item_ids
  from grouped
 where items > 1
 order by items desc
 limit 50
"""


def _dsn() -> str:
    for key in ("MIGRATION_DSN", "CONNECTION_STRING_DIRECT", "CONNECTION_STRING"):
        value = os.environ.get(key)
        if value:
            return value
    sys.exit("no DSN: set MIGRATION_DSN (or CONNECTION_STRING_DIRECT/CONNECTION_STRING)")


def _rule(title: str) -> None:
    # ASCII only. An operator runs this from whatever console they have, and a
    # Windows one is cp1252 -- box-drawing characters raise UnicodeEncodeError
    # and take the whole report down AFTER it has already run the queries.
    print("\n-- " + title + " " + "-" * max(0, 68 - len(title)))


def main() -> int:
    if psycopg is None:
        sys.exit("psycopg is not installed: pip install 'psycopg[binary]'")

    dsn = _dsn()
    # WHICH database produced these numbers is half the report -- the same reason
    # `migration-sql` prints it. Host only, parsed by psycopg rather than sliced
    # out of the string by hand: a partial DSN through `cut` is one mistake away
    # from putting a credential in a log.
    print(f"database host: {psycopg.conninfo.conninfo_to_dict(dsn).get('host')}")

    with psycopg.connect(dsn, connect_timeout=30) as conn, conn.cursor() as cur:
        total = cur.execute(TOTAL).fetchone()[0]
        print(f"wardrobe items: {total}")

        _rule("by stored category")
        rows = cur.execute(BY_CATEGORY).fetchall()
        for category, n in rows:
            # Whether the taxonomy can turn this word into a body region. This
            # is the column that explains an "ineligible" count.
            readable = "ok " if tax.is_known_category(category) else "?? "
            print(f"  {readable} {category:<28}{n:>7}")
        print(f"  ({len(rows)} distinct values)")

        blank = cur.execute(BLANK).fetchone()[0]
        print(f"\n  null/blank category: {blank}")
        unreadable = sum(n for c, n in rows if not tax.is_known_category(c))
        print(f"  stored but unreadable as a role: {unreadable}")

        _rule("stored role + verdict")
        for status, canonical, n in cur.execute(BY_STATUS).fetchall():
            print(f"  {status:<16}{canonical:<18}{n:>7}")

        _rule("try-on eligibility")
        eligible, no_role, needs_review, unsupported = cur.execute(ELIGIBLE).fetchone()
        print(f"  eligible                    {eligible:>7}")
        print(f"  ineligible - no role        {no_role:>7}  (never categorised, or unreadable)")
        print(f"  ineligible - needs_review   {needs_review:>7}  (verdict already recorded)")
        print(f"  ineligible - role we cannot render {unsupported:>2}  (e.g. belts)")

        _rule("EXACT duplicate candidates (dry run - nothing is deleted)")
        dupes = cur.execute(DUPLICATES).fetchall()
        if not dupes:
            print("  none found on identical-bytes evidence.")
        else:
            print("  Same owner, byte-identical asset. Candidates only:")
            for role, items, item_ids in dupes:
                ids = ", ".join(str(i) for i in item_ids)
                print(f"  {role:<10}{items:>3} items   {ids}")
            print(
                "\n  These are CANDIDATES. Deleting any of them requires the owner's"
                "\n  explicit confirmation of the exact ids — two identical dresses"
                "\n  in a closet may be two identical dresses."
            )

        _rule("AI calls made by this report")
        print("  none. Every number above comes from SQL over columns the app already")
        print("  stores; no image is read, and no provider is contacted.")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
