"""Poll loading helpers (FEATURES_COMMUNITY_PLUS · Poll).

Builds PollResponse objects with AGGREGATE vote counts + only the caller's own
choice — used by the feed (batch) and the polls router (single). Never exposes
who voted what beyond the caller (§10).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

import asyncpg

from app.models.poll import PollOption, PollResponse

# A poll row + a jsonb map {option_index: count} of aggregate votes + the
# caller's own choice. $1 = caller id; the WHERE clause is appended per use.
_POLL_SELECT = """
    select pp.id, pp.post_id, pp.question, pp.options, pp.closes_at,
           coalesce((
             select jsonb_object_agg(v.option_index::text, v.cnt)
               from (select option_index, count(*) as cnt
                       from public.poll_votes
                      where poll_id = pp.id
                      group by option_index) v
           ), '{}'::jsonb) as counts,
           (select option_index from public.poll_votes
             where poll_id = pp.id and user_id = $1::uuid) as my_choice
      from public.post_polls pp
"""


def _poll_from_row(row: asyncpg.Record) -> PollResponse:
    options_raw = row["options"]
    if isinstance(options_raw, str):  # asyncpg returns jsonb as text
        options_raw = json.loads(options_raw)
    counts_raw = row["counts"]
    if isinstance(counts_raw, str):
        counts_raw = json.loads(counts_raw)
    counts = {int(k): int(v) for k, v in (counts_raw or {}).items()}
    options = [
        PollOption(
            index=int(o["index"]),
            label=o["label"],
            votes=counts.get(int(o["index"]), 0),
        )
        for o in options_raw
    ]
    closes_at = row["closes_at"]
    is_closed = closes_at is not None and closes_at <= datetime.now(UTC)
    return PollResponse(
        id=str(row["id"]),
        question=row["question"],
        options=options,
        total_votes=sum(counts.values()),
        my_choice=row["my_choice"],
        closes_at=closes_at,
        is_closed=is_closed,
    )


async def load_polls_for_posts(
    conn: asyncpg.Connection, user_id: str, post_ids: list[str]
) -> dict[str, PollResponse]:
    """post_id → PollResponse for the posts that have a poll (others omitted)."""
    if not post_ids:
        return {}
    rows = await conn.fetch(
        _POLL_SELECT + " where pp.post_id = any($2::uuid[])",
        user_id,
        post_ids,
    )
    return {str(r["post_id"]): _poll_from_row(r) for r in rows}


async def load_poll(conn: asyncpg.Connection, user_id: str, poll_id: str) -> PollResponse | None:
    row = await conn.fetchrow(
        _POLL_SELECT + " where pp.id = $2::uuid",
        user_id,
        poll_id,
    )
    return _poll_from_row(row) if row is not None else None
