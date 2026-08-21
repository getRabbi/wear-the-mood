"""Static checks on migrations 0073–0076 — the retention & monetization schema.

These run with no database, so CI proves the safety properties are present in
the SQL itself rather than discovered on a staging box. Four properties matter
more than the rest, and each one has broken a production deploy somewhere:

  1. **Additive only.** No DROP TABLE, no DROP COLUMN, no ALTER ... TYPE, no
     narrowing of an existing column. A migration that removes something is not
     reversible by re-running the previous one.
  2. **RLS on every user-owned table**, with a policy per operation. A user
     table with RLS enabled and no policy is not "secure", it is broken; one
     with policies and no RLS is not secure at all.
  3. **Flags seeded OFF.** Deploying the schema must not switch a feature on.
  4. **No price, allowance or product id is written.** §53: engineering
     completion is not a pricing change.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

_MIGRATIONS = Path(__file__).resolve().parents[3] / "supabase" / "migrations"

_FILES = {
    "ledger": "0073_render_cost_ledger.sql",
    "style_memory": "0074_style_memory.sql",
    "planner": "0075_planner_events_and_moods.sql",
    "monetization": "0076_monetization_config.sql",
}

#: Tables introduced here that hold USER-owned rows and therefore need RLS.
_USER_TABLES = (
    "style_memory_profiles",
    "style_memory_signals",
    "mood_plans",
    "style_events",
    "experiment_assignments",
    "monetization_events",
)


def _strip_comments(text: str) -> str:
    """Drop `--` line comments.

    Every one of these files opens with a long rationale block that names the
    very prices and product ids the "no pricing change" assertions forbid. That
    prose is the reason the rules exist; matching on it would make the tests
    unwritable and the comments unwriteable. So the assertions look at the
    STATEMENTS, which is what actually runs.
    """
    return chr(10).join(line.split("--", 1)[0] for line in text.splitlines())


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", _strip_comments(text)).lower()


@pytest.fixture(scope="module")
def sql() -> dict[str, str]:
    out: dict[str, str] = {}
    for key, name in _FILES.items():
        path = _MIGRATIONS / name
        assert path.exists(), f"missing migration: {path}"
        out[key] = path.read_text(encoding="utf-8")
    return out


@pytest.fixture(scope="module")
def all_sql(sql: dict[str, str]) -> str:
    return _norm("\n".join(sql.values()))


# ── 1. additive only ─────────────────────────────────────────────────────────


def test_nothing_is_dropped(all_sql: str) -> None:
    for forbidden in ("drop table", "drop column", "truncate", "delete from"):
        assert forbidden not in all_sql, f"destructive statement present: {forbidden}"


def test_no_column_changes_type_or_nullability(all_sql: str) -> None:
    # `drop policy if exists` / `drop trigger if exists` are re-runnability, not
    # destruction, and are matched by neither of these.
    assert "alter column" not in all_sql
    assert "set not null" not in all_sql


def test_every_added_column_is_optional(sql: dict[str, str]) -> None:
    """A column added to a table that already has rows must be nullable or
    defaulted; `add column ... not null` with no default fails outright on a
    populated table."""
    for name, text in sql.items():
        for match in re.finditer(r"add column if not exists ([^,;]+)", _norm(text)):
            clause = match.group(1)
            if "not null" in clause:
                assert "default" in clause, f"{name}: non-null column with no default: {clause}"


def test_every_statement_is_re_runnable(sql: dict[str, str]) -> None:
    """A migration that cannot be re-run is a migration that cannot be retried
    after a partial failure."""
    for name, text in sql.items():
        n = _norm(text)
        assert not re.search(r"create table (?!if not exists)", n), name
        assert not re.search(r"create (unique )?index (?!if not exists)", n), name
        # A view is replaced rather than guarded — `create or replace` is
        # already idempotent.
        assert not re.search(r"create view ", n), name


# ── 2. RLS ───────────────────────────────────────────────────────────────────


def test_every_user_table_enables_rls(all_sql: str) -> None:
    for table in _USER_TABLES:
        assert f"alter table public.{table} enable row level security" in all_sql, (
            f"{table} has no RLS"
        )


def test_every_user_table_is_scoped_to_its_owner(all_sql: str) -> None:
    for table in _USER_TABLES:
        policies = re.findall(rf"create policy \w+ on public\.{table}[^;]+;", all_sql)
        assert policies, f"{table} has RLS but no policy — every read would fail"
        for policy in policies:
            assert "auth.uid() = user_id" in policy, f"{table}: unscoped policy: {policy}"


def test_signals_are_append_only(sql: dict[str, str]) -> None:
    """A correction is a NEW signal, never an edit of the evidence — so the
    audit trail cannot be rewritten by the client."""
    n = _norm(sql["style_memory"])
    assert "create policy style_memory_signals_update_own" not in n


def test_operator_config_is_service_role_only(sql: dict[str, str]) -> None:
    """`monetization_config` is operator data. RLS on with no policy means only
    the service role reaches it — the app gets a composed snapshot instead."""
    n = _norm(sql["monetization"])
    assert "alter table public.monetization_config enable row level security" in n
    assert (
        "create policy" not in n.split("experiment_assignments")[0].split("monetization_config")[-1]
    )


def test_experiment_assignment_is_not_client_writable(sql: dict[str, str]) -> None:
    """A user who could insert their own assignment could pick their own price."""
    n = _norm(sql["monetization"])
    assert "create policy experiment_assignments_select_own" in n
    assert "create policy experiment_assignments_insert" not in n
    assert "create policy experiment_assignments_update" not in n


# ── 3. flags seeded OFF ──────────────────────────────────────────────────────


def test_every_seeded_flag_is_off(all_sql: str) -> None:
    seeded = re.findall(r"\('(feature_[a-z0-9_]+)', (true|false)", all_sql)
    assert seeded, "no flags seeded — the rollout levers would not exist"
    for key, enabled in seeded:
        assert enabled == "false", f"{key} is seeded ON"


def test_seeding_never_overwrites_an_existing_flag(all_sql: str) -> None:
    # `do nothing`, not `do update`: re-running a migration must never flip a
    # flag an operator has already turned on.
    for chunk in all_sql.split("insert into public.feature_flags")[1:]:
        assert "on conflict (key) do nothing" in chunk


def test_the_expected_flags_exist(all_sql: str) -> None:
    for key in (
        "feature_style_memory",
        "feature_style_memory_feedback",
        "feature_mood_planner_v2",
        "feature_event_planner",
        "feature_personalized_home_v2",
        "feature_render_gate_v2",
        "feature_paywall_v2",
        "feature_credit_economics_v2",
        "feature_credit_rollover_v2",
    ):
        assert key in all_sql, f"missing flag: {key}"


# ── 4. no pricing change ─────────────────────────────────────────────────────


def test_no_price_or_allowance_is_written(all_sql: str) -> None:
    """§53 in executable form. None of these may appear anywhere in the new
    schema: not the current prices, not the challenger prices, and not the
    current or proposed monthly allowances."""
    for forbidden in ("8.99", "15.99", "11.99", "21.99", "79.99", "149.99", "4.99"):
        assert forbidden not in all_sql, f"a price is written into the schema: {forbidden}"


def test_the_plans_table_is_never_touched(all_sql: str) -> None:
    """`public.plans` is the authority for tier, allowance and store product id.
    This project READS it and never writes it — the word may appear in a
    `comment on`, but no statement may target it."""
    for verb in ("alter table", "insert into", "update", "delete from", "drop table"):
        assert f"{verb} public.plans" not in all_sql, f"{verb} public.plans"
    assert "monthly_credits" not in all_sql


def test_no_store_product_id_is_written(all_sql: str) -> None:
    for product in ("topup_40", "pro_monthly", "pro_max_monthly"):
        assert product not in all_sql, f"a store product id is written: {product}"


def test_the_credit_tables_are_never_touched(all_sql: str) -> None:
    """The credit ledger and balances belong to the billing system. This project
    LINKS to them (ai_usage_log.job_id) and never writes their schema."""
    assert "alter table public.credits" not in all_sql
    assert "alter table public.credit_transactions" not in all_sql
    assert "public.user_subscriptions" not in all_sql


def test_the_free_allowance_starts_deferred_to_code(sql: dict[str, str]) -> None:
    """A jsonb null means "use FREE_TRYON_TRIAL_CREDITS". Seeding a NUMBER here
    would silently change every free user's allowance on deploy."""
    n = _norm(sql["monetization"])
    match = re.search(r"\('free_render_lifetime_limit', ('[^']*'|[a-z]+)", n)
    assert match, "free_render_lifetime_limit is not seeded"
    assert "null" in match.group(1)


