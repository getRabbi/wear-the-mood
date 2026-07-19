"""Generate Studio Mannequin CANDIDATES with FASHN Model Create (admin/ops tool).

Ops-only — NOT shipped in any client. Single provider = FASHN. It generates 3–5
photorealistic fashion-mannequin candidates per preset category so the founder can
pick + approve images by hand. It does NOT upload to R2 and does NOT activate any
preset. Activation is a deliberate, separate, guarded step (`activate`) that runs
only on a manually-approved, reachable image URL — never a null/broken one.

Usage (run from backend/):
    python scripts/generate_mannequin_candidates.py plan
        # dry run: print the prompts + planned FASHN calls. No API call, no cost.

    python scripts/generate_mannequin_candidates.py generate --confirm [--env .env] [--count 4]
        # actually calls FASHN Model Create (SPENDS FASHN CREDITS). Writes candidate
        # URLs to scripts/out/mannequin_candidates.json for manual review. No R2, no
        # activation.

    python scripts/generate_mannequin_candidates.py activate <style> <url> [--env .env.prod]
        # AFTER manual approval + uploading the chosen image to R2/CDN: validates the
        # URL is reachable + an image, then sets tryon_model_presets.image_url +
        # is_active=true for that studio_tryon style. Refuses null/broken URLs.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import httpx  # noqa: E402
from dotenv import dotenv_values  # noqa: E402

from app.core.config import get_settings, is_secret_set, pick_migration_dsn  # noqa: E402
from app.services.tryon.fashn import FashnTryOnProvider  # noqa: E402

# The 5 studio mannequin categories (style key -> its descriptor).
MANNEQUIN_STYLES: dict[str, str] = {
    "female_studio": (
        "photorealistic adult female fashion mannequin with realistic female body proportions"
    ),
    "modest": (
        "photorealistic adult female fashion mannequin with realistic body proportions, "
        "modest styling"
    ),
    "male_studio": (
        "photorealistic adult male fashion mannequin with realistic male body proportions"
    ),
    "curve": (
        "photorealistic adult curve / plus-size female fashion mannequin with realistic "
        "curvy body proportions"
    ),
    "neutral": (
        "photorealistic gender-neutral adult fashion mannequin with realistic body proportions"
    ),
}

# Shared requirements appended to every prompt (from the provider strategy).
_PROMPT_SUFFIX = (
    ", full body, front facing, standing straight in a neutral, try-on-friendly "
    "pose, arms relaxed and slightly away from the torso, wearing a plain fitted "
    "neutral base outfit, plain seamless light-grey studio background, minimal or "
    "no facial detail, no bag, no accessories, soft even studio lighting, "
    "photorealistic digital fashion mannequin — NOT a toy doll, realistic human "
    "body proportions, high quality."
)

_OUT = Path(__file__).resolve().parent / "out" / "mannequin_candidates.json"


def build_prompts() -> dict[str, str]:
    """The Model-Create prompt for each mannequin category (pure — unit-testable)."""
    return {style: f"{desc}{_PROMPT_SUFFIX}" for style, desc in MANNEQUIN_STYLES.items()}


async def generate_candidates(
    provider: FashnTryOnProvider, *, count: int = 4
) -> dict[str, list[str]]:
    """Generate `count` (clamped 3–5) candidates per category via FASHN Model Create.
    Returns {style: [image_url, ...]}. Never activates anything."""
    count = max(3, min(5, count))
    prompts = build_prompts()
    out: dict[str, list[str]] = {}
    for style, prompt in prompts.items():
        # FASHN model-create returns up to 4 per call; loop seeds to reach `count`.
        urls: list[str] = []
        seed = 42
        while len(urls) < count:
            batch = await provider.model_create(
                prompt=prompt, num_images=min(4, count - len(urls)), seed=seed
            )
            urls.extend(batch)
            seed += 1
        out[style] = urls[:count]
        print(f"  {style}: {len(out[style])} candidate(s)")
    return out


def _fashn_provider(env: dict) -> FashnTryOnProvider:
    key = env.get("FASHN_API_KEY", "")
    if not is_secret_set(key):
        raise SystemExit("FASHN_API_KEY not set in the chosen env file.")
    base = env.get("FASHN_BASE_URL") or "https://api.fashn.ai"
    return FashnTryOnProvider(key, base_url=base)


def _cmd_plan() -> int:
    print("Studio Mannequin candidate prompts (FASHN Model Create) — DRY RUN:\n")
    for style, prompt in build_prompts().items():
        print(f"[{style}]\n  {prompt}\n")
    print(
        "Run `generate --confirm` to actually call FASHN (spends credits). "
        "Nothing is uploaded or activated by this tool."
    )
    return 0


def _cmd_generate(args: argparse.Namespace) -> int:
    if not args.confirm:
        print("Refusing to call FASHN without --confirm (it spends FASHN credits).")
        return 2
    env = dotenv_values(Path(__file__).resolve().parent.parent / args.env)
    provider = _fashn_provider(env)
    print(f"Generating {args.count} candidate(s) per category via FASHN Model Create…")
    results = asyncio.run(generate_candidates(provider, count=args.count))
    _OUT.parent.mkdir(parents=True, exist_ok=True)
    _OUT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"\nWrote candidate URLs to {_OUT}")
    print(
        "NEXT (manual): review the URLs, upload the chosen image per category to "
        "R2/CDN, then run `activate <style> <public_url>`. NOTHING was activated."
    )
    return 0


def _valid_image_url(url: str) -> bool:
    """True only if the URL is reachable and serves an image (guards activation)."""
    if not url or not url.strip():
        return False
    try:
        with httpx.Client(timeout=20.0, follow_redirects=True) as c:
            r = c.get(url)
            r.raise_for_status()
            return r.headers.get("content-type", "").lower().startswith("image/")
    except Exception as exc:
        print(f"  URL check failed: {exc}")
        return False


def _cmd_activate(args: argparse.Namespace) -> int:
    if args.style not in MANNEQUIN_STYLES:
        print(f"Unknown style '{args.style}'. One of: {', '.join(MANNEQUIN_STYLES)}")
        return 2
    if not _valid_image_url(args.image_url):
        print("Refusing to activate: image_url is missing, unreachable, or not an image.")
        return 2
    dsn, _ = pick_migration_dsn(dotenv_values(Path(__file__).resolve().parent.parent / args.env))
    if not dsn:
        print(f"No CONNECTION_STRING(_DIRECT) in backend/{args.env}")
        return 1
    import psycopg

    conn = psycopg.connect(dsn, autocommit=True, prepare_threshold=None)
    with conn, conn.cursor() as cur:
        cur.execute(
            "update public.tryon_model_presets set image_url = %s, is_active = true "
            "where kind = 'studio_tryon' and style = %s "
            "and %s is not null and length(trim(%s)) > 0 returning name",
            (args.image_url, args.style, args.image_url, args.image_url),
        )
        row = cur.fetchone()
    if row is None:
        print("No matching preset updated (nothing activated).")
        return 1
    print(f"Activated '{row[0]}' ({args.style}) -> {args.image_url}")
    return 0


def main() -> int:
    _ = get_settings  # ensure config importable
    p = argparse.ArgumentParser(description="Studio Mannequin candidate generator (FASHN).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan")
    g = sub.add_parser("generate")
    g.add_argument("--confirm", action="store_true")
    g.add_argument("--env", default=".env")
    g.add_argument("--count", type=int, default=4)
    a = sub.add_parser("activate")
    a.add_argument("style")
    a.add_argument("image_url")
    a.add_argument("--env", default=".env.prod")
    args = p.parse_args()

    if args.cmd == "plan":
        return _cmd_plan()
    if args.cmd == "generate":
        return _cmd_generate(args)
    if args.cmd == "activate":
        return _cmd_activate(args)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
