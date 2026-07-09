"""Static checks on migration 0036 — the credits RLS lockdown + HD = Pro Max only.

The runtime RLS behaviour is covered by the DSN-gated live tests
(test_subscriptions_live). These assertions always run (no DB needed) so CI proves
the fix is present + correct in the migration itself.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

_MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "0036_credits_rls_lockdown_and_hd_promax_only.sql"
)


@pytest.fixture(scope="module")
def sql() -> str:
    assert _MIGRATION.exists(), f"missing migration: {_MIGRATION}"
    return _MIGRATION.read_text(encoding="utf-8")


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).lower()


def test_drops_the_dangerous_client_write_policy(sql: str) -> None:
    assert "drop policy if exists credits_rw_own on public.credits" in _norm(sql)


def test_creates_select_only_policy(sql: str) -> None:
    n = _norm(sql)
    assert "create policy credits_select_own on public.credits" in n
    assert "for select" in n
    assert "using (auth.uid() = user_id)" in n


def test_no_client_write_policy_on_credits(sql: str) -> None:
    # The migration creates EXACTLY ONE policy, and it is the SELECT-only one on
    # public.credits — so no client write policy is (re)introduced.
    n = _norm(sql)
    assert n.count("create policy") == 1
    assert "create policy credits_select_own on public.credits for select" in n


def test_hd_is_pro_max_only(sql: str) -> None:
    n = _norm(sql)
    assert "set hd_allowed = false, updated_at = now() where tier = 'pro'" in n
    assert "set hd_allowed = true, updated_at = now() where tier = 'pro_max'" in n
