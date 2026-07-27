"""Shared ingestion of a CLIENT-SUPPLIED cutout mask (local-first BG removal §5, §6).

TWO callers hand us a PNG mask produced off-server and expect the cutout to be
re-composited from the stored ORIGINAL:

  * the free Erase/Restore editor — ``PUT /v1/wardrobe/{id}/cutout-mask`` — where
    the mask is a human hand-edit of an existing cutout;
  * the local-first ingestion endpoint — ``POST /v1/wardrobe/local-cutout`` — where
    the mask came from Apple Vision or Google ML Kit on the user's device.

Both must normalize the original with the SAME helper the automatic rembg worker
uses (``app.services.bg.imaging``), require an EXACT dimension match, and preserve
the soft alpha. Keeping that in one place is the whole point of this module: a
divergence between the two paths would produce cutouts that no longer line up with
the stored original, and the editor could no longer re-edit a locally-created mask.

Everything here is pure and CPU-bound — callers run it in a thread. Nothing in this
module trusts the client: dimensions, decodability and alpha sanity are all
re-derived from the bytes, never read from a client-supplied metric (§5).

Pillow is imported transitively through ``imaging``, which is why this module is
imported lazily by the routers (the light api/cron/CI paths must not pull Pillow
through ``app.services.bg.__init__``).
"""

from __future__ import annotations

from dataclasses import dataclass

from app.services.bg import imaging


@dataclass(frozen=True)
class ComposedCutout:
    """A cutout re-composited from a stored original + an uploaded soft mask.

    ``cutout_png`` is the transparent RGBA cutout, ``mask_png`` the sanitised
    single-channel mask (both lossless PNG), and ``width``/``height`` the
    normalized source dimensions the two share.
    """

    cutout_png: bytes
    mask_png: bytes
    width: int
    height: int


def compose_from_uploaded_mask(
    original: bytes, mask_bytes: bytes, *, max_edge: int
) -> ComposedCutout:
    """Normalize ``original``, validate ``mask_bytes`` against it, and compose.

    The exact behaviour the editor has shipped with, unchanged:

      1. ``normalize_source_image`` — header-first bomb guard, animated reject,
         EXIF transpose, RGB. The image is never resized.
      2. ``decode_uploaded_mask`` — decodes rather than trusting the content-type,
         rejects non-PNG/animated/oversized, reduces to a single 'L' channel at its
         own dimensions.
      3. Exact dimension match required — a mask that does not line up with the
         stored original is a hard error, never silently resized.
      4. ``sanitize_soft_mask`` — snaps only near-extreme alpha (<=3 / >=252) so
         straps, lace and hair keep their intermediate values.
      5. Compose the transparent cutout + re-encode the mask.

    Raises ``imaging.ImageValidationError`` (a ``ValueError``) on any invalid input
    so callers can map it to a typed 422 (§13).
    """
    norm = imaging.normalize_source_image(original, max_edge=max_edge)
    mask = imaging.decode_uploaded_mask(mask_bytes, max_edge=max_edge)
    if mask.size != (norm.width, norm.height):
        raise imaging.ImageValidationError(
            f"Mask dimensions {mask.size} must match the image {(norm.width, norm.height)}."
        )
    mask = imaging.sanitize_soft_mask(mask)
    return ComposedCutout(
        cutout_png=imaging.compose_cutout_png(norm.image, mask),
        mask_png=imaging.encode_mask_png(mask),
        width=norm.width,
        height=norm.height,
    )


def mask_alpha_area_ratio(mask_png: bytes, *, max_edge: int) -> float:
    """Mean alpha of a sanitised mask, in ``0.0..1.0`` — the server's OWN measure of
    how much of the frame the foreground covers.

    This exists so the local-cutout endpoint can sanity-check coverage without
    trusting the device's ``foregroundAreaRatio`` (§5: "Never trust client metrics
    as security validation"). It is the mean of the 8-bit mask, so a soft edge
    contributes proportionally rather than being counted as fully present or fully
    absent — deliberate, since the whole pipeline preserves intermediate alpha.
    """
    mask = imaging.sanitize_soft_mask(imaging.decode_uploaded_mask(mask_png, max_edge=max_edge))
    histogram = mask.histogram()
    pixels = sum(histogram)
    if pixels <= 0:
        raise imaging.ImageValidationError("Mask has no pixels.")
    weighted = sum(value * count for value, count in enumerate(histogram))
    return weighted / (pixels * 255.0)
