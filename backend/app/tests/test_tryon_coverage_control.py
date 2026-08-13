"""Try-on COVERAGE — the operational switch beside the rights gate (0068).

The property every test here defends is one sentence: coverage can only ever
narrow. Rights say whether we may; coverage says whether we do; and no
arrangement of the second may produce an eligible product the first refused.

Two layers, as in test_image_rights_control.py:

  * **Static** assertions on the migration, which always run. They pin the
    things that must hold even where no database is reachable — that the
    migration inserts no policy rows, grants no rights, and that `off` is
    checked before any product override.

  * **Live** assertions against a real Postgres, skipped without a DSN or where
    0068 has not been applied. The precedence matrix is behaviour, and a fake
    connection asserting on query text would only prove the text was written.

Nothing here touches an existing row: every live test builds its own merchant
under a unique slug and removes it afterwards.
"""

from __future__ import annotations

import asyncio
import re
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest

_MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "0068_merchant_product_tryon_controls.sql"
)


@pytest.fixture(scope="module")
def sql() -> str:
    assert _MIGRATION.exists(), f"missing migration: {_MIGRATION}"
    return _MIGRATION.read_text(encoding="utf-8")


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).lower()


def _body(normalised: str, fn: str) -> str:
    """The dollar-quoted body of one function in the normalised migration.

    Everything after the declaration is `... as $$ BODY $$;`, so the body is the
    first `$$`-delimited chunk that follows the name — asserting on the whole
    file instead would let a rule stated in one function satisfy a test about
    another.
    """
    tail = normalised.split(f"create or replace function {fn}")[1]
    return tail.split("$$")[1]


# ── static: the shape of the control ────────────────────────────────────────


def test_the_mode_vocabulary_is_exactly_three_values(sql: str) -> None:
    n = _norm(sql)
    assert "check (mode in ('off', 'all', 'selected'))" in n
    # A fourth value would be a second policy system disagreeing with the first.
    for invented in ("'auto'", "'partial'", "'inherit'", "'default'"):
        assert f"mode in ({invented}" not in n


def test_the_product_override_is_additive_and_nullable(sql: str) -> None:
    n = _norm(sql)
    assert "add column if not exists tryon_policy_override text" in n
    # NULL is "inherit", so no NOT NULL and no default — either would turn every
    # existing row into an explicit decision nobody made.
    assert "tryon_policy_override text not null" not in n
    assert "tryon_policy_override text default" not in n
    assert "check (tryon_policy_override in ('on', 'off'))" in n


def test_the_default_mode_is_off(sql: str) -> None:
    """The safe default, in both places it has to hold: the column default, and
    the answer for a merchant with no row at all."""
    n = _norm(sql)
    assert "mode text not null default 'off'" in n
    assert "'off' )" in n or "), 'off' )" in n.replace("\n", " ")
    # The resolver's coalesce is the one that matters — a merchant nobody has
    # decided about must not read as decided.
    assert "coalesce( (select t.mode from public.merchant_tryon_policy t" in n
    assert "'off' )" in n


def test_the_migration_inserts_no_policy_rows(sql: str) -> None:
    """The whole safety claim of this migration. Not one merchant is switched on
    by deploying it, so exposure after it lands is a subset of exposure before."""
    n = _norm(sql)
    assert "insert into public.merchant_tryon_policy" in n, "the RPC inserts; that is expected"
    # ...but only from inside the audited RPC, never as a migration statement.
    body = n.split("create or replace function public.admin_set_merchant_tryon_mode")[0]
    assert "insert into public.merchant_tryon_policy" not in body


