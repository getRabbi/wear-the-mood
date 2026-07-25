"""Cron one-shot: nightly DB backup (blueprint §11.7, §14).

Wraps ``app.cron.backup`` (``pg_dump`` over the DIRECT/session DSN — never the 6543
transaction pooler — → private R2). Unified ``app.tasks.*`` entrypoint for the Azure
scheduled Job; the DO ofelia keeps calling ``python -m app.cron.backup``. Finite, no loop.
"""

from app.cron.backup import main

if __name__ == "__main__":
    main()
