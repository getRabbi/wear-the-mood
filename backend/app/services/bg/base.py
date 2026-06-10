"""BackgroundRemover interface (CLAUDE.md §2.2).

Wardrobe cutout generation goes through this interface — never call a model/lib
directly from a router or worker. The concrete remover is chosen by env in
get_background_remover (rembg to start, BiRefNet/BEN2 later — all permissive,
§2.2). Implementations take the original image bytes and return PNG bytes with
the background removed, or raise so the worker can mark the item 'failed'.
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class BackgroundRemover(ABC):
    name: str

    @abstractmethod
    async def remove(self, image: bytes) -> bytes:
        """Return PNG bytes of [image] with its background removed, or raise."""
        raise NotImplementedError