def test_the_render_costs_start_deferred_to_code(sql: dict[str, str]) -> None:
    n = _norm(sql["monetization"])
    for key in ("render_cost_standard", "render_cost_hd", "render_cost_enhance"):
        match = re.search(rf"\('{key}', ('[^']*'|[a-z]+)", n)
        assert match, f"{key} is not seeded"
        assert "null" in match.group(1), f"{key} is seeded with a number"


def test_trial_and_rollover_start_disabled(sql: dict[str, str]) -> None:
    n = _norm(sql["monetization"])
    assert "('trial_enabled', 'false'" in n
    assert "('rollover_enabled', 'false'" in n


# ── the cost ledger ──────────────────────────────────────────────────────────


def test_the_ledger_records_what_a_render_cost_us_and_them(sql: dict[str, str]) -> None:
    n = _norm(sql["ledger"])
    for column in (
        "job_id",
        "endpoint",
        "mode",
        "resolution",
        "external_units",
        "wtm_credit_cost",
        "technical_retries",
        "quality_retries",
        "quality_state",
        "plan_tier",
    ):
        assert f"add column if not exists {column}" in n, f"ledger missing {column}"


def test_the_verdict_is_constrained_to_real_values(sql: dict[str, str]) -> None:
    n = _norm(sql["ledger"])
    assert "outcome is null or outcome in ('kept', 'rejected')" in n
    # NULL must stay expressible: "not answered" is not "rejected".
    assert "outcome text not null" not in n


