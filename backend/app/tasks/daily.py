"""Cron one-shot: daily stylist push (blueprint §11.7, §20).

Wraps ``app.cron.daily`` (sends only to users at their local DAILY_PUSH_HOUR, so it
runs hourly). Unified ``app.tasks.*`` entrypoint for the Azure scheduled Job; the DO
ofelia keeps calling ``python -m app.cron.daily``. Finite, no loop.
"""

from app.cron.daily import main

if __name__ == "__main__":
    main()
