"""Atomic claim-by-id for the split workers (blueprint §4.2, §4.4, §11.3).

A wake signal references a specific `job_id`; the worker claims THAT row with
`for update skip locked`, flipping it to `processing`, stamping the lease
(`locked_at`), and bumping the authoritative `attempt_count`. A row that is already
terminal, missing, or held by another replica returns None — the caller deletes the
duplicate/stale signal (§4.4 step 4). A `processing` row whose lease is older than
`stale_seconds` is re-claimable, which is how crash recovery re-runs a job.
"""

from __future__ import annotations

import asyncpg

_TRYON_CLAIM = """
update public.tryon_jobs
   set status = 'processing', locked_at = now(), attempt_count = attempt_count + 1
 where id = (
   select id from public.tryon_jobs
    where id = $1::uuid
      and (status = 'queued'
           or (status = 'processing'
               and (locked_at is null or locked_at < now() - make_interval(secs => $2::int))))
    for update skip locked
    limit 1
 )
returning id, user_id, person_image_url, garment_image_url,
          garment_image_urls, provider, hd, attempt_count
"""

_AI_CLAIM = """
update public.ai_jobs
   set status = 'processing', locked_at = now(), attempt_count = attempt_count + 1
 where id = (
   select id from public.ai_jobs
    where id = $1::uuid
      and (status = 'queued'
           or (status = 'processing'
               and (locked_at is null or locked_at < now() - make_interval(secs => $2::int))))
    for update skip locked
    limit 1
 )
returning id, user_id, job_type, source_item_id, style, hd, quality,
          credits_reserved, attempt_count
"""

# Leases on `cutout_locked_at` (0046), NOT `updated_at`. `updated_at` is bumped by
# trg_wardrobe_items_updated_at on every write — including recovery's re-signal —
# which reset the lease clock and livelocked abandoned rows so they could never be
# re-claimed. `cutout_locked_at` is written only here, by the claim itself.
# A NULL lease on a 'processing' row is claimable on purpose: that is how Azure
# adopts a row the (stopped) DigitalOcean worker abandoned at cutover.
_CUTOUT_CLAIM = """
update public.wardrobe_items
   set cutout_status = 'processing', cutout_locked_at = now(),
       attempt_count = attempt_count + 1
 where id = (
   select id from public.wardrobe_items
    where id = $1::uuid
      and (cutout_status = 'queued'
           or (cutout_status = 'processing'
               and (cutout_locked_at is null
                    or cutout_locked_at < now() - make_interval(secs => $2::int))))
    for update skip locked
    limit 1
 )
returning id, user_id, image_url, title, category, attempt_count
"""


async def claim_tryon_job(
    conn: asyncpg.Connection, job_id: object, *, stale_seconds: int
) -> asyncpg.Record | None:
    return await conn.fetchrow(_TRYON_CLAIM, str(job_id), stale_seconds)


async def claim_ai_job(
    conn: asyncpg.Connection, job_id: object, *, stale_seconds: int
) -> asyncpg.Record | None:
    return await conn.fetchrow(_AI_CLAIM, str(job_id), stale_seconds)


async def claim_cutout(
    conn: asyncpg.Connection, item_id: object, *, stale_seconds: int
) -> asyncpg.Record | None:
    return await conn.fetchrow(_CUTOUT_CLAIM, str(item_id), stale_seconds)
