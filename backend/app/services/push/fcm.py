"""Firebase Cloud Messaging sender (CLAUDE.md §20) — gated on the founder's
Firebase project.

Live delivery needs two things the founder provides: the `firebase-admin`
package installed in the push/cron service, and a service-account credentials
JSON (FCM_CREDENTIALS_JSON) for the project (FCM_PROJECT_ID). Until then the
resolver returns the stub, so importing this module never requires the package
(the import is lazy, inside the constructor).
"""

from __future__ import annotations

import asyncio
import json
import logging

from app.services.push.base import DeliveryStatus, PushMessage

log = logging.getLogger("fashionos.push")


def _classify(exc: Exception) -> DeliveryStatus:
    """Map a firebase-admin send failure to a DeliveryStatus (§6).

    Conservative by design: only errors that are *unambiguously* about this
    specific registration token invalidate it. Anything else is treated as
    transient/config so a message-construction bug or a credential outage can
    never mass-prune a user's real, live tokens.
    """
    from firebase_admin import exceptions as fx
    from firebase_admin import messaging

    # ── Permanent, token-specific: deactivate this token, don't retry. ──
    if isinstance(exc, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
        return DeliveryStatus.invalid_token
    if isinstance(exc, fx.InvalidArgumentError):
        # INVALID_ARGUMENT covers both a bad token *and* a bad message. Only the
        # former should kill the token — gate on the token-related wording so a
        # payload bug doesn't wipe every device.
        text = str(exc).lower()
        if "registration token" in text or "not a valid fcm" in text:
            return DeliveryStatus.invalid_token
        return DeliveryStatus.retryable

    # ── Credential / project problem: identical for every token → stop. ──
    if isinstance(exc, (fx.UnauthenticatedError, fx.PermissionDeniedError)):
        return DeliveryStatus.auth_error
    if exc.__class__.__module__.startswith("google.auth"):  # token-refresh failure
        return DeliveryStatus.auth_error

    # ── Transient: keep the token, a bounded retry may succeed. ──
    if isinstance(
        exc,
        (
            messaging.QuotaExceededError,
            fx.ResourceExhaustedError,
            fx.UnavailableError,
            fx.InternalError,
            fx.DeadlineExceededError,
        ),
    ):
        return DeliveryStatus.retryable

    return DeliveryStatus.retryable  # unknown → never invalidate a token on a guess


class FcmSender:
    name = "fcm"

    def __init__(self, credentials_json: str, *, app_name: str = "fashionos-push") -> None:
        # Lazy import: the package is only required when FCM is actually enabled.
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(json.loads(credentials_json))
        try:
            self._app = firebase_admin.get_app(app_name)
        except ValueError:
            self._app = firebase_admin.initialize_app(cred, name=app_name)

    async def send(self, token: str, message: PushMessage) -> DeliveryStatus:
        from firebase_admin import messaging

        android = None
        if message.android_channel:
            android = messaging.AndroidConfig(
                notification=messaging.AndroidNotification(channel_id=message.android_channel)
            )
        msg = messaging.Message(
            token=token,
            notification=messaging.Notification(title=message.title, body=message.body),
            data=message.data,
            android=android,
        )
        try:
            # firebase-admin's send is blocking HTTP — keep the caller async.
            await asyncio.to_thread(messaging.send, msg, app=self._app)
            return DeliveryStatus.ok
        except Exception as exc:  # best-effort; never raise into the caller (§20)
            status = _classify(exc)
            # Never log the full token (§11) — only a short prefix + the class.
            log.warning(
                "FCM send to %s… → %s (%s)",
                token[:8],
                status.value,
                exc.__class__.__name__,
            )
            return status
