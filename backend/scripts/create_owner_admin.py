"""Bootstrap the FIRST admin (owner) for the Ops Console (admin panel §15).

Ops/dev tool only — NOT shipped in any client, NOT run on app startup. Promotes a
Supabase Auth user to an `owner` row in `public.admin_users` (status `active`), so
they can sign in to the console. Idempotent (re-running just re-affirms owner).

It reads the git-ignored backend env file (default `.env` = DEV, where migration
0024 is applied; pass `--env .env.prod` for prod AFTER 0024 is live there) and
connects with the DIRECT 5432 admin connection. Secrets are never printed.

Usage (run from backend/):
    # promote an account that ALREADY exists in Supabase Auth:
    python scripts/create_owner_admin.py --email owner@example.com

    # create the account first (email+password, email pre-confirmed) THEN promote
    # — handy for a console-login account when you signed up via OAuth/no password:
    python scripts/create_owner_admin.py --email owner@example.com --password 'S0me-Strong-Pass'

    # target prod (only after 0024 has been applied to prod):
    python scripts/create_owner_admin.py --email owner@example.com --env .env.prod

Env fallback: --email defaults to INITIAL_OWNER_EMAIL if set.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Make the backend package importable when run as `python scripts/...`.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg  # noqa: E402  (after sys.path setup)
from dotenv import dotenv_values  # noqa: E402

from app.core.config import pick_migration_dsn  # noqa: E402


def _create_auth_user(base_url: str, service_key: str, email: str, password: str) -> str:
    """Create a confirmed email/password user via the Supabase Auth Admin API and
    return its id. Uses stdlib only (no extra deps). The service key authenticates
    the call and is NEVER logged."""
    url = f"{base_url.rstrip('/')}/auth/v1/admin/users"
    body = json.dumps({"email": email, "password": password, "email_confirm": True}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"Supabase Auth admin create failed ({exc.code}): {detail}") from exc
    user_id = data.get("id")
    if not user_id:
        raise SystemExit(f"Auth admin create returned no id: {data}")
    return str(user_id)


def main() -> int:
    parser = argparse.ArgumentParser(description="Promote a Supabase user to console owner.")
    parser.add_argument("--email", help="owner email (defaults to INITIAL_OWNER_EMAIL)")
    parser.add_argument(
        "--password",
        help="if set AND the user doesn't exist, create the auth account with this password",
    )
    parser.add_argument("--env", default=".env", help="backend env file (default .env = dev)")
    args = parser.parse_args()

    env_path = Path(__file__).resolve().parent.parent / args.env
    if not env_path.exists():
        print(f"env file not found: backend/{args.env}")
        return 1
    env = dotenv_values(env_path)

    email = (args.email or env.get("INITIAL_OWNER_EMAIL") or "").strip()
    if not email:
        print("No email given. Pass --email or set INITIAL_OWNER_EMAIL in the env file.")
        return 2

    dsn, used_fallback = pick_migration_dsn(env)
    if not dsn:
        print(f"Neither CONNECTION_STRING_DIRECT nor CONNECTION_STRING set in backend/{args.env}")
        return 1
    if used_fallback:
        print("WARNING: CONNECTION_STRING_DIRECT not set - using the 6543 pooler.")

    with psycopg.connect(dsn, autocommit=True, prepare_threshold=None) as conn:
        with conn.cursor() as cur:
            # Guard: admin_users must exist (migration 0024 applied to THIS db).
            cur.execute("select to_regclass('public.admin_users')")
            if cur.fetchone()[0] is None:
                print(
                    "public.admin_users does not exist — apply migration 0024 to this "
                    f"database first (e.g. `python scripts/apply_all.py {args.env}`)."
                )
                return 1

            # Resolve the auth user by email.
            cur.execute(
                "select id::text, email from auth.users where lower(email) = lower(%s)",
                (email,),
            )
            row = cur.fetchone()

        if row is None:
            if not args.password:
                print(
                    f"No Supabase Auth user with email {email}.\n"
                    "Create the account first, then re-run. Either:\n"
                    "  - sign up in the app / Supabase dashboard, then re-run this script, or\n"
                    "  - re-run with --password '<strong-password>' to create it now."
                )
                return 1
            base_url = (env.get("SUPABASE_URL") or "").strip()
            service_key = (
                env.get("SUPABASE_SECRET_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY") or ""
            ).strip()
            if not base_url or not service_key:
                print(f"SUPABASE_URL and a service/secret key are required in backend/{args.env}.")
                return 1
            print(f"Creating Supabase Auth user {email} (email pre-confirmed)...")
            user_id = _create_auth_user(base_url, service_key, email, args.password)
        else:
            user_id, email = row[0], row[1]

        # Upsert the owner row + write an audit trail, in one transaction.
        with conn.cursor() as cur:
            cur.execute("begin")
            cur.execute(
                """
                insert into public.admin_users (user_id, email, role, status, created_by)
                values (%s, %s, 'owner', 'active', %s)
                on conflict (user_id) do update
                  set role = 'owner', status = 'active',
                      email = excluded.email, updated_at = now()
                returning role, status
                """,
                (user_id, email, user_id),
            )
            role, status = cur.fetchone()
            cur.execute(
                """
                insert into public.admin_audit_log
                  (admin_id, admin_email, action, target_type, target_id, reason, metadata)
                values (%s, %s, 'create_owner_admin', 'admin_user', %s,
                        'initial owner bootstrap (create_owner_admin.py)',
                        jsonb_build_object('env', %s::text))
                """,
                (user_id, email, user_id, args.env),
            )
            cur.execute("commit")

    print(f"OK - {email} is now {role}/{status} in admin_users (user_id {user_id}).")
    print("Point admin-web at THIS Supabase project, then sign in at /login.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
