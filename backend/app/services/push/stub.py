"""Stub push sender — the default until Firebase is wired (CLAUDE.md §20).

Logs what it would deliver and reports success, so the whole daily-push loop
(selection -> compose -> send) is runnable and testable with no Firebase project,
mirroring the stub-first try-on / LLM providers.
"""

from __future__ import annotations

import logging

from app.services.push.base import DeliveryStatus, PushMessage

log = logging.getLogger("fashionos.push")


class StubSender:
    name = "stub"

    async def send(self, token: str, message: PushMessage) -> DeliveryStatus:
        log.info("push (stub) -> %s…: %s — %s", token[:8], message.title, message.body)
        return DeliveryStatus.ok
