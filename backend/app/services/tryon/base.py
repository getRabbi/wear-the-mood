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
        """Return the URL of the generated try-on image for ONE garment, or raise
        on failure.

        The interface stays single-garment because our provider (FASHN) applies
        one garment per call. MULTI-GARMENT looks are composed in the worker by
        CHAINING this method — each render's output becomes the next render's
        person image, in the client-provided render order (dress/base → top →
        bottom → outerwear → shoes/bag/accessory). See
        ``app.workers.tryon_worker.process_job``. A provider that natively accepts
        a bundle could override this strategy later.
        """
        raise NotImplementedError