def test_the_migration_grants_no_rights(sql: str) -> None:
    """No rights value is ever assigned a literal. Every write takes the value an
    admin passed to an audited, single-target RPC, so there is no shape of this
    migration that licenses something as a side effect of running."""
    n = _norm(sql)
    assert "set image_rights_default = 'licensed'" not in n
    assert "set image_rights_status = 'licensed'" not in n
    assert "set image_rights_override = 'licensed'" not in n
    # The only rights writes in the file are the two 0067 RPCs it re-creates,
    # and both take their value from a parameter.
    writes = re.findall(r"set\s+image_rights_\w+\s*=\s*([^\s,]+)", n)
    assert writes, "the rights RPCs are re-created here, so there must be writes"
    assert all(w.startswith("p_rights") or w.startswith("case") for w in writes), writes
    # Propagation stays bounded to rows that inherit.
    assert "where merchant_id = p_merchant_id and image_rights_override is null" in n


def test_merchant_off_is_checked_before_any_product_override(sql: str) -> None:
    """The kill switch. If a product override were consulted first, `off` would
    be a suggestion rather than a rollback."""
    n = _norm(sql)
    policy = _body(n, "public.product_effective_tryon_policy")
    off_at = policy.index("when 'off' then 'off'")
    all_at = policy.index("when 'all' then")
    sel_at = policy.index("when 'selected' then")
    assert off_at < all_at < sel_at


def test_all_mode_honours_a_product_switched_off(sql: str) -> None:
    n = _norm(sql)
    assert "when 'all' then case when p.tryon_policy_override = 'off' then 'off' else 'on' end" in n


def test_selected_mode_defaults_to_off(sql: str) -> None:
    """Future imports must stay off under SELECTED. Expressed as "on only when
    the product says on", which is the same statement about products that do not
    exist yet."""
    n = _norm(sql)
    assert (
        "when 'selected' then case when p.tryon_policy_override = 'on' then 'on' else 'off' end"
        in n
    )


def test_an_unknown_mode_falls_through_to_off(sql: str) -> None:
    assert "else 'off' end" in _body(_norm(sql), "public.product_effective_tryon_policy")


def test_the_gate_requires_rights_and_coverage(sql: str) -> None:
    """Both, always. Neither is sufficient and coverage never substitutes."""
    gate = _body(_norm(sql), "public.product_tryon_ready")
    assert "public.product_effective_image_rights(p) = 'licensed'" in gate
    assert "public.product_effective_tryon_policy(p) = 'on'" in gate
    assert "p.try_on_status = 'ready'" in gate
    # And the image condition 0065 added is still there.
    assert "coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null" in gate


def test_rights_are_reported_before_coverage_in_the_refusal(sql: str) -> None:
    """An operator chasing "why is this off" should be told about rights first:
    it is the question that has to be answered before the others matter."""
    n = _norm(sql)
    blocked = n.split("'blocked_by', case")[1]
    assert blocked.index("rights_not_licensed") < blocked.index("merchant_tryon_off")
    assert blocked.index("merchant_tryon_off") < blocked.index("no_image")


def test_coverage_never_recomputes_try_on_status(sql: str) -> None:
    """`try_on_status` is the technical marker (rights + a usable image).
    Switching coverage off must not destroy the record of whether a product was
    ever renderable, or switching back on would not restore it."""
    n = _norm(sql)
    override_fn = n.split("create or replace function public.admin_set_product_tryon_override")[1]
    override_fn = override_fn.split("$$;")[0]
    assert "product_recompute_tryon_status" not in override_fn
    assert "set try_on_status" not in override_fn


def test_the_mode_switch_erases_no_product_override(sql: str) -> None:
    n = _norm(sql)
    mode_fn = n.split("create or replace function public.admin_set_merchant_tryon_mode")[1]
    mode_fn = mode_fn.split("$$;")[0]
    assert "set tryon_policy_override" not in mode_fn
    assert "update public.products" not in mode_fn.split("select count(*)")[0]


def test_bulk_writes_coverage_and_never_rights(sql: str) -> None:
    n = _norm(sql)
    bulk = n.split("create or replace function public.admin_bulk_set_product_tryon")[1]
    bulk = bulk.split("$$;")[0]
    assert "set tryon_policy_override = p_override" in bulk
    assert "image_rights_override =" not in bulk
    assert "image_rights_status =" not in bulk
    # It REPORTS what it could not make eligible rather than fixing the number.
    assert "'not_licensed'" in bulk
    assert "public.product_effective_image_rights(p) <> 'licensed'" in bulk


