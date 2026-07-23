"""RemBG **batch** entrypoint for the event-driven Azure Container Apps Job
``wtm-rembg-job`` (Phase 5 §A/B).

Same critical path as ``app.workers.rembg_worker`` — wake on the ``jobs`` queue,
claim the exact row with ``for update skip locked``, cut out, mark ready, emit one
``enrichment`` signal — but it **terminates** instead of looping forever, so the
Job execution ends and Azure stops billing.

The rembg model is loaded ONCE here, before the drain loop, so its cost is paid
once per execution and amortised across up to ``REMBG_BATCH_MAX_JOBS`` images
rather than once per image.

Run with: ``python -m app.workers.rembg_batch``
"""

from __future__ import annotations

import asyncio
import logging
import time

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.queues import get_queue_provider
from app.services.bg import prewarm_background_remover
from app.workers.batch import run_batch
from app.workers.rembg_worker import run_once

log = logging.getLogger("fashionos.worker.rembg.batch")


async def _run() -> int:
    s = get_settings()
    started = time.monotonic()

    has_db = await init_db()
    if not has_db:
        log.error("CONNECTION_STRING not set — rembg job cannot run.")
        return 1
    provider = get_queue_provider()

    # Construct the remover up front. prewarm_background_remover() is lru_cached and
    # RembgBackgroundRemover.__init__ calls new_session(), so this loads the ONNX
    # model exactly once per execution; every job in the batch then reuses it. Doing
    # it here also keeps the cost visible in startup_s instead of hiding inside the
    # first job's timing. A model that cannot load FAILS the execution before any
    # row is claimed, so no item is left stranded in 'processing' (§ BG upgrade §8).
    try:
        prewarm_background_remover()
    except Exception:
        log.exception("background remover failed to initialize; failing execution before claiming")
        await provider.close()
        await close_db()
        return 1
    startup_s = time.monotonic() - started
    log.info("rembg job ready in %.1fs (model loaded once)", startup_s)

    try:
        res = await run_batch(
            conn_factory=get_pool().acquire,
            provider=provider,
            run_once=run_once,
            stale_seconds=s.worker_stale_seconds,
            max_attempts=s.worker_max_attempts,
            max_jobs=s.rembg_batch_max_jobs,
            max_seconds=s.batch_max_seconds,
            idle_exit_seconds=s.batch_idle_exit_seconds,
            label="rembg",
            startup_s=startup_s,
        )
    finally:
        await provider.close()
        await close_db()
    # An execution that errored on EVERY poll and processed nothing is a broken
    # environment, not a drained queue — it must exit non-zero so Azure reports
    # Failed. Returning 0 here previously masked a totally failed execution as
    # "Succeeded", which hid a real fault during Phase 5 testing.
    if res.errors and not res.processed:
        log.error(
            "rembg batch made no progress in %d polls (%d errors) — failing execution",
            res.polls,
            res.errors,
        )
        return 1
    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_sentry()
    log.info("Fashion OS rembg BATCH job starting.")
    raise SystemExit(asyncio.run(_run()))


if __name__ == "__main__":
    main()
