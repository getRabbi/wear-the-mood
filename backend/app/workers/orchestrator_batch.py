"""AI orchestrator **batch** entrypoint for the event-driven Azure Container Apps
Job ``wtm-ai-orchestrator-job`` (Phase 5 §A/B).

Same surfaces as ``app.workers.ai_orchestrator`` — try-on, AI Studio, and wardrobe
enrichment drained off the ``enrichment`` queue — but it terminates when the batch
is done so the Job execution ends and billing stops.

Per-job work here is lighter than rembg (no ONNX model), so the batch is larger:
``ORCHESTRATOR_BATCH_MAX_JOBS`` defaults to 20.

Run with: ``python -m app.workers.orchestrator_batch``
"""

from __future__ import annotations

import asyncio
import logging
import time

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.queues import get_queue_provider
from app.workers.ai_orchestrator import run_once
from app.workers.batch import run_batch

log = logging.getLogger("fashionos.worker.orchestrator.batch")


async def _run() -> int:
    s = get_settings()
    started = time.monotonic()

    has_db = await init_db()
    if not has_db:
        log.error("CONNECTION_STRING not set — orchestrator job cannot run.")
        return 1
    provider = get_queue_provider()
    startup_s = time.monotonic() - started

    try:
        await run_batch(
            conn_factory=get_pool().acquire,
            provider=provider,
            run_once=run_once,
            stale_seconds=s.worker_stale_seconds,
            max_attempts=s.worker_max_attempts,
            max_jobs=s.orchestrator_batch_max_jobs,
            max_seconds=s.batch_max_seconds,
            idle_exit_seconds=s.batch_idle_exit_seconds,
            label="orchestrator",
            startup_s=startup_s,
        )
    finally:
        await provider.close()
        await close_db()
    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_sentry()
    log.info("Fashion OS AI orchestrator BATCH job starting.")
    raise SystemExit(asyncio.run(_run()))


if __name__ == "__main__":
    main()
