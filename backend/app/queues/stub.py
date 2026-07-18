"""In-memory queue provider for tests and local/offline runs (blueprint §11.2).

Not durable and not multi-process — it exists so the whole job lifecycle is
exercisable without Azure. Visibility timeout is modelled just enough for the
receive→claim→delete tests; the DB remains authoritative either way.
"""

from __future__ import annotations

import time
import uuid
from collections import defaultdict

from app.queues.base import QueueProvider, ReceivedSignal
from app.queues.message import QueueMessage


class _Entry:
    __slots__ = ("id", "message", "visible_at", "dequeue_count")

    def __init__(self, message: QueueMessage) -> None:
        self.id = uuid.uuid4().hex
        self.message = message
        self.visible_at = 0.0
        self.dequeue_count = 0


class StubQueue(QueueProvider):
    def __init__(self) -> None:
        self._queues: dict[str, list[_Entry]] = defaultdict(list)

    async def send_signal(self, queue: str, message: QueueMessage) -> None:
        self._queues[queue].append(_Entry(message))

    async def receive_signals(
        self, queue: str, *, max_messages: int = 1, visibility_timeout: int = 60
    ) -> list[ReceivedSignal]:
        now = time.monotonic()
        out: list[ReceivedSignal] = []
        for entry in self._queues[queue]:
            if len(out) >= max_messages:
                break
            if entry.visible_at <= now:
                entry.visible_at = now + visibility_timeout
                entry.dequeue_count += 1
                out.append(
                    ReceivedSignal(
                        message=entry.message,
                        receipt=entry.id,
                        dequeue_count=entry.dequeue_count,
                    )
                )
        return out

    async def delete_signal(self, queue: str, signal: ReceivedSignal) -> None:
        q = self._queues[queue]
        self._queues[queue] = [e for e in q if e.id != signal.receipt]

    # ── test helpers (not part of the interface) ──
    def depth(self, queue: str) -> int:
        """Total messages still present (visible or invisible)."""
        return len(self._queues[queue])

    def make_all_visible(self) -> None:
        for entries in self._queues.values():
            for entry in entries:
                entry.visible_at = 0.0
