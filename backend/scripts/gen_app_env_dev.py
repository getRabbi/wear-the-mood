"""Generate app/env/dev.json (git-ignored) from backend/.env.

Ops/dev helper. Writes ONLY client-safe public values (Supabase URL + anon key,
API base url, public telemetry hosts) — never secret keys. The Supabase URL is
derived from CONNECTION_STRING if SUPABASE_URL is still a placeholder.

Usage (run from backend/):  python scripts/gen_app_env_dev.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from dotenv import dotenv_values

repo_root = Path(__file__).resolve().parents[2]
env = dotenv_values(repo_root / "backend" / ".env")

url = (env.get("SUPABASE_URL") or "").strip()
anon = (env.get("SUPABASE_ANON_KEY") or "").strip()

if not url or "YOUR-PROJECT-REF" in url:
    conn = env.get("CONNECTION_STRING") or ""
    match = re.search(r"postgres\.([a-z0-9]+):", conn)
    if match:
        url = f"https://{match.group(1)}.supabase.co"

config = {
    "ENVIRONMENT": "dev",
    "API_BASE_URL": "http://10.0.2.2:8000",
    "SUPABASE_URL": url,
    "SUPABASE_ANON_KEY": anon,
    "SENTRY_DSN": "",
    "POSTHOG_API_KEY": "",
    "POSTHOG_HOST": "https://us.i.posthog.com",
}

dest = repo_root / "app" / "env" / "dev.json"
dest.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
print(
    f"wrote {dest.relative_to(repo_root)} (supabase_url set: {bool(url)}, anon set: {bool(anon)})"
)