def test_bulk_is_bounded(sql: str) -> None:
    n = _norm(sql)
    assert "if v_requested > 500 then" in n


def test_every_mutation_asserts_an_active_admin_and_audits(sql: str) -> None:
    n = _norm(sql)
    for action in (
        "'merchant_set_tryon_mode'",
        "'product_set_tryon_override'",
        "'product_clear_tryon_override'",
        "'product_bulk_set_tryon_override'",
        "'product_bulk_clear_tryon_override'",
    ):
        assert action in n
    # One per RPC in this file: the three coverage mutations plus the two rights
    # functions it re-creates.
    assert n.count("perform admin_assert_active(p_admin_id)") >= 5


def test_the_rpcs_are_service_role_only(sql: str) -> None:
    n = _norm(sql)
    for fn in (
        "admin_set_merchant_tryon_mode(uuid,text,uuid,text,text)",
        "admin_set_product_tryon_override(uuid,text,uuid,text,text)",
        "admin_bulk_set_product_tryon(uuid,text,uuid[],text,text)",
        "admin_merchant_tryon_summary(uuid)",
    ):
        assert fn in n
    assert "revoke execute on function public.%s from public, anon, authenticated" in n
    assert "grant execute on function public.%s to service_role" in n


def test_the_resolver_is_readable_by_the_app(sql: str) -> None:
    """`product_tryon_ready` is granted to anon/authenticated so the app can
    filter. Its coverage dependency has to answer for them too, or the app would
    see `off` everywhere while the console saw the truth."""
    n = _norm(sql)
    assert "create or replace function public.merchant_tryon_mode(p_merchant_id uuid)" in n
    assert "security definer set search_path = public" in n
    assert (
        "grant execute on function public.merchant_tryon_mode(uuid) to anon, authenticated, "
        "service_role" in n
    )


def test_the_policy_table_is_default_deny(sql: str) -> None:
    n = _norm(sql)
    assert "alter table public.merchant_tryon_policy enable row level security" in n
    assert "create policy" not in n.split("merchant_tryon_policy")[1].split("alter table")[0]


def test_rights_evidence_is_evidence_and_not_a_gate(sql: str) -> None:
    n = _norm(sql)
    for col in ("rights_basis", "rights_reference", "rights_verified_at", "rights_verified_by"):
        assert f"add column if not exists {col}" in n
    # No gate reads it. Neither readiness function may mention it.
    for fn in ("public.product_tryon_ready", "public.product_tryon_readiness"):
        body = _body(n, fn)
        assert "rights_basis" not in body, fn
        assert "rights_reference" not in body, fn


def test_licensing_does_not_switch_coverage_on(sql: str) -> None:
    """The independence claim, in the one function that could most plausibly
    have been written to violate it."""
    n = _norm(sql)
    rights_fn = n.split("create or replace function public.admin_set_merchant_image_rights")[1]
    rights_fn = rights_fn.split("$$;")[0]
    assert "insert into public.merchant_tryon_policy" not in rights_fn
    assert "set tryon_policy_override" not in rights_fn
    # It records the mode it did NOT change, so the audit shows the separation.
    assert "'tryon_mode_unchanged'" in rights_fn


# ── static: the importer keeps its hands off ────────────────────────────────


def test_the_importer_never_writes_a_coverage_override() -> None:
    """Feed sync must not destroy a manual decision. It does not mention the
    column at all, which is a stronger guarantee than remembering to preserve
    it."""
    import app.services.catalog.sync as sync_mod

    source = _norm(Path(sync_mod.__file__).read_text(encoding="utf-8"))
    assert "tryon_policy_override" not in source
    assert "merchant_tryon_policy" not in source


def test_the_network_connector_never_writes_a_coverage_override() -> None:
    from app.services.catalog.networks import awin_adapter, discovery

    for mod in (awin_adapter, discovery):
        source = _norm(Path(mod.__file__).read_text(encoding="utf-8"))
        assert "tryon_policy_override" not in source, mod.__name__
        assert "merchant_tryon_policy" not in source, mod.__name__


