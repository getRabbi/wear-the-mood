"""pick_migration_dsn — migrations/admin DSN selection (Phase 2B).

Prefer the DIRECT 5432 (CONNECTION_STRING_DIRECT); fall back to the runtime 6543
pooler (CONNECTION_STRING) with a flag so the caller can warn. Runtime DB access
is unaffected (it always uses CONNECTION_STRING)."""

from __future__ import annotations

from app.core.config import pick_migration_dsn

_DIRECT = "postgresql://u:p@db.ref.supabase.co:5432/postgres"
_POOLED = "postgresql://u:p@aws-1.pooler.supabase.com:6543/postgres"


def test_prefers_direct_when_present() -> None:
    dsn, fallback = pick_migration_dsn(
        {"CONNECTION_STRING_DIRECT": _DIRECT, "CONNECTION_STRING": _POOLED}
    )
    assert dsn == _DIRECT
    assert fallback is False


def test_falls_back_to_pooler_with_flag() -> None:
    dsn, fallback = pick_migration_dsn({"CONNECTION_STRING": _POOLED})
    assert dsn == _POOLED
    assert fallback is True


def test_empty_direct_falls_back() -> None:
    dsn, fallback = pick_migration_dsn(
        {"CONNECTION_STRING_DIRECT": "  ", "CONNECTION_STRING": _POOLED}
    )
    assert dsn == _POOLED
    assert fallback is True


def test_none_when_neither_set() -> None:
    assert pick_migration_dsn({}) == (None, True)
    assert pick_migration_dsn({"CONNECTION_STRING_DIRECT": "", "CONNECTION_STRING": None}) == (
        None,
        True,
    )


def test_direct_is_stripped() -> None:
    dsn, fallback = pick_migration_dsn({"CONNECTION_STRING_DIRECT": f"  {_DIRECT}  "})
    assert dsn == _DIRECT
    assert fallback is False
