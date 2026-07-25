"""Cron one-shot: news ingestion (blueprint §11.7).

Canonical logic lives in ``app.cron.news``; this thin wrapper is the unified
``app.tasks.*`` entrypoint the Azure scheduled Job calls, while the DigitalOcean
bridge's ofelia keeps calling ``python -m app.cron.news``. Finite, no loop; an
unhandled failure exits non-zero (Sentry captures handled failures).
"""

from app.cron.news import main

if __name__ == "__main__":
    main()
