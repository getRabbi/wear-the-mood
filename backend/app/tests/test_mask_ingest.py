"""Shared uploaded-mask ingestion service (local-first BG removal, Phase 1).

These lock the contract BOTH the free Erase/Restore editor and the (not yet added)
local-cutout endpoint depend on: normalize with the same helper as automatic
removal, require an exact dimension match, and preserve the soft alpha. The
editor's own endpoint tests live in ``test_wardrobe.py`` and must stay green
unchanged — that is the regression guard that this extraction changed nothing.
"""

from __future__ import annotations

import io

import pytest
from PIL import Image

from app.services.bg.imaging import ImageValidationError
from app.services.bg.mask_ingest import (
    ComposedCutout,
    compose_from_uploaded_mask,
    mask_alpha_area_ratio,
)

MAX_EDGE = 4096


def _jpeg(size: tuple[int, int] = (20, 20), color: tuple[int, int, int] = (200, 10, 10)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="JPEG")
    return buf.getvalue()


def _mask_png(size: tuple[int, int] = (20, 20), value: int = 140) -> bytes:
    """A single-channel 'L' mask PNG filled with ``value``."""
    buf = io.BytesIO()
    Image.new("L", size, value).save(buf, format="PNG")
    return buf.getvalue()


def _rgba_png(size: tuple[int, int] = (20, 20), alpha: int = 140) -> bytes:
    """An alpha-bearing PNG — the shape a device engine writes for a cutout."""
    buf = io.BytesIO()
    Image.new("RGBA", size, (5, 5, 5, alpha)).save(buf, format="PNG")
    return buf.getvalue()


# ── compose ──────────────────────────────────────────────────────────────────


def test_compose_returns_dimensions_and_preserves_soft_alpha() -> None:
    composed = compose_from_uploaded_mask(
        _jpeg((20, 20)), _mask_png((20, 20), 140), max_edge=MAX_EDGE
    )

    assert isinstance(composed, ComposedCutout)
    assert (composed.width, composed.height) == (20, 20)
    cutout = Image.open(io.BytesIO(composed.cutout_png))
    assert cutout.mode == "RGBA" and cutout.size == (20, 20)
    # 140 is an intermediate value: it must survive verbatim, never be thresholded.
    assert cutout.getpixel((10, 10))[3] == 140
    mask = Image.open(io.BytesIO(composed.mask_png))
    assert mask.mode == "L" and mask.getpixel((10, 10)) == 140


def test_compose_accepts_an_alpha_bearing_png_mask() -> None:
    """A device engine may hand us an RGBA PNG; the alpha band is the mask."""
    composed = compose_from_uploaded_mask(
        _jpeg((20, 20)), _rgba_png((20, 20), 90), max_edge=MAX_EDGE
    )
    assert Image.open(io.BytesIO(composed.cutout_png)).getpixel((3, 3))[3] == 90


def test_compose_snaps_only_near_extreme_alpha() -> None:
    """The sanitiser clamps <=3 and >=252 and leaves everything between alone —
    the rule that keeps lace, straps and hair from becoming a hard stencil."""
    near_transparent = compose_from_uploaded_mask(_jpeg(), _mask_png(value=2), max_edge=MAX_EDGE)
    near_opaque = compose_from_uploaded_mask(_jpeg(), _mask_png(value=253), max_edge=MAX_EDGE)
    midtone = compose_from_uploaded_mask(_jpeg(), _mask_png(value=200), max_edge=MAX_EDGE)

    assert Image.open(io.BytesIO(near_transparent.mask_png)).getpixel((1, 1)) == 0
    assert Image.open(io.BytesIO(near_opaque.mask_png)).getpixel((1, 1)) == 255
    assert Image.open(io.BytesIO(midtone.mask_png)).getpixel((1, 1)) == 200


def test_compose_rejects_mismatched_dimensions() -> None:
    with pytest.raises(ImageValidationError):
        compose_from_uploaded_mask(_jpeg((20, 20)), _mask_png((10, 10)), max_edge=MAX_EDGE)


def test_compose_rejects_non_png_mask() -> None:
    # A JPEG of the RIGHT size still fails: the format is checked after decoding.
    with pytest.raises(ImageValidationError):
        compose_from_uploaded_mask(_jpeg((20, 20)), _jpeg((20, 20)), max_edge=MAX_EDGE)


def test_compose_rejects_malformed_mask() -> None:
    with pytest.raises(ImageValidationError):
        compose_from_uploaded_mask(_jpeg((20, 20)), b"not-a-png", max_edge=MAX_EDGE)


def test_compose_rejects_malformed_original() -> None:
    with pytest.raises(ImageValidationError):
        compose_from_uploaded_mask(b"not-an-image", _mask_png((20, 20)), max_edge=MAX_EDGE)


def test_compose_rejects_source_over_max_edge() -> None:
    with pytest.raises(ImageValidationError):
        compose_from_uploaded_mask(_jpeg((80, 20)), _mask_png((80, 20)), max_edge=40)


def test_compose_matches_the_editor_wrapper_byte_for_byte() -> None:
    """The editor endpoint's ``_apply_uploaded_mask`` must stay a pure delegation —
    this is the regression guard for the Phase 1 extraction."""
    from app.routers.v1.wardrobe import _apply_uploaded_mask

    original, mask = _jpeg((24, 18)), _mask_png((24, 18), 175)
    cutout_png, mask_png = _apply_uploaded_mask(original, mask, MAX_EDGE)
    composed = compose_from_uploaded_mask(original, mask, max_edge=MAX_EDGE)

    assert cutout_png == composed.cutout_png
    assert mask_png == composed.mask_png


# ── server-side alpha-area sanity (never trusts the client's metric) ─────────


def test_alpha_area_ratio_reads_full_and_empty_masks() -> None:
    assert mask_alpha_area_ratio(_mask_png(value=255), max_edge=MAX_EDGE) == pytest.approx(1.0)
    assert mask_alpha_area_ratio(_mask_png(value=0), max_edge=MAX_EDGE) == pytest.approx(0.0)


def test_alpha_area_ratio_counts_soft_alpha_proportionally() -> None:
    """A half-alpha mask is ~0.5 coverage, not 0 or 1 — the pipeline preserves
    intermediate values, so the coverage measure has to as well."""
    ratio = mask_alpha_area_ratio(_mask_png(value=128), max_edge=MAX_EDGE)
    assert ratio == pytest.approx(128 / 255.0, abs=1e-6)


def test_alpha_area_ratio_on_a_partially_covered_mask() -> None:
    """Quarter of the frame opaque → ~0.25 coverage."""
    img = Image.new("L", (20, 20), 0)
    for x in range(10):
        for y in range(10):
            img.putpixel((x, y), 255)
    buf = io.BytesIO()
    img.save(buf, format="PNG")

    assert mask_alpha_area_ratio(buf.getvalue(), max_edge=MAX_EDGE) == pytest.approx(0.25)


def test_alpha_area_ratio_rejects_a_malformed_mask() -> None:
    with pytest.raises(ImageValidationError):
        mask_alpha_area_ratio(b"not-a-png", max_edge=MAX_EDGE)
