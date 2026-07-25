"""BackgroundRemover interface (CLAUDE.md §2.2).

Wardrobe cutout generation goes through this interface — never call a model/lib
directly from a router or worker. The concrete remover is chosen by env in
get_background_remover (rembg to start, BiRefNet/BEN2 later — all permissive,
§2.2). Implementations take the original image bytes and return a
:class:`BackgroundRemovalResult` (the cutout PNG, an optional editable soft-alpha
mask, and the produced dimensions), or raise so the worker can mark the item
'failed'.

This module stays dependency-light on purpose (no Pillow / rembg import) so the
api, cron, CI and the stub path can import it freely.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class BackgroundRemovalResult:
    """The output of one background-removal run.

    * ``cutout_png`` — the transparent cutout, PNG bytes (fed to storage + tagger).
    * ``mask_png``  — the grayscale/alpha soft mask as lossless PNG, or ``None``
      when the remover produced no separable mask (stub / legacy path). Persisted
      as the private ``cutout_mask`` asset so the free editor can re-edit it.
    * ``width`` / ``height`` — the produced (normalized) dimensions; ``0`` when a
      lightweight remover (the stub) does not decode the image.
    * ``model`` — the resolved model identifier, e.g. ``birefnet-general-lite``.
    """

    cutout_png: bytes
    mask_png: bytes | None
    width: int
    height: int
    model: str


class BackgroundRemover(ABC):
    name: str

    @abstractmethod
    async def remove(self, image: bytes) -> BackgroundRemovalResult:
        """Remove the background of [image]; return a BackgroundRemovalResult or raise."""
        raise NotImplementedError