def test_the_shopping_tryon_request_is_rechecked_at_execution_time() -> None:
    """The stale-client guard. A card cached while a product was on must not be
    able to spend credits after it was switched off."""
    import app.routers.v1.tryon as tryon_mod

    source = _norm(Path(tryon_mod.__file__).read_text(encoding="utf-8"))
    assert "public.product_tryon_ready(p) as tryon_ready" in source
    assert 'if not row["tryon_ready"]:' in source


def test_the_readiness_recheck_precedes_moderation_and_credit_reservation() -> None:
    """Ordering is the whole point: rejecting AFTER the moderation call would
    have sent the image to a provider, and after the reservation would have
    taken credits for a render that never runs."""
    import app.routers.v1.tryon as tryon_mod

    source = Path(tryon_mod.__file__).read_text(encoding="utf-8")
    body = source.split("async def _create_tryon")[1]
    resolve_at = body.index("_resolve_shopping_source(conn, body)")
    moderate_at = body.index("_moderate_one(")
    reserve_at = body.index("reserve_key(conn, idempotency_key")
    assert resolve_at < moderate_at, "origin must be checked before anything leaves us"
    assert resolve_at < reserve_at, "origin must be checked before credits are reserved"


def test_every_client_surface_reads_the_same_server_verdict() -> None:
    """All app surfaces agree because there is only one definition to agree
    with: `_PRODUCT_COLUMNS` derives try-on eligibility from the function, and
    every product endpoint selects those columns."""
    import app.routers.v1.discover as discover_mod

    source = Path(discover_mod.__file__).read_text(encoding="utf-8")
    assert "case when public.product_tryon_ready(p) then 'ready'" in source
    # The raw column is never served as the client's answer.
    assert source.count("_PRODUCT_COLUMNS") >= 5


# ── live: the precedence matrix ─────────────────────────────────────────────


def _dsn() -> str | None:
    from app.core.config import get_settings

    return get_settings().connection_string


@pytest.fixture(scope="module")
def live() -> Any:
    dsn = _dsn()
    if not dsn:
        pytest.skip("CONNECTION_STRING not set; skipping live coverage checks")

    import asyncpg

    async def _check() -> bool:
        conn = await asyncpg.connect(dsn, statement_cache_size=0)
        try:
            return bool(
                await conn.fetchval(
                    "select exists (select 1 from information_schema.columns "
                    " where table_name='products' and column_name='tryon_policy_override')"
                )
            )
        finally:
            await conn.close()

    if not asyncio.run(_check()):
        pytest.skip("migration 0068 not applied to this database")

    def run(body: Callable[[Any], Any]) -> Any:
        async def _wrapped() -> Any:
            conn = await asyncpg.connect(dsn, statement_cache_size=0)
            try:
                return await body(conn)
            finally:
                # Sweep every throwaway merchant this file could have created,
                # not only the one the test named: a fixture that raises during
                # SEED never reaches its own cleanup. The slug prefix is unique
                # to these tests, so this can only remove rows they created.
                try:
                    ids = [
                        r["id"]
                        for r in await conn.fetch(
                            "select id from public.merchants where slug like 'test-cover-%'"
                        )
                    ]
                    if ids:
                        await conn.execute(
                            "delete from public.products where merchant_id = any($1::uuid[])", ids
                        )
                        await conn.execute(
                            "delete from public.merchant_feed_config "
                            " where merchant_id = any($1::uuid[])",
                            ids,
                        )
                        # merchant_tryon_policy cascades from merchants.
                        await conn.execute(
                            "delete from public.merchants where id = any($1::uuid[])", ids
                        )
                finally:
                    await conn.close()

        return asyncio.run(_wrapped())

    return run


async def _admin(conn: Any) -> tuple[str, str]:
    row = await conn.fetchrow(
        "select user_id, email from public.admin_users where status = 'active' limit 1"
    )
    if row is None:
        pytest.skip("no active admin_users row in this database")
    return str(row["user_id"]), row["email"]


