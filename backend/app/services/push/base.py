"""Push-notification provider interface (CLAUDE.md §20).

Push always goes through a PushSender so the daily-stylist cron never hardcodes
Firebase. The stub is the default everywhere; the real FcmSender is selected only
when PUSH_PROVIDER=fcm and Firebase credentials are present (live delivery is the
founder-gated part — the rest of the loop is testable now).
"""

from __future__ import annotations

from enum import StrEnum
from typing import Protocol

from pydantic import BaseModel, Field


class DeliveryStatus(StrEnum):
    """Outcome of a single-token push, so callers can prune dead tokens without
    guessing from a bare bool (CLAUDE.md §20).

    - ``ok``            delivered.
    - ``invalid_token`` permanent (UNREGISTERED / not-registered / bad token /
                        sender-project mismatch) → deactivate that token, stop retrying.
    - ``retryable``     transient (unavailable / internal / resource-exhausted /
                        network) → keep the token; a bounded retry may re-send.
    - ``auth_error``    credential/project problem — affects EVERY token equally,
                        so callers should stop the run and invalidate NOTHING.
    """

    ok = "ok"
    invalid_token = "invalid_token"
    retryable = "retryable"
    auth_error = "auth_error"


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

    async def send(self, token: str, message: PushMessage) -> DeliveryStatus:
        """Deliver to one token. Returns a DeliveryStatus. Implementations must be
        best-effort — never raise into the caller; classify the failure and return
        the matching status so dead tokens can be pruned (§20)."""
        ...
