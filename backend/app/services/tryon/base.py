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
        """Return the URL of the generated try-on image, or raise on failure."""
        raise NotImplementedError