async def _seed(
    conn: Any, *, rights: str = "licensed", mode: str | None = None, count: int = 3
) -> tuple[str, list[str]]:
    """A throwaway merchant whose products are technically ready.

    `try_on_status` is seeded exactly as the importer would have written it —
    `ready` only where the rights in force cleared it — so a licensed fixture
    starts from a state the pipeline actually produces.

    `mode=None` deliberately leaves NO policy row, which is the production
    default and the thing several tests are about.
    """
    tag = uuid.uuid4().hex[:12]
    merchant_id = await conn.fetchval(
        "insert into public.merchants (slug, name, approved) values ($1, $2, true) returning id",
        f"test-cover-{tag}",
        f"Test Coverage {tag}",
    )
    await conn.execute(
        "insert into public.merchant_feed_config (merchant_id, feed_url, image_rights_default) "
        "values ($1, $2, $3)",
        merchant_id,
        f"https://feed.invalid/{tag}.xml",
        rights,
    )
    if mode is not None:
        await conn.execute(
            "insert into public.merchant_tryon_policy (merchant_id, mode) values ($1, $2)",
            merchant_id,
            mode,
        )
    ids: list[str] = []
    for i in range(count):
        pid = await conn.fetchval(
            """
            insert into public.products
              (merchant_id, external_id, title, price_minor, currency, image_urls,
               affiliate_ref, stock_status, try_on_status, image_rights_status,
               active, last_synced_at)
            values ($1, $2, $3, 1000, 'USD', array['https://cdn.invalid/a.jpg'],
                    $4, 'in_stock', $5, $6, true, now())
            returning id
            """,
            merchant_id,
            f"ext-{tag}-{i}",
            f"Product {i}",
            f"ext-{tag}-{i}",
            "ready" if rights == "licensed" else "unsupported",
            rights,
        )
        ids.append(str(pid))
    return str(merchant_id), ids


async def _cleanup(conn: Any, merchant_id: str) -> None:
    await conn.execute("delete from public.products where merchant_id = $1::uuid", merchant_id)
    await conn.execute(
        "delete from public.merchant_feed_config where merchant_id = $1::uuid", merchant_id
    )
    await conn.execute("delete from public.merchants where id = $1::uuid", merchant_id)


async def _state(conn: Any, product_id: str) -> tuple[str, str | None, str, bool]:
    row = await conn.fetchrow(
        """
        select public.merchant_tryon_mode(p.merchant_id) as mode,
               p.tryon_policy_override as override,
               public.product_effective_tryon_policy(p) as policy,
               public.product_tryon_ready(p) as ready
          from public.products p where p.id = $1::uuid
        """,
        product_id,
    )
    return row["mode"], row["override"], row["policy"], row["ready"]


