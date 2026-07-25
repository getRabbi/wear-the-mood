"""Generate TypeScript row types for the tables the admin console reads
DIRECTLY (not via jsonb RPCs), from the live dev schema (Phase Z).

The console imports these in its DAL via Pick<...>, so a renamed/dropped
column fails `tsc` at build time instead of erroring at runtime in prod.
Regenerate after any migration that touches these tables, then commit:

    .venv/Scripts/python.exe scripts/gen_admin_db_types.py

Writes admin-web/src/lib/types/db.generated.ts. Uses the same backend/.env
DSN as apply_sql.py (dev project — schema is identical to prod by §6).
"""

from __future__ import annotations

import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg  # noqa: E402
from dotenv import dotenv_values  # noqa: E402

from app.core.config import pick_migration_dsn  # noqa: E402

# Only the tables the console queries with .from("...") — RPC jsonb shapes are
# typed at the DAL by hand (they are projections, not rows).
TABLES = [
    "feature_flags",
    "tryon_model_presets",
    "plans",
    "admin_audit_log",
    "admin_users",
]

TS_TYPES = {
    "text": "string",
    "character varying": "string",
    "uuid": "string",
    "boolean": "boolean",
    "integer": "number",
    "bigint": "number",
    "smallint": "number",
    "numeric": "number",
    "double precision": "number",
    "real": "number",
    "timestamp with time zone": "string",
    "timestamp without time zone": "string",
    "date": "string",
    "jsonb": "Record<string, unknown>",
    "json": "Record<string, unknown>",
    "ARRAY": "string[]",
}


def pascal(table: str) -> str:
    return "".join(w.capitalize() for w in table.split("_"))


def main() -> int:
    env = dotenv_values(Path(__file__).resolve().parent.parent / ".env")
    dsn, _ = pick_migration_dsn(env)
    if not dsn:
        print("No CONNECTION_STRING(_DIRECT) in backend/.env")
        return 1

    out: list[str] = [
        "// GENERATED FILE — do not edit by hand.",
        "// Regenerate: backend> .venv/Scripts/python.exe scripts/gen_admin_db_types.py",
        f"// Generated {datetime.now(UTC).strftime('%Y-%m-%d %H:%M UTC')} from the dev schema.",
        "//",
        "// Row types for tables the console reads DIRECTLY via .from(). The DAL",
        "// uses Pick<> on these, so a renamed column fails the build (Phase Z).",
        "",
    ]
    with psycopg.connect(dsn, prepare_threshold=None) as conn:
        cur = conn.cursor()
        for table in TABLES:
            cur.execute(
                """
                select column_name, data_type, is_nullable
                  from information_schema.columns
                 where table_schema = 'public' and table_name = %s
                 order by ordinal_position
                """,
                (table,),
            )
            cols = cur.fetchall()
            if not cols:
                print(f"WARNING: table {table} not found; skipping")
                continue
            out.append(f"export type {pascal(table)}Row = {{")
            for name, data_type, nullable in cols:
                ts = TS_TYPES.get(data_type, "unknown")
                null = " | null" if nullable == "YES" else ""
                out.append(f"  {name}: {ts}{null};")
            out.append("};")
            out.append("")

    target = (
        Path(__file__).resolve().parent.parent.parent
        / "admin-web"
        / "src"
        / "lib"
        / "types"
        / "db.generated.ts"
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"wrote {target} ({len(TABLES)} tables)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
