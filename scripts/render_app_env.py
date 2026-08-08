#!/usr/bin/env python3
"""Generate ``app/env/<profile>.json`` from a COMMITTED feature policy plus credentials.

Why this exists
---------------
``app/env/prod.json`` is git-ignored and was, until now, the only authority on
which features a production artifact shipped with. That made a core feature's
existence depend on someone remembering to keep a hand-maintained file correct:

* every ``prod.json.bak-*`` snapshot in this repo has the local-background gates
  ABSENT, and a missing gate compiles to ``false``;
* Codemagic OVERWRITES the file from an env group, so a gate set on the founder's
  laptop is simply not in a CI build;
* ``bool.fromEnvironment`` reads only the exact string ``"true"``, so ``"True"``,
  ``"1"`` or a stray space silently compile the feature off.

Splitting the file fixes the class of failure rather than one instance:

* **feature policy** (which features exist) is committed, reviewable and
  diffable -- ``app/env/feature_policy.<profile>.json``;
* **credentials** (which backend, which keys) stay out of git, in the
  environment or in the existing untracked ``prod.json``.

This script merges the two. ``scripts/verify_local_cutout_release.py`` then
refuses to build a release whose merged result disagrees with the policy.

Usage
-----
CI, credentials from the environment (Codemagic ``app_prod_config``)::

    python3 scripts/render_app_env.py --profile prod --credentials env

Locally, credentials preserved from the existing untracked file::

    python3 scripts/render_app_env.py --profile prod --credentials file

The ``file`` mode is idempotent and self-healing: it keeps every credential
already in ``app/env/prod.json`` and rewrites the gates from the committed
policy, so a drifted or truncated local config snaps back to the invariant
instead of silently shipping.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
ENV_DIR = REPO_ROOT / "app" / "env"

#: Credential/config keys, in the order they are written. ``required`` keys make
#: the render fail loudly; the rest fall back to the stated default, which matches
#: the ``String.fromEnvironment`` default on the Dart side.
CREDENTIAL_KEYS: tuple[tuple[str, bool, str], ...] = (
    ("API_BASE_URL", True, ""),
    ("SUPABASE_URL", True, ""),
    ("SUPABASE_ANON_KEY", True, ""),
    ("SENTRY_DSN", False, ""),
    ("POSTHOG_API_KEY", False, ""),
    ("POSTHOG_HOST", False, "https://us.i.posthog.com"),
    ("GOOGLE_WEB_CLIENT_ID", False, ""),
    ("REVENUECAT_ANDROID_KEY", False, ""),
    ("REVENUECAT_IOS_KEY", False, ""),
    ("REVENUECAT_ENTITLEMENT_ID", False, "premium"),
)

#: Values printed literally in the build log. Feature gates belong here: they are
#: never secrets, and a generic "set" would read as "on" for a gate whose value is
#: the string "false" -- exactly the confusion to avoid during a staged rollout.
NON_SECRET_KEYS = frozenset(
    {"ENVIRONMENT", "API_BASE_URL", "POSTHOG_HOST", "REVENUECAT_ENTITLEMENT_ID"}
)


class RenderError(RuntimeError):
    """A configuration problem that must stop the build."""


def policy_path(profile: str) -> Path:
    return ENV_DIR / f"feature_policy.{profile}.json"


def load_policy(profile: str) -> dict[str, str]:
    """Read and validate the committed feature policy for ``profile``."""
    path = policy_path(profile)
    if not path.exists():
        raise RenderError(f"no committed feature policy at {path.relative_to(REPO_ROOT)}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RenderError(f"{path.name} is not valid JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise RenderError(f"{path.name} must be a JSON object")
    declared = document.get("profile")
    if declared != profile:
        raise RenderError(f"{path.name} declares profile {declared!r}, expected {profile!r}")
    gates = document.get("gates")
    if not isinstance(gates, dict) or not gates:
        raise RenderError(f"{path.name} has no 'gates' object")
    problems = [
        f"{name}={value!r}"
        for name, value in gates.items()
        if not isinstance(value, str) or value not in ("true", "false")
    ]
    if problems:
        raise RenderError(
            f"{path.name}: gate(s) must be the literal string 'true' or 'false' "
            "(Dart treats every other value as false): " + ", ".join(sorted(problems))
        )
    return {str(name): str(value) for name, value in gates.items()}


def read_existing(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RenderError(f"{path.name} exists but is not valid JSON: {exc}") from exc
    return document if isinstance(document, dict) else {}


def collect_credentials(source: str, existing: dict[str, Any]) -> dict[str, str]:
    """Resolve credentials from the environment or the existing untracked file."""
    resolved: dict[str, str] = {}
    missing: list[str] = []
    for key, required, default in CREDENTIAL_KEYS:
        if source == "env":
            value = os.environ.get(key)
        else:
            raw = existing.get(key)
            value = raw if isinstance(raw, str) else None
        if value is None or value == "":
            if required:
                missing.append(key)
                continue
            value = default
        resolved[key] = value
    if missing:
        where = (
            "the app_prod_config env group"
            if source == "env"
            else "app/env/prod.json (run with --credentials env in CI)"
        )
        raise RenderError(f"missing required credential(s) {', '.join(missing)} -- set them in {where}")
    return resolved


def render(profile: str, credentials_source: str, out_path: Path) -> dict[str, str]:
    gates = load_policy(profile)
    existing = read_existing(out_path)
    credentials = collect_credentials(credentials_source, existing)
    # ENVIRONMENT is derived from the profile, never inherited: a stale "staging"
    # in an untracked file must not survive into a production artifact.
    document: dict[str, str] = {"ENVIRONMENT": "prod"}
    document.update(credentials)
    document.update(gates)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return document


def summarise(document: dict[str, str], gate_names: frozenset[str]) -> str:
    """A secret-safe one-line summary: gates literal, everything else set/empty."""
    shown = {
        key: (value if key in NON_SECRET_KEYS or key in gate_names else ("set" if value else "empty"))
        for key, value in document.items()
    }
    return json.dumps(shown, sort_keys=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--profile",
        default="prod",
        help="feature-policy profile to apply (prod | ios-diagnostic)",
    )
    parser.add_argument(
        "--credentials",
        choices=("env", "file"),
        default="env",
        help="read credentials from the process environment (CI) or from the existing output file (local)",
    )
    parser.add_argument(
        "--out",
        default=str(ENV_DIR / "prod.json"),
        help="path of the dart-define file to write",
    )
    args = parser.parse_args(argv)

    try:
        document = render(args.profile, args.credentials, Path(args.out))
    except RenderError as exc:
        print(f"FATAL: {exc}", file=sys.stderr)
        return 1
    gate_names = frozenset(load_policy(args.profile))
    out = Path(args.out)
    rel = out.relative_to(REPO_ROOT) if out.is_relative_to(REPO_ROOT) else out
    print(f"{rel} <- feature_policy.{args.profile}.json + {args.credentials} credentials")
    print(f"  {summarise(document, gate_names)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
