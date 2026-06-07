"""Daily scheduled job (Render `cron` service).

Placeholder until Phase 2 wires the timezone-aware daily stylist push
(CLAUDE.md §20). Run with: ``python -m app.cron.daily``
"""

from __future__ import annotations

import logging

from app.core.observability import init_sentry

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron")


def main() -> None:
    init_sentry()
    log.info("Fashion OS daily cron ran (placeholder).")


if __name__ == "__main__":
    main()
