"""Prefetch (and optionally smoke-test) a rembg background-removal model.

The operator runs this once at activation time to download the chosen model into
the shared ``U2NET_HOME`` volume BEFORE flipping ``BG_MODEL``, so the worker never
downloads a model at execution time (§ BG upgrade Phase 2 / §14 Stage 2). It:

  * reads ``BG_MODEL`` (or ``--model``), validated against the two intended,
    download-able models (u2net, birefnet-general-lite);
  * constructs the rembg session ONCE (which downloads + caches the weights under
    ``U2NET_HOME``);
  * performs NO database work and logs no credentials or image bytes;
  * with ``--smoke``, additionally verifies a valid mask PNG and a valid
    transparent cutout PNG are produced from a tiny synthetic image;
  * exits non-zero on any failure.

Examples::

    python -m app.scripts.prefetch_bg_model                       # uses BG_MODEL
    python -m app.scripts.prefetch_bg_model --model birefnet-general-lite --smoke
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

from app.core.config import PREFETCHABLE_BG_MODELS, get_settings

log = logging.getLogger("fashionos.scripts.prefetch_bg_model")


def _smoke_test(session) -> None:
    """Round-trip a tiny synthetic image: mask-only PNG + transparent cutout PNG.
    Raises if either output is not a valid, correctly-typed image."""
    import io

    from PIL import Image
    from rembg import remove

    src = Image.new("RGB", (32, 32), (180, 120, 90))

    mask = remove(
        src, session=session, only_mask=True, post_process_mask=False, alpha_matting=False
    )
    if not hasattr(mask, "size"):
        mask = Image.open(io.BytesIO(mask))
    if mask.size != src.size:
        raise RuntimeError(f"mask size {mask.size} != source {src.size}")

    cutout = remove(src, session=session, post_process_mask=False, alpha_matting=False)
    if not hasattr(cutout, "size"):
        cutout = Image.open(io.BytesIO(cutout))
    if cutout.mode != "RGBA":
        raise RuntimeError(f"cutout mode {cutout.mode} is not RGBA (transparent)")
    log.info("smoke test OK: mask %s, cutout %s %s", mask.size, cutout.mode, cutout.size)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description="Prefetch a rembg background-removal model.")
    parser.add_argument(
        "--model",
        default=None,
        help="Model to prefetch (default: BG_MODEL). One of: " + ", ".join(PREFETCHABLE_BG_MODELS),
    )
    parser.add_argument(
        "--smoke", action="store_true", help="Also verify mask + transparent cutout output."
    )
    args = parser.parse_args(argv)

    model = (args.model or get_settings().background_model or "").strip()
    if model not in PREFETCHABLE_BG_MODELS:
        log.error(
            "unsupported model %r; expected one of %s", model, ", ".join(PREFETCHABLE_BG_MODELS)
        )
        return 2

    log.info("prefetching rembg model %r into U2NET_HOME=%s", model, os.environ.get("U2NET_HOME"))
    try:
        from rembg import new_session

        session = new_session(model)
    except Exception:
        log.exception("failed to construct rembg session for %r", model)
        return 1

    if args.smoke:
        try:
            _smoke_test(session)
        except Exception:
            log.exception("smoke test failed for %r", model)
            return 1

    log.info("model %r ready", model)
    return 0


if __name__ == "__main__":
    sys.exit(main())
