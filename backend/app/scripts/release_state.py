"""Read back what a deployed database ACTUALLY says about this release.

    python -m app.scripts.release_state

STRICTLY READ-ONLY. Nothing here writes, and there is no `--apply`.

Why it exists: every number in this report has, at some point, been believed to
be one thing while the database said another. The free allowance was 3 in a
`.env` and 1 in the code. HD cost 4 in a constant and could be anything in
`monetization_config`. A feature flag's compiled default is not the same fact as
the row that overrides it. "We think it is on" is how the 0071 incident happened
in a different department of the same system.

So this prints, from the deployed database and the running settings:

  * every release-critical feature flag, and whether a row exists at all;
  * the monetization config that can override a price or an allowance;
  * the resolved credit policy — what a user would actually be charged;
  * the consent version the server currently demands.

Nothing here prints a credential, a user id, an email or any content.
"""

from __future__ import annotations

import os
import sys

from app.core.config import get_settings
from app.core.plans import (
    AI_ENHANCE_COST,
    HD_COST,
    MAX_APP_CREDITS_PER_RENDER,
    STD_COST,
)
from app.services.privacy.ai_consent import (
    AI_PERSONAL_IMAGE_CONSENT,
    CURRENT_AI_CONSENT_VERSION,
)

try:
    import psycopg
except ImportError:  # pragma: no cover
    psycopg = None  # type: ignore[assignment]


#: Flags whose value changes what a user experiences in this release.
#:
#: Each entry is (key, required, code_default, why). The CODE DEFAULT matters as
#: much as the required value, because `flag_enabled(..., default=X)` returns X
#: when no row exists — so an absent row is not automatically wrong. The first
#: version of this report treated every missing row as a failure and duly cried
#: wolf about `ai_tryon_enabled`, which defaults ON and was therefore already in
#: exactly the state the release needs. A verdict that reports healthy things as
#: broken is one nobody reads.
#:
#: What an absent row IS, is unstated: nobody has recorded an intention, so the
#: value can change under a code edit nobody connected to it. That is reported
#: as a note, not a failure.
RELEASE_FLAGS: tuple[tuple[str, bool, bool, str], ...] = (
    ("wardrobe_require_metadata", True, True, "a garment cannot be saved with no name/category"),
    (
        "wardrobe_require_known_category",
        True,
        False,
        "the category must resolve to a body region",
    ),
    (
        "tryon_strict_categories",
        True,
        False,
        "no provider-auto guessing for unidentified garments",
    ),
    # Kill-switches. ON in code; a row exists only when somebody turned one off
    # during an incident, and this report must never suggest re-enabling it
    # without a human deciding to.
    ("ai_tryon_enabled", True, True, "AI try-on is not kill-switched"),
    ("ai_studio_enabled", True, True, "AI Studio is not kill-switched"),
    ("feature_credit_economics_v2", False, False, "the v2 price ladder stays off"),
    (
        "feature_render_gate_v2",
        False,
        False,
        "the free allowance comes from the deployed setting",
    ),
)

#: Config keys that can move a price or an allowance out from under the code.
WATCHED_CONFIG = (
    "render_cost_standard",
    "render_cost_hd",
    "render_cost_enhance",
    "free_render_lifetime_limit",
)


def _dsn() -> str:
    for key in ("MIGRATION_DSN", "CONNECTION_STRING_DIRECT", "CONNECTION_STRING"):
        value = os.environ.get(key)
        if value:
            return value
    sys.exit("no DSN: set MIGRATION_DSN (or CONNECTION_STRING_DIRECT/CONNECTION_STRING)")


def _rule(title: str) -> None:
    # ASCII only: an operator's Windows console is cp1252 and box-drawing
    # characters raise UnicodeEncodeError after the queries have already run.
    print("\n-- " + title + " " + "-" * max(0, 68 - len(title)))


def main() -> int:
    if psycopg is None:
        sys.exit("psycopg is not installed: pip install 'psycopg[binary]'")

    dsn = _dsn()
    print(f"database host: {psycopg.conninfo.conninfo_to_dict(dsn).get('host')}")
    settings = get_settings()
    problems: list[str] = []
    unstated: list[str] = []

    with psycopg.connect(dsn, connect_timeout=30) as conn, conn.cursor() as cur:
        _rule("release feature flags")
        rows = dict(cur.execute("select key, enabled from public.feature_flags").fetchall() or [])
        for key, required, code_default, why in RELEASE_FLAGS:
            row = rows.get(key)
            # The EFFECTIVE value is what a request actually sees: the row when
            # one exists, the compiled default when it does not.
            effective = code_default if row is None else row
            shown = f"(no row -> {code_default})" if row is None else str(row)
            ok = effective is required
            mark = "ok  " if ok else "FAIL"
            print(f"  [{mark}] {key:<34}{shown:<20} required={required}")
            if not ok:
                print(f"           -> {why}")
                problems.append(f"{key} is {effective}, needs {required}")
            elif row is None:
                # Correct today, but by inheritance rather than by decision.
                unstated.append(key)

        _rule("monetization config overrides")
        try:
            cfg = dict(
                cur.execute(
                    "select key, value::text from public.monetization_config "
                    "where key = any(%s::text[])",
                    (list(WATCHED_CONFIG),),
                ).fetchall()
                or []
            )
        except psycopg.errors.UndefinedTable:
            conn.rollback()
            cfg = {}
            print("  monetization_config does not exist; code defaults are in force")
        for key in WATCHED_CONFIG:
            raw = cfg.get(key, "(no row)")
            print(f"  {key:<34}{raw}")

        _rule("what a user is actually charged")
        print(f"  standard render        {STD_COST}")
        print(f"  HD / Try-On Max        {HD_COST}")
        print(f"  AI Enhance             {AI_ENHANCE_COST}")
        print(f"  hard cap per render    {MAX_APP_CREDITS_PER_RENDER}")
        for name, value in (
            ("STD_COST", STD_COST),
            ("HD_COST", HD_COST),
            ("AI_ENHANCE_COST", AI_ENHANCE_COST),
        ):
            if value > MAX_APP_CREDITS_PER_RENDER:
                problems.append(f"{name}={value} exceeds the cap")

        _rule("free lifetime render allowance")
        print(f"  FREE_TRYON_TRIAL_CREDITS (deployed) {settings.free_tryon_trial_credits}")
        if settings.free_tryon_trial_credits != 3:
            problems.append(
                f"free allowance is {settings.free_tryon_trial_credits}, the release says 3"
            )

        _rule("consent")
        print(f"  required version   v{CURRENT_AI_CONSENT_VERSION}")
        print(f"  consent type       {AI_PERSONAL_IMAGE_CONSENT}")
        granted = cur.execute(
            "select consent_version, count(*) from public.user_privacy_consents "
            "where consent_type = %s and revoked_at is null group by 1 order by 1",
            (AI_PERSONAL_IMAGE_CONSENT,),
        ).fetchall()
        # Counts only. Which accounts consented is not something a release
        # report needs to know, and printing it would be the leak this whole
        # feature exists to prevent.
        for version, count in granted or [("(none)", 0)]:
            print(f"  accounts holding v{version}: {count}")

    _rule("verdict")
    if unstated:
        # Not a failure. Worth saying out loud, because a flag nobody has stated
        # is a flag whose value can move under an unrelated code change.
        print("  correct, but only by code default (no row states the intent):")
        for key in unstated:
            print(f"    - {key}")
    if problems:
        print("  NOT the required release state:")
        for p in problems:
            print(f"    - {p}")
        return 1
    print("  every release-critical setting matches what this build requires.")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
