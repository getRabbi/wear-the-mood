"""Push notifications (CLAUDE.md §20). Resolve a PushSender by config, default
to the stub, fall back to the stub if FCM is selected but not yet usable."""

from __future__ import annotations

import logging
from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.push.base import PushMessage, PushSender
from app.services.push.stub import StubSender

log = logging.getLogger("fashionos.push")

__all__ = ["PushMessage", "PushSender", "StubSender", "get_push_sender"]


@lru_cache
def get_push_sender() -> PushSender:
    """Pick the push sender from settings. FCM only when explicitly enabled AND
    its credentials are present and loadable; otherwise the stub keeps the daily
    push loop runnable (CLAUDE.md §20)."""
    settings = get_settings()
    if settings.push_provider == "fcm" and is_secret_set(settings.fcm_credentials_json):
        try:
            from app.services.push.fcm import FcmSender

            return FcmSender(settings.fcm_credentials_json)
        except Exception as exc:  # missing package / bad creds -> stay runnable
            log.warning("FCM sender unavailable (%s); falling back to stub.", exc)
    return StubSender()
