"""Async job worker (Render `worker` service).

Placeholder until Phase 1 wires real try-on / batch job processing (CLAUDE.md §7).
Run with: ``python -m app.workers.worker``
"""

from __future__ import annotations

import logging
import time

from app.core.observability import init_sentry

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.worker")


def main() -> None:
    init_sentry()
    log.info("Fashion OS worker started (placeholder — no jobs to process yet).")
    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
