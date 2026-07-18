"""Cron one-shot: AI spend alert (blueprint §11.7, §14).

Wraps ``app.cron.spend_alert`` (warns when 24h ai_usage_log spend crosses the
threshold). Unified ``app.tasks.*`` entrypoint for the Azure scheduled Job; the DO
ofelia keeps calling ``python -m app.cron.spend_alert``. Finite, no loop.
"""

from app.cron.spend_alert import main

if __name__ == "__main__":
    main()
