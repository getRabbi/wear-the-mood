"""Push-notification provider interface (CLAUDE.md §20).

Push always goes through a PushSender so the daily-stylist cron never hardcodes
Firebase. The stub is the default everywhere; the real FcmSender is selected only
when PUSH_PROVIDER=fcm and Firebase credentials are present (live delivery is the
founder-gated part — the rest of the loop is testable now).
"""

from __future__ import annotations

from typing import Protocol

from pydantic import BaseModel, Field


class PushMessage(BaseModel):
    """A notification to deliver to one device token."""

    title: str
    body: str
    # Data payload (e.g. a deep-link route); FCM requires string values.
    data: dict[str, str] = Field(default_factory=dict)
    # Android notification channel id (created natively in MainActivity, §20).
    # None → the manifest default channel. Routes events to the right channel
    # (e.g. referral/account → wtm_account, social → wtm_social).
    android_channel: str | None = None


class PushSender(Protocol):
    """Delivers a PushMessage to a single device token."""

    name: str

    async def send(self, token: str, message: PushMessage) -> bool:
        """Deliver to one token. Returns True on success. Implementations must be
        best-effort — never raise into the cron loop; log and return False."""
        ...
