"""Shared Pillow image helpers for background removal + the free cutout editor.

ONE normalization path is used by BOTH automatic removal (the rembg remover, on
the worker) and the manual correction endpoint (the api), so a cutout and a
hand-edited mask always line up on identical pixel dimensions.

Pillow is imported at module top — this module is imported ONLY by the rembg
remover (worker; Pillow ships with the rembg stack) and the correction router
(api; Pillow added to requirements.txt). It is NEVER imported by the stub path or
``app.services.bg.__init__``, so the light api/cron/CI environments that route to
the stub never pull Pillow through here.

Deliberately conservative (§ BG upgrade §8): decode safely, reject decompression
bombs / animated / oversized / zero-dim images, exif-transpose, and PRESERVE the
soft alpha — the only sanitiser clamps values that are already essentially fully
transparent/opaque. No global threshold, erosion, dilation, hole-fill, colour-key
or blur.
"""

from __future__ import annotations

import io
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

# High-quality resampler for the (rare) case where the model returns a mask at a
# different size than the normalized original — smooth, appropriate for alpha.
MASK_RESAMPLE = Image.LANCZOS
# Balanced PNG compression: good size without paying maximum CPU per cutout (§8.11).
_PNG_COMPRESS_LEVEL = 6
# Soft-alpha sanitiser bounds — ONLY near-extreme values are snapped, so straps,
# lace, sleeves and floral edges (all intermediate alpha) are preserved (§8.9).
_ALPHA_FLOOR = 3
_ALPHA_CEIL = 252
_SANITIZE_LUT = [0 if v <= _ALPHA_FLOOR else 255 if v >= _ALPHA_CEIL else v for v in range(256)]


class ImageValidationError(ValueError):
    """A source or mask image was malformed, animated, zero-dim or too large."""


@dataclass(frozen=True)
class NormalizedImage:
    """A decoded, exif-corrected RGB image + its (post-transpose) dimensions."""

    image: Image.Image  # mode == "RGB"
    width: int
    height: int


def _guard_dimensions(size: tuple[int, int], *, max_edge: int) -> None:
    w, h = size
    if w <= 0 or h <= 0:
        raise ImageValidationError("Image has invalid dimensions.")
    if w > max_edge or h > max_edge:
        raise ImageValidationError(f"Image edge {max(w, h)}px exceeds the {max_edge}px limit.")


def _reject_animated(img: Image.Image) -> None:
    if getattr(img, "is_animated", False) or getattr(img, "n_frames", 1) > 1:
        raise ImageValidationError("Animated images are not supported.")


def normalize_source_image(data: bytes, *, max_edge: int) -> NormalizedImage:
    """Decode + normalize an original wardrobe image for removal/correction.

    Header dimensions are checked BEFORE the pixels are decoded, so a
    decompression bomb is rejected without being rasterised. EXIF orientation is
    applied, the result is RGB, and the image is NEVER resized — we only reject an
    edge above ``max_edge``; the ~1600px wardrobe input is preserved as-is (§8).
    """
    try:
        img = Image.open(io.BytesIO(data))
        _guard_dimensions(img.size, max_edge=max_edge)  # header-only; pre-decode
        _reject_animated(img)
        img = ImageOps.exif_transpose(img)  # decodes + applies orientation
        rgb = img.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ImageValidationError(f"Could not read image: {exc}") from exc
    _guard_dimensions(rgb.size, max_edge=max_edge)  # post-transpose (w/h may swap)
    return NormalizedImage(image=rgb, width=rgb.width, height=rgb.height)


def sanitize_soft_mask(mask: Image.Image) -> Image.Image:
    """Snap only near-extreme alpha to 0/255; keep every intermediate value (§8.9)."""
    return mask.convert("L").point(_SANITIZE_LUT)


def _extract_mask_channel(img: Image.Image) -> Image.Image:
    """Reduce any accepted mask image to a single 8-bit 'L' channel: grayscale as
    itself, an alpha-bearing image via its alpha band (RGBA/LA/PA), else luminance."""
    if img.mode == "L":
        return img
    if img.mode in ("RGBA", "LA", "PA"):
        return img.getchannel("A")
    if img.mode == "P" and "transparency" in img.info:
        return img.convert("RGBA").getchannel("A")
    return img.convert("L")


def coerce_model_mask(mask: Image.Image, *, size: tuple[int, int]) -> Image.Image:
    """Turn a model's raw mask into a sanitised 'L' mask matching ``size`` exactly.
    Resizes with a high-quality resampler only if the library returned another size
    (rembg normally returns the input size), then preserves the soft alpha."""
    m = _extract_mask_channel(mask)
    if m.size != size:
        m = m.resize(size, MASK_RESAMPLE)
    return sanitize_soft_mask(m)


def decode_uploaded_mask(data: bytes, *, max_edge: int) -> Image.Image:
    """Validate an uploaded correction mask by DECODING it (not trusting the
    content-type) and return a single-channel 'L' mask at its own dimensions —
    NOT resized. Rejects non-PNG, animated, oversized or malformed uploads (§11).
    Callers require the exact dimensions and sanitise afterwards."""
    try:
        img = Image.open(io.BytesIO(data))
        if (img.format or "").upper() != "PNG":
            raise ImageValidationError("Mask must be a PNG image.")
        _guard_dimensions(img.size, max_edge=max_edge)
        _reject_animated(img)
        img.load()
        return _extract_mask_channel(img)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ImageValidationError(f"Could not read mask: {exc}") from exc


def encode_mask_png(mask: Image.Image) -> bytes:
    """Encode a 'L' mask as a lossless PNG (§8.11)."""
    buf = io.BytesIO()
    mask.convert("L").save(buf, format="PNG", compress_level=_PNG_COMPRESS_LEVEL)
    return buf.getvalue()


def compose_cutout_png(rgb: Image.Image, mask: Image.Image) -> bytes:
    """Apply a soft-alpha 'L' mask to an RGB image and encode a transparent PNG
    cutout with balanced (not maximum-CPU) compression (§8.10/§8.11)."""
    out = rgb.convert("RGBA")
    out.putalpha(mask.convert("L"))
    buf = io.BytesIO()
    out.save(buf, format="PNG", compress_level=_PNG_COMPRESS_LEVEL)
    return buf.getvalue()
