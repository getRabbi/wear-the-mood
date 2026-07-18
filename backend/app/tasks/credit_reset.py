"""Cron one-shot: monthly credit reset backstop (blueprint §11.7, §18).

Wraps ``app.cron.credit_reset`` (no-rollover monthly grant backstop). Unified
``app.tasks.*`` entrypoint for the Azure scheduled Job; the DO ofelia keeps calling
``python -m app.cron.credit_reset``. Finite, no loop.
"""

from app.cron.credit_reset import main

if __name__ == "__main__":
    main()