def test_every_rejection_reason_is_constrained(sql: dict[str, str]) -> None:
    n = _norm(sql["ledger"])
    for reason in (
        "identity_issue",
        "garment_issue",
        "not_my_style",
        "body_proportion_issue",
        "color_issue",
        "occasion_mismatch",
        "other",
    ):
        assert reason in n, f"missing rejection reason: {reason}"


def test_check_constraints_do_not_hold_an_exclusive_lock(sql: dict[str, str]) -> None:
    """A plain `add constraint ... check` holds ACCESS EXCLUSIVE on
    `tryon_results` for the whole validating scan, blocking every read and
    write to try-on history. NOT VALID + a separate VALIDATE keeps concurrent
    traffic running."""
    n = _norm(sql["ledger"])
    assert n.count("not valid") == 2
    assert "validate constraint tryon_results_outcome_check" in n
    assert "validate constraint tryon_results_rejection_reason_check" in n


def test_the_economics_view_is_not_exposed_to_api_roles(sql: dict[str, str]) -> None:
    """A view does NOT inherit its base tables' RLS: by default it runs as its
    owner, so `render_economics` over the service-role-only `ai_usage_log`
    would hand every user's costs to any authenticated caller through
    PostgREST. Both guards must be present."""
    n = _norm(sql["ledger"])
    assert "revoke all on public.render_economics from anon, authenticated" in n
    assert "security_invoker = true" in n


def test_the_ledger_does_not_foreign_key_the_job(sql: dict[str, str]) -> None:
    """An accounting record must survive the deletion of the thing it describes:
    a user deleting a result must not erase what that render cost us."""
    n = _norm(sql["ledger"])
    assert "job_id uuid references" not in n


# ── 0077: consent history (added with the v2 re-consent) ─────────────────────


def test_the_consent_audit_log_is_additive_and_append_only() -> None:
    """A version bump overwrites the CURRENT consent row by design. The decision
    it replaced must survive somewhere, or the bump destroys the very evidence
    a consent system exists to produce."""
    path = _MIGRATIONS / "0077_ai_consent_audit_history.sql"
    assert path.exists(), f"missing migration: {path}"
    n = _norm(path.read_text(encoding="utf-8"))

    # Additive: the hot-path consent table is not touched at all.
    for forbidden in ("drop table", "drop column", "truncate", "delete from"):
        assert forbidden not in n, f"destructive statement: {forbidden}"
    assert "alter table public.user_privacy_consents" not in n

    # RLS on, readable by its owner, and writable by NOBODY through the API —
    # a client that could insert here could fabricate its own consent evidence.
    assert "alter table public.user_privacy_consent_events enable row level security" in n
    assert "create policy user_privacy_consent_events_select_own" in n
    assert "for insert" not in n
    assert "for update" not in n

    # The backfill is guarded, so re-running the migration cannot duplicate it.
    assert "where not exists" in n
    assert "'backfill'" in n
