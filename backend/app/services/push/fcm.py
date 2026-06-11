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

from app.services.push.base import PushMessage

log = logging.getLogger("fashionos.push")


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

    async def send(self, token: str, message: PushMessage) -> bool:
        from firebase_admin import messaging

        msg = messaging.Message(
            token=token,
            notification=messaging.Notification(title=message.title, body=message.body),
            data=message.data,
        )
        try:
            # firebase-admin's send is blocking HTTP — keep the cron loop async.
            await asyncio.to_thread(messaging.send, msg, app=self._app)
            return True
        except Exception as exc:  # best-effort; never break the cron loop (§20)
            log.warning("FCM send to %s… failed: %s", token[:8], exc)
            return False
