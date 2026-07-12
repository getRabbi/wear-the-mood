"""Admin <-> app drift check (ADMIN_GAP_REPORT.md Phase Z).

Re-runs the static half of the sync audit in one command, so the next app
feature can't silently break the console again. Purely static — no DB, no
network. Run from backend/:

    .venv/Scripts/python.exe scripts/admin_drift_check.py

Checks:
  1. RPC drift        — every `.rpc("...")` name the console calls must be
                        defined by a migration (a renamed/removed function is
                        caught here instead of erroring at runtime).
  2. Report subjects  — every reports.subject_type the app (Dart) or backend
                        (Python) can file must be (a) resolved by the newest
                        admin_list_reports definition and (b) branched in the
                        console's reports page.
  3. Table coverage   — every `create table public.X` must be either reachable
                        from the console (named in admin-web/src or in an
                        admin migration) or explicitly allowlisted below with
                        a reason. A NEW table that is none of these fails the
                        check — that's the "you added a feature, now add it to
                        admin" tripwire (see docs/ADMIN_SYNC_CHECKLIST.md).

Exit code 0 = in sync; 1 = drift found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SUPABASE = REPO / "supabase"
ADMIN_SRC = REPO / "admin-web" / "src"
BACKEND_APP = REPO / "backend" / "app"
APP_LIB = REPO / "app" / "lib"

# Tables the console deliberately does NOT cover. Every entry needs a reason —
# if you remove the reason, remove the entry.
TABLE_ALLOWLIST: dict[str, str] = {
    # Private / biometric-adjacent user data (§10) — admin must not browse it.
    "wardrobe_items": "private closet data; counts only via dashboards",
    "outfits": "private user data",
    "tryon_photos": "private body photos (§10)",
    "tryon_results": "private try-on outputs; jobs listed per-user instead",
    "taste_signals": "private taste graph",
    "consents": "legal record; backend-only",
    "profiles": "covered via admin_list_users/admin_user_detail RPCs",
    # Infra / plumbing — nothing to moderate.
    "idempotency_keys": "server plumbing",
    "device_tokens": "push plumbing",
    "notifications": "user-facing inbox; campaigns are the admin surface",
    "referrals": "read via user detail when needed; no moderation surface",
    "blocks": "user-to-user privacy tool; no admin action applies",
    "follows": "social graph; visible via user detail counts",
    "likes": "engagement rows; visible via post counts",
    "news_items": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "challenges": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "challenge_entries": "entries are posts; moderated via posts",
    "community_awards": "derived leaderboard data",
    "daily_guides": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "offers": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "quizzes": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "quiz_questions": "ops-authored content — authoring UI is deferred (gap 1.9)",
    "quiz_responses": "private quiz answers",
    "post_polls": "moderated with their parent post",
    "poll_votes": "engagement rows",
    "tryon_avatars": "dormant feature (0033) — wire into admin when built",
    "entitlements": "server-owned RevenueCat mirror; tier shown via user detail",
    "ai_usage_log": "aggregated via admin_ai_cost_daily",
    "taste_vectors": "n/a",
}

FAILURES: list[str] = []


def read_all(root: Path, suffixes: tuple[str, ...]) -> str:
    chunks: list[str] = []
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.suffix in suffixes:
            chunks.append(p.read_text(encoding="utf-8", errors="ignore"))
    return "\n".join(chunks)


def check(name: str, problems: list[str]) -> None:
    if problems:
        FAILURES.extend(f"[{name}] {p}" for p in problems)
        print(f"FAIL  {name}: {len(problems)} problem(s)")
        for p in problems:
            print(f"      - {p}")
    else:
        print(f"ok    {name}")


def main() -> int:
    sql_text = read_all(SUPABASE, (".sql",))
    admin_text = read_all(ADMIN_SRC, (".ts", ".tsx"))
    backend_text = read_all(BACKEND_APP, (".py",))
    dart_text = read_all(APP_LIB, (".dart",))

    # ── 1. RPC drift ─────────────────────────────────────────────────────────
    called = set(re.findall(r"\.rpc\(\s*\"([a-z0-9_]+)\"", admin_text))
    defined = set(
        re.findall(r"create or replace function public\.([a-z0-9_]+)\s*\(", sql_text)
    )
    check("rpc-exists", sorted(f"console calls undefined RPC {n}" for n in called - defined))

    # ── 2. report subject types ──────────────────────────────────────────────
    filed = set(re.findall(r"subjectType:\s*'([a-z_]+)'", dart_text))
    # Backend-side literals: the subject_type sits in the VALUES list right after
    # the insert — a bounded window keeps unrelated string constants out.
    filed |= set(
        re.findall(r"insert into public\.reports[\s\S]{0,160}?'([a-z_]+)'", backend_text)
    )
    filed.discard("ai_output_self_report")  # a reason literal, not a subject type
    # The newest admin_list_reports definition wins (migrations are ordered).
    defs = re.findall(
        r"create or replace function public\.admin_list_reports.*?end;\s*\$\$",
        sql_text,
        re.S,
    )
    latest = defs[-1] if defs else ""
    resolved = set(re.findall(r"when '([a-z_]+)' then", latest))
    page = (ADMIN_SRC / "app" / "(protected)" / "reports" / "page.tsx").read_text(
        encoding="utf-8"
    )
    branched = set(re.findall(r"subject_type === \"([a-z_]+)\"", page))
    problems = []
    for s in sorted(filed):
        if s not in resolved:
            problems.append(
                f"subject_type '{s}' filed by the app/backend "
                "but NOT resolved by admin_list_reports"
            )
        if s not in branched:
            problems.append(
                f"subject_type '{s}' filed by the app/backend "
                "but NOT rendered by reports/page.tsx"
            )
    check("report-subjects", problems)

    # ── 3. table coverage ─────────────────────────────────────────────────────
    tables = set(
        re.findall(r"create table if not exists public\.([a-z0-9_]+)", sql_text)
    )
    admin_migrations = "\n".join(
        p.read_text(encoding="utf-8", errors="ignore")
        for p in sorted(SUPABASE.glob("migrations/*.sql"))
        if "admin" in p.name
    )
    problems = []
    for t in sorted(tables):
        if t in TABLE_ALLOWLIST:
            continue
        if t in admin_text or re.search(rf"public\.{t}\b", admin_migrations):
            continue
        problems.append(
            f"table '{t}' has no admin coverage and no allowlist entry "
            "(new feature? follow docs/ADMIN_SYNC_CHECKLIST.md)"
        )
    check("table-coverage", problems)

    # stale allowlist entries (table dropped/renamed) — warn-level, still fails
    check(
        "allowlist-fresh",
        sorted(
            f"allowlisted table '{t}' no longer exists in the schema"
            for t in TABLE_ALLOWLIST
            if t not in tables and t != "taste_vectors"
        ),
    )

    print()
    if FAILURES:
        print(f"DRIFT FOUND: {len(FAILURES)} problem(s). Admin is out of sync with the app.")
        return 1
    print("ADMIN IN SYNC — no drift detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