def test_live_a_merchant_with_no_policy_row_is_off(live: Any) -> None:
    """Production state the moment 0068 lands: fully licensed, technically
    ready, and not exposed, because nobody has decided yet."""

    async def body(conn: Any) -> None:
        merchant_id, products = await _seed(conn, rights="licensed", mode=None)
        try:
            for pid in products:
                mode, override, policy, ready = await _state(conn, pid)
                assert mode == "off"
                assert override is None
                assert policy == "off"
                assert ready is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_merchant_off_beats_a_product_switched_on(live: Any) -> None:
    """The hard kill. Everything else about this product is perfect."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="selected")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "on",
                "test",
            )
            assert (await _state(conn, target))[3] is True

            await conn.fetchval(
                "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "off",
                "emergency",
            )
            mode, override, policy, ready = await _state(conn, target)
            assert mode == "off"
            assert override == "on", "the product decision is kept, not erased"
            assert policy == "off"
            assert ready is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_restoring_the_mode_restores_the_product_decision(live: Any) -> None:
    """Which is what makes `off` a rollback rather than a reset."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="selected")
        target = products[0]
        try:
            for mode, expected in (("selected", True), ("off", False), ("selected", True)):
                if mode == "selected" and expected:
                    await conn.fetchval(
                        "select public.admin_set_product_tryon_override("
                        "$1::uuid,$2,$3::uuid,$4,$5)",
                        admin_id,
                        admin_email,
                        target,
                        "on",
                        "test",
                    )
                await conn.fetchval(
                    "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                    admin_id,
                    admin_email,
                    merchant_id,
                    mode,
                    "test",
                )
                assert (await _state(conn, target))[3] is expected
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_all_mode_exposes_everything_eligible(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode=None)
        try:
            await conn.fetchval(
                "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "all",
                "test",
            )
            for pid in products:
                _, override, policy, ready = await _state(conn, pid)
                assert override is None, "inheritance, not a rewrite of every row"
                assert policy == "on"
                assert ready is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_a_single_product_can_be_excepted_from_all(live: Any) -> None:
    """Example B: whole store on, one product off."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="all")
        held, *rest = products
        try:
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                held,
                "off",
                "test",
            )
            assert (await _state(conn, held))[3] is False
            for pid in rest:
                assert (await _state(conn, pid))[3] is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_selected_mode_enables_only_what_was_picked(live: Any) -> None:
    """Example C."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="selected")
        picked, *others = products
        try:
            for pid in products:
                assert (await _state(conn, pid))[3] is False, "selected starts closed"

            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                picked,
                "on",
                "test",
            )
            assert (await _state(conn, picked))[3] is True
            for pid in others:
                assert (await _state(conn, pid))[3] is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_product_permission_works_under_an_unknown_merchant(live: Any) -> None:
    """Example D: permission for one item, no claim about the merchant."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="unknown", mode="selected")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5,$6,$7)",
                admin_id,
                admin_email,
                target,
                "licensed",
                "test",
                "product_permission",
                "email 2026-08-12",
            )
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "on",
                "test",
            )
            assert (await _state(conn, target))[3] is True

            row = await conn.fetchrow(
                "select image_rights_default from public.merchant_feed_config "
                " where merchant_id = $1::uuid",
                merchant_id,
            )
            assert row["image_rights_default"] == "unknown", "the merchant is untouched"
            for pid in products[1:]:
                assert (await _state(conn, pid))[3] is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


@pytest.mark.parametrize("rights", ["unknown", "restricted"])
def test_live_coverage_never_outranks_rights(live: Any, rights: str) -> None:
    """The one thing that must never resolve. Everything operational says yes."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights=rights, mode="all")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "on",
                "test",
            )
            _, override, policy, ready = await _state(conn, target)
            assert override == "on"
            assert policy == "on", "coverage really is on"
            assert ready is False, "and it still is not eligible"

            readiness = await conn.fetchval(
                "select public.product_tryon_readiness(p) from public.products p "
                " where p.id = $1::uuid",
                target,
            )
            import json

            r = json.loads(readiness) if isinstance(readiness, str) else dict(readiness)
            assert r["policy_ok"] is True
            assert r["rights_ok"] is False
            assert r["blocked_by"] == (
                "rights_restricted" if rights == "restricted" else "rights_not_licensed"
            )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_clearing_an_override_returns_to_the_merchant_mode(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="all")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "off",
                "test",
            )
            assert (await _state(conn, target))[3] is False

            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                None,
                "test",
            )
            _, override, policy, ready = await _state(conn, target)
            assert override is None
            assert policy == "on"
            assert ready is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_a_newly_imported_product_inherits_the_mode(live: Any) -> None:
    """Feed behaviour, expressed the only way it can be tested honestly: insert a
    row the way the importer does and read what it resolves to. Under ALL it is
    live immediately; under SELECTED it is not."""

    async def body(conn: Any) -> None:
        for mode, expected in (("all", True), ("selected", False), ("off", False)):
            merchant_id, _ = await _seed(conn, rights="licensed", mode=mode, count=0)
            try:
                tag = uuid.uuid4().hex[:8]
                pid = await conn.fetchval(
                    """
                    insert into public.products
                      (merchant_id, external_id, title, price_minor, currency, image_urls,
                       affiliate_ref, stock_status, try_on_status, image_rights_status,
                       active, last_synced_at)
                    values ($1, $2, 'Imported later', 1000, 'USD',
                            array['https://cdn.invalid/new.jpg'], $2, 'in_stock',
                            'ready', 'licensed', true, now())
                    returning id
                    """,
                    merchant_id,
                    f"new-{tag}",
                )
                _, override, _, ready = await _state(conn, str(pid))
                assert override is None, "no row was rewritten to make this work"
                assert ready is expected, f"mode {mode}"
            finally:
                await _cleanup(conn, merchant_id)

    live(body)


