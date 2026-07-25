"""Cron one-shot: giveaway pickup-chat cleanup (blueprint §11.7, §10/§19).

Wraps ``app.cron.giveaway_chats`` (pickup-chat expiry + redaction + stale-request
purge). Unified ``app.tasks.*`` entrypoint for the Azure scheduled Job; the DO ofelia
keeps calling ``python -m app.cron.giveaway_chats``. Finite, no loop.
"""

from app.cron.giveaway_chats import main

if __name__ == "__main__":
    main()
