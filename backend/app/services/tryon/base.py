"""TryOnProvider interface (CLAUDE.md §2.1, §2.2).

All try-on generation goes through this interface — never call a vendor SDK from
a router or widget. The concrete provider is chosen by env in get_tryon_provider
(FASHN.ai at launch; self-hosted Leffa later). Implementations must retry/timeout
and surface a clean error so the worker can mark the job failed without charging.
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class TryOnProvider(ABC):
    name: str

    @abstractmethod
    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        """Return the URL of the generated try-on image, or raise on failure.

        Single-garment today: the client's full Outfit Stack is sent, but the AI
        job renders the PRIMARY garment (top/dress > bottom > accessory) and the
        rest of the stack is recorded client-side.

        TODO (multi-garment AI, follow-up — CLAUDE.md §7): add a
        ``generate_outfit(person_image_url, garment_image_urls: list[str])`` that
        composes a layered look, either via a provider that accepts a bundle or by
        chaining single calls (base -> top -> bottom -> accessories), feeding each
        result as the next call's person image. Needs a ``garment_image_urls``
        column on ``tryon_jobs`` (migration) + a worker branch on count > 1.
        """
        raise NotImplementedError
