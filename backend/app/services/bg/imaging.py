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


#: Lossless-WebP effort. Pillow maps ``quality`` to the encoder's effort when
#: ``lossless=True`` — higher is smaller but slower. 60 sits near the knee: most of
#: the size win, without spending the upload saving back on CPU.
_WEBP_LOSSLESS_EFFORT = 60


def compose_cutout_webp(rgb: Image.Image, mask: Image.Image) -> bytes:
    """Same composite as [compose_cutout_png], encoded as LOSSLESS WebP.

    Byte-for-byte identical pixels — ``lossless=True`` means no chroma subsampling
    and no quantisation, so soft mask edges survive exactly as in the PNG. WebP is
    simply a better container for this content: a 1200x1600 RGBA cutout is roughly
    4 MB as PNG and about a quarter of that as lossless WebP.

    That matters because the size IS the latency. With the uploads already running
    concurrently, a real ingest still spent 3641 ms of 5089 ms in storage — that
    remainder is bandwidth for one multi-megabyte object, not ordering, so the only
    lever left is sending fewer bytes.

    Alpha is preserved: WebP supports a full 8-bit alpha channel, which is the whole
    reason a cutout cannot be JPEG.
    """
    out = rgb.convert("RGBA")
    out.putalpha(mask.convert("L"))
    buf = io.BytesIO()
    out.save(buf, format="WEBP", lossless=True, quality=_WEBP_LOSSLESS_EFFORT)
    return buf.getvalue()


# ── AI Enhance source preparation ────────────────────────────────────────────
# The enhancement provider is handed a base64 data URI, so what we send has to be
# a self-describing, universally decodable still. Three things go wrong without a
# dedicated step here:
#
#   1. A cutout carries an ALPHA channel. Flattened by the provider onto whatever
#      it defaults to (usually black), the model sees a silhouette on a void and
#      has no lighting or background left to improve — the only thing it can still
#      do is sharpen. Compositing onto a neutral studio white first gives it a
#      real product photo to work with.
#   2. The declared MIME must match the bytes. Local cutouts are lossless WebP
#      while the worker used to hard-code ``image/png``; re-encoding here makes the
#      pair correct by construction rather than by assumption.
#   3. A 4096px original is ~13 MB once base64-encoded. Bounding the long edge
#      keeps the request sane without ever upscaling a smaller source.
#
# Aspect ratio is always preserved, and an image already within the bound is never
# resampled — we re-encode losslessly, so no generation loss is introduced.

#: Neutral studio white that alpha is composited onto (never pure #FFFFFF black
#: clipping — plain white is what a catalog packshot background actually is).
_ENHANCE_MATTE = (255, 255, 255)

#: Downscale resampler for the enhance source. LANCZOS keeps garment texture and
#: stitching legible, which is exactly the detail the enhancement is judged on.
_ENHANCE_RESAMPLE = Image.LANCZOS


def prepare_enhance_source(data: bytes, *, max_edge: int) -> tuple[bytes, str, int, int]:
    """Turn arbitrary stored item bytes into a provider-ready enhance source.

    Returns ``(png_bytes, content_type, width, height)``. The content type is
    always the one that genuinely describes the returned bytes.

    Accepts a transparent cutout (WebP/PNG) or an ordinary photograph (JPEG/WebP)
    and normalises both to an opaque RGB PNG: EXIF orientation applied, alpha
    composited onto a studio-white matte, long edge bounded by ``max_edge`` with
    the aspect ratio preserved, encoded losslessly.

    Raises [ImageValidationError] when the bytes are not a usable still image.
    """
    try:
        img = Image.open(io.BytesIO(data))
        _reject_animated(img)
        img = ImageOps.exif_transpose(img)
        if img.mode in ("RGBA", "LA", "PA") or (img.mode == "P" and "transparency" in img.info):
            rgba = img.convert("RGBA")
            matte = Image.new("RGB", rgba.size, _ENHANCE_MATTE)
            matte.paste(rgba, mask=rgba.getchannel("A"))
            rgb = matte
        else:
            rgb = img.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ImageValidationError(f"Could not read image: {exc}") from exc

    if rgb.width <= 0 or rgb.height <= 0:
        raise ImageValidationError("Image has invalid dimensions.")

    longest = max(rgb.width, rgb.height)
    if longest > max_edge:
        scale = max_edge / longest
        # round() rather than int(): truncation can drop a pixel and shift the
        # ratio; max(1, ...) keeps a very thin image from collapsing to zero.
        target = (max(1, round(rgb.width * scale)), max(1, round(rgb.height * scale)))
        rgb = rgb.resize(target, _ENHANCE_RESAMPLE)

    buf = io.BytesIO()
    rgb.save(buf, format="PNG", compress_level=_PNG_COMPRESS_LEVEL)
    return buf.getvalue(), "image/png", rgb.width, rgb.height