def test_live_bulk_enables_and_reports_what_it_could_not(live: Any) -> None:
    async def body(conn: Any) -> None:
        import json

        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="selected")
        try:
            # One of the three has its rights explicitly withdrawn.
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[2],
                "restricted",
                "test",
            )

            raw = await conn.fetchval(
                "select public.admin_bulk_set_product_tryon($1::uuid,$2,$3::uuid[],$4,$5)",
                admin_id,
                admin_email,
                products,
                "on",
                "test",
            )
            result = json.loads(raw) if isinstance(raw, str) else dict(raw)
            assert result["requested"] == 3
            assert result["updated"] == 3
            assert result["try_on_ready_after"] == 2
            assert result["not_licensed"] == 1
            assert len(result["blocked"]) == 1
            assert result["blocked"][0]["id"] == products[2]

            # The restricted one was switched ON and is still not eligible —
            # bulk enabling is not bulk licensing.
            _, override, policy, ready = await _state(conn, products[2])
            assert override == "on"
            assert policy == "on"
            assert ready is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_bulk_disable_and_clear(live: Any) -> None:
    async def body(conn: Any) -> None:
        import json

        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="all")
        try:
            raw = await conn.fetchval(
                "select public.admin_bulk_set_product_tryon($1::uuid,$2,$3::uuid[],$4,$5)",
                admin_id,
                admin_email,
                products,
                "off",
                "test",
            )
            assert (json.loads(raw) if isinstance(raw, str) else dict(raw))["updated"] == 3
            for pid in products:
                assert (await _state(conn, pid))[3] is False

            await conn.fetchval(
                "select public.admin_bulk_set_product_tryon($1::uuid,$2,$3::uuid[],$4,$5)",
                admin_id,
                admin_email,
                products,
                None,
                "test",
            )
            for pid in products:
                _, override, _, ready = await _state(conn, pid)
                assert override is None
                assert ready is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_an_invalid_mode_or_override_is_refused(live: Any) -> None:
    async def body(conn: Any) -> None:
        import asyncpg

        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="off")
        try:
            with pytest.raises(asyncpg.PostgresError, match="VALIDATION_ERROR"):
                await conn.fetchval(
                    "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                    admin_id,
                    admin_email,
                    merchant_id,
                    "everything",
                    "test",
                )
            with pytest.raises(asyncpg.PostgresError, match="VALIDATION_ERROR"):
                await conn.fetchval(
                    "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                    admin_id,
                    admin_email,
                    products[0],
                    "yes",
                    "test",
                )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_a_non_admin_cannot_change_coverage(live: Any) -> None:
    async def body(conn: Any) -> None:
        import asyncpg

        merchant_id, _ = await _seed(conn, rights="licensed", mode="off")
        try:
            with pytest.raises(asyncpg.PostgresError):
                await conn.fetchval(
                    "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                    str(uuid.uuid4()),
                    "nobody@example.test",
                    merchant_id,
                    "all",
                    "test",
                )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_the_summary_counts_what_the_console_renders(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="selected", count=4)
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[0],
                "restricted",
                "test",
            )
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[1],
                "on",
                "test",
            )
            await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[2],
                "off",
                "test",
            )

            row = await conn.fetchrow(
                "select * from public.admin_merchant_tryon_summary($1::uuid)", merchant_id
            )
            assert row["tryon_mode"] == "selected"
            assert row["total_products"] == 4
            assert row["rights_licensed"] == 3
            assert row["blocked_rights"] == 1
            assert row["explicitly_enabled"] == 1
            assert row["explicitly_disabled"] == 1
            assert row["tryon_ready"] == 1, "only the one that was picked"
            # The number the ALL dialog quotes: everything licensed and ready
            # that is not switched off by hand.
            assert row["eligible_if_all"] == 2
            assert row["eligible_if_selected"] == 1
            assert row["awaiting_selection"] == 1
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_audit_records_the_coverage_change(live: Any) -> None:
    async def body(conn: Any) -> None:
        import json

        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="licensed", mode="off")
        try:
            audit_id = await conn.fetchval(
                "select public.admin_set_merchant_tryon_mode($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "all",
                "unit test",
            )
            row = await conn.fetchrow(
                "select action, target_type, target_id, before_data, after_data, metadata "
                "  from public.admin_audit_log where id = $1",
                audit_id,
            )

            def j(value: object) -> dict:
                return json.loads(value) if isinstance(value, str) else dict(value or {})

            assert row["action"] == "merchant_set_tryon_mode"
            assert row["target_type"] == "merchant"
            assert row["target_id"] == merchant_id
            assert j(row["before_data"])["tryon_mode"] == "off"
            assert j(row["after_data"])["tryon_mode"] == "all"
            meta = j(row["metadata"])
            assert meta["previous_mode"] == "off"
            assert meta["new_mode"] == "all"
            assert meta["products_try_on_ready_after"] == 3

            set_id = await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[0],
                "off",
                "unit test",
            )
            clear_id = await conn.fetchval(
                "select public.admin_set_product_tryon_override($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[0],
                None,
                "unit test",
            )
            rows = await conn.fetch(
                "select id, action from public.admin_audit_log where id = any($1::bigint[])",
                [set_id, clear_id],
            )
            by_id = {r["id"]: r["action"] for r in rows}
            assert by_id[set_id] == "product_set_tryon_override"
            assert by_id[clear_id] == "product_clear_tryon_override"
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_rights_evidence_is_recorded_and_cleared(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="unknown", mode="off")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5,$6,$7)",
                admin_id,
                admin_email,
                target,
                "licensed",
                "test",
                "product_permission",
                "support ticket 4417",
            )
            row = await conn.fetchrow(
                "select rights_basis, rights_reference, rights_verified_at, rights_verified_by "
                "  from public.products where id = $1::uuid",
                target,
            )
            assert row["rights_basis"] == "product_permission"
            assert row["rights_reference"] == "support ticket 4417"
            assert row["rights_verified_at"] is not None
            assert row["rights_verified_by"] == admin_email

            # Withdrawing clears it: a reference describing a permission we no
            # longer claim is worse than no reference.
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "restricted",
                "test",
            )
            row = await conn.fetchrow(
                "select rights_basis, rights_reference, rights_verified_at "
                "  from public.products where id = $1::uuid",
                target,
            )
            assert row["rights_basis"] is None
            assert row["rights_reference"] is None
            assert row["rights_verified_at"] is None
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_licensing_a_merchant_does_not_switch_coverage_on(live: Any) -> None:
    """The independence claim, end to end."""

    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, rights="unknown", mode=None)
        try:
            await conn.fetchval(
                "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5,$6,$7)",
                admin_id,
                admin_email,
                merchant_id,
                "licensed",
                "test",
                "merchant_permission",
                "MSA 2026-08",
            )
            for pid in products:
                mode, _, policy, ready = await _state(conn, pid)
                assert mode == "off", "licensing created no policy row"
                assert policy == "off"
                assert ready is False
            # And the rights really did land: only coverage is holding it back.
            row = await conn.fetchrow(
                "select public.product_effective_image_rights(p) as rights, p.try_on_status "
                "  from public.products p where p.id = $1::uuid",
                products[0],
            )
            assert row["rights"] == "licensed"
            assert row["try_on_status"] == "ready"
        finally:
            await _cleanup(conn, merchant_id)

    live(body)
