"""AI image-rights control — the operational gate for shopping try-on (0067).

Two layers, deliberately:

  * **Static** assertions on the migration, which always run. They pin the
    properties that must never regress even in an environment with no database:
    that `unknown` is never silently promoted, that the importer is untouched,
    and that there is no bulk-licensing path.

  * **Live** assertions against a real Postgres, skipped when no DSN is
    configured or when 0067 has not been applied there. Inheritance,
    propagation, override precedence and rollback are behaviours of SQL, and a
    fake connection asserting on query text would prove only that the text was
    written — not that it does what it says.

Nothing here is allowed to touch an existing row: every live test creates its
own merchant and products under a unique slug and removes them afterwards.
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
    / "0067_admin_image_rights_control.sql"
)


@pytest.fixture(scope="module")
def sql() -> str:
    assert _MIGRATION.exists(), f"missing migration: {_MIGRATION}"
    return _MIGRATION.read_text(encoding="utf-8")


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).lower()


# ── static: the shape of the control ────────────────────────────────────────


def test_the_override_column_is_additive_and_nullable(sql: str) -> None:
    n = _norm(sql)
    assert "add column if not exists image_rights_override text" in n
    # NULL is "inherit", so the column must not be NOT NULL and must not carry a
    # default that would silently make every existing row an explicit decision.
    assert "image_rights_override text not null" not in n
    assert "image_rights_override text default" not in n


def test_the_enum_is_the_existing_one(sql: str) -> None:
    """0053/0057 already define the vocabulary. A fourth value would mean two
    rights systems disagreeing about the same product."""
    n = _norm(sql)
    assert "check (image_rights_override in ('unknown', 'licensed', 'restricted'))" in n
    for invented in ("'pending_review'", "'approved'", "'granted'", "'allowed'"):
        assert invented not in n


def test_effective_rights_is_override_then_status(sql: str) -> None:
    n = _norm(sql)
    assert "coalesce(p.image_rights_override, p.image_rights_status)" in n


def test_the_ai_gate_still_demands_licensed(sql: str) -> None:
    """0065's rule, unchanged in strength — only re-pointed at effective rights."""
    n = _norm(sql)
    assert "public.product_effective_image_rights(p) = 'licensed'" in n
    assert "p.try_on_status = 'ready'" in n


def test_display_and_ai_gates_stay_separate(sql: str) -> None:
    """The thing 0065 exists to prevent. Display suppresses only a positive
    refusal; AI demands a positive grant."""
    n = _norm(sql)
    assert "public.product_effective_image_rights(p) <> 'restricted'" in n  # display
    assert "public.product_effective_image_rights(p) = 'licensed'" in n  # AI


def test_unknown_is_never_promoted_to_licensed(sql: str) -> None:
    n = _norm(sql)
    # No rule anywhere that reads "if unknown then licensed", in any spelling.
    assert "then 'licensed'" not in n.replace("= 'licensed'\n", "")
    assert "coalesce(p.image_rights_override, 'licensed')" not in n
    assert "coalesce(c.image_rights_default, 'licensed')" not in n
    # The only default for a missing merchant config is unknown.
    assert "coalesce(c.image_rights_default, 'unknown')" in n


def test_propagation_touches_only_inheriting_rows(sql: str) -> None:
    """A merchant-wide change is not permission to discard a product decision."""
    n = _norm(sql)
    assert "where merchant_id = p_merchant_id and image_rights_override is null" in n
    # And never the other way round.
    assert "set image_rights_override" not in n.replace(
        "set image_rights_override = p_rights, updated_at = now() where id = p_product_id", ""
    )


def test_there_is_no_bulk_or_network_wide_licensing(sql: str) -> None:
    """Licensing is per merchant, by id, every time."""
    n = _norm(sql)
    for banned in (
        "update public.merchant_feed_config set image_rights_default = 'licensed'",
        "where network =",
        "for all merchants",
    ):
        assert banned not in n
    # Every rights mutation is scoped to a single id.
    assert n.count("p_merchant_id uuid") >= 1
    assert "where merchant_id = p_merchant_id" in n


def test_readiness_is_reported_not_reimplemented(sql: str) -> None:
    n = _norm(sql)
    assert "create or replace function public.product_tryon_readiness" in n
    assert "'ready', public.product_tryon_ready(p)" in n
    assert "'blocked_by'" in n


def test_the_rpcs_are_service_role_only(sql: str) -> None:
    n = _norm(sql)
    for fn in (
        "admin_set_merchant_image_rights(uuid,text,uuid,text,text)",
        "admin_set_product_image_rights(uuid,text,uuid,text,text)",
    ):
        assert fn in n
    assert "revoke execute on function public.%s from public, anon, authenticated" in _norm(sql)
    assert "grant execute on function public.%s to service_role" in _norm(sql)


def test_both_rpcs_assert_an_active_admin_and_audit(sql: str) -> None:
    n = _norm(sql)
    assert n.count("perform admin_assert_active(p_admin_id)") >= 3
    assert "return admin_log_audit(" in n
    assert "'merchant_set_image_rights'" in n
    assert "'product_set_image_rights_override'" in n
    # Clearing an override is its own decision and its own audit action.
    assert "'product_clear_image_rights_override'" in n


def test_the_tryon_image_guard_is_not_weakened(sql: str) -> None:
    n = _norm(sql)
    assert "select public.product_effective_image_rights(p) into v_rights" in n
    assert "when v_rights = 'licensed' then 'ready'" in n
    assert "else 'unsupported'" in n


def test_a_pending_feed_claim_is_never_promoted_by_a_rights_change(sql: str) -> None:
    """`pending` means the FEED said the garment is not compatible yet. Rights
    moving does not answer that question."""
    n = _norm(sql)
    assert "when p.try_on_status = 'pending' then 'pending'" in n


# ── static: the importer stays conservative ─────────────────────────────────


def test_the_awin_adapter_still_defaults_to_unsupported() -> None:
    from app.services.catalog.networks import awin_adapter

    source = _norm(Path(awin_adapter.__file__).read_text(encoding="utf-8"))
    assert '"try_on_status": "unsupported"' in source
    for banned in ('"try_on_status": "ready"', '"image_rights_status"', '"licensed"'):
        assert banned not in source, "the importer must never assert rights"


def test_resolve_rights_still_refuses_anything_unconfigured() -> None:
    from app.services.catalog.normalize import resolve_rights

    assert resolve_rights("licensed") == "licensed"
    assert resolve_rights("unknown") == "unknown"
    assert resolve_rights("restricted") == "restricted"
    # Anything a feed makes up lands as unknown, not as a grant.
    assert resolve_rights("yes-we-promise") == "unknown"
    assert resolve_rights("") == "unknown"


def test_the_importer_defers_to_an_explicit_product_override() -> None:
    """The gap a console control alone would not have closed: before 0067 the
    next sync overwrote whatever an admin had decided."""
    source = _norm(
        Path(__import__("app.services.catalog.sync", fromlist=["x"]).__file__).read_text(
            encoding="utf-8"
        )
    )
    assert (
        'override = existing["image_rights_override"] if existing is not none else none' in source
    )
    assert "rights = override or resolve_rights(rights_default)" in source
    # And the UPDATE leaves an overridden row's status alone.
    assert "when image_rights_override is null then $24 else image_rights_status end" in source


def test_a_shopping_tryon_is_refused_when_the_product_is_not_ready() -> None:
    """Backend authority. A card cached before a merchant was de-licensed must
    not still be able to spend credits rendering it."""
    import app.routers.v1.tryon as tryon_mod

    source = _norm(Path(tryon_mod.__file__).read_text(encoding="utf-8"))
    assert "public.product_tryon_ready(p) as tryon_ready" in source
    assert 'if not row["tryon_ready"]:' in source


# ── live: the behaviour ─────────────────────────────────────────────────────


def _dsn() -> str | None:
    from app.core.config import get_settings

    return get_settings().connection_string


@pytest.fixture(scope="module")
def live() -> Any:
    """A connection factory, or a skip.

    Skips on two conditions rather than one: no DSN at all, and a DSN whose
    database has not had 0067 applied. The second matters because a missing
    column would otherwise surface as a wall of confusing failures in an
    environment that is simply behind.
    """
    dsn = _dsn()
    if not dsn:
        pytest.skip("CONNECTION_STRING not set; skipping live image-rights checks")

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

    # 0068, not 0067. Since coverage exists, readiness needs BOTH gates, so these
    # rights fixtures switch coverage on in order to keep testing rights in
    # isolation — and a database that predates coverage cannot run them as
    # written. Skipping beats a wall of failures in an environment that is simply
    # behind.
    if not asyncio.run(_check()):
        pytest.skip("migration 0068 not applied to this database")

    def run(body: Callable[[Any], Any]) -> Any:
        async def _wrapped() -> Any:
            conn = await asyncpg.connect(dsn, statement_cache_size=0)
            try:
                return await body(conn)
            finally:
                # Sweep every throwaway merchant, not only the one this test
                # named. A test whose SEED raises never reaches its own
                # try/finally, and the first draft of this file leaked
                # twenty-three merchants into the dev database exactly that way.
                # The slug prefix is unique to these fixtures, so this can only
                # ever remove rows a test created.
                try:
                    ids = [
                        r["id"]
                        for r in await conn.fetch(
                            "select id from public.merchants where slug like 'test-rights-%'"
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
                        await conn.execute(
                            "delete from public.merchants where id = any($1::uuid[])", ids
                        )
                finally:
                    await conn.close()

        return asyncio.run(_wrapped())

    return run


async def _seed(
    conn: Any, *, merchant_default: str, tryon_mode: str = "all"
) -> tuple[str, list[str]]:
    """A throwaway merchant with three products, all inheriting.

    Its own slug and its own rows, so nothing here can read or disturb a real
    merchant — including the one this feature was built for.

    Coverage defaults to `all` (0068). Every test in THIS file is about rights,
    and leaving coverage at its production-safe `off` would make all of them pass
    for the wrong reason: nothing would be ready, whatever the rights said. The
    coverage gate itself is exercised in test_tryon_coverage_control.py.
    """
    tag = uuid.uuid4().hex[:12]
    merchant_id = await conn.fetchval(
        "insert into public.merchants (slug, name, approved) values ($1, $2, true) returning id",
        f"test-rights-{tag}",
        f"Test Rights {tag}",
    )
    await conn.execute(
        "insert into public.merchant_feed_config (merchant_id, feed_url, image_rights_default) "
        "values ($1, $2, $3)",
        merchant_id,
        f"https://feed.invalid/{tag}.xml",
        merchant_default,
    )
    await conn.execute(
        "insert into public.merchant_tryon_policy (merchant_id, mode) values ($1, $2)",
        merchant_id,
        tryon_mode,
    )
    ids: list[str] = []
    for i in range(3):
        pid = await conn.fetchval(
            """
            insert into public.products
              (merchant_id, external_id, title, price_minor, currency, image_urls,
               affiliate_ref, stock_status, try_on_status, image_rights_status,
               active, last_synced_at)
            values ($1, $2, $3, 1000, 'USD', array['https://cdn.invalid/a.jpg'],
                    $5, 'in_stock', $6, $4, true, now())
            returning id
            """,
            merchant_id,
            f"ext-{tag}-{i}",
            f"Product {i}",
            merchant_default,
            f"ext-{tag}-{i}",
            # What the importer would have written: `resolve_tryon` marks a
            # product ready when the rights in force cleared it AND there is a
            # usable image. Seeding every row `unsupported` regardless would
            # make the licensed fixture start from a state the pipeline never
            # produces, and the rollback test would prove nothing.
            "ready" if merchant_default == "licensed" else "unsupported",
        )
        ids.append(str(pid))
    return str(merchant_id), ids


async def _cleanup(conn: Any, merchant_id: str) -> None:
    await conn.execute("delete from public.products where merchant_id = $1::uuid", merchant_id)
    await conn.execute(
        "delete from public.merchant_feed_config where merchant_id = $1::uuid", merchant_id
    )
    await conn.execute("delete from public.merchants where id = $1::uuid", merchant_id)


async def _admin(conn: Any) -> tuple[str, str]:
    """An active admin to attribute the audited mutations to."""
    row = await conn.fetchrow(
        "select user_id, email from public.admin_users where status = 'active' limit 1"
    )
    if row is None:
        pytest.skip("no active admin_users row in this database")
    return str(row["user_id"]), row["email"]


async def _rights(conn: Any, product_id: str) -> tuple[str, str | None, str, bool]:
    row = await conn.fetchrow(
        """
        select p.image_rights_status, p.image_rights_override,
               public.product_effective_image_rights(p) as effective,
               public.product_tryon_ready(p) as ready
          from public.products p where p.id = $1::uuid
        """,
        product_id,
    )
    return (
        row["image_rights_status"],
        row["image_rights_override"],
        row["effective"],
        row["ready"],
    )


def test_live_merchant_licensing_makes_inheriting_products_eligible(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        try:
            for pid in products:
                _, _, effective, ready = await _rights(conn, pid)
                assert effective == "unknown"
                assert ready is False

            await conn.fetchval(
                "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "licensed",
                "test",
            )

            for pid in products:
                status, override, effective, ready = await _rights(conn, pid)
                assert status == "licensed", "inheriting rows follow the new default"
                assert override is None
                assert effective == "licensed"
                assert ready is True, "readiness is recomputed, not left stale"
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_an_explicit_override_survives_a_merchant_change(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        held, *inheriting = products
        try:
            # One product is explicitly restricted by a human.
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                held,
                "restricted",
                "test",
            )
            # Then the whole merchant is licensed.
            await conn.fetchval(
                "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "licensed",
                "test",
            )

            _, override, effective, ready = await _rights(conn, held)
            assert override == "restricted", "a merchant change never discards a decision"
            assert effective == "restricted"
            assert ready is False

            for pid in inheriting:
                _, _, effective, ready = await _rights(conn, pid)
                assert effective == "licensed"
                assert ready is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_an_override_can_license_a_product_under_an_unknown_merchant(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "licensed",
                "test",
            )
            status, override, effective, ready = await _rights(conn, target)
            assert status == "unknown", "the merchant default is untouched"
            assert override == "licensed"
            assert effective == "licensed"
            assert ready is True
            # And its neighbours are unaffected.
            _, _, other_effective, other_ready = await _rights(conn, products[1])
            assert other_effective == "unknown"
            assert other_ready is False
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_clearing_an_override_returns_to_inheritance(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="licensed")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "restricted",
                "test",
            )
            assert (await _rights(conn, target))[2] == "restricted"

            # NULL means inherit.
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                None,
                "test",
            )
            status, override, effective, ready = await _rights(conn, target)
            assert override is None
            assert effective == status == "licensed"
            assert ready is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


@pytest.mark.parametrize("rollback_to", ["restricted", "unknown"])
def test_live_rollback_removes_eligibility_without_touching_each_product(
    live: Any, rollback_to: str
) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="licensed")
        try:
            # Everything starts eligible.
            for pid in products:
                assert (await _rights(conn, pid))[3] is True

            await conn.fetchval(
                "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                rollback_to,
                "test",
            )

            for pid in products:
                _, _, effective, ready = await _rights(conn, pid)
                assert effective == rollback_to
                assert ready is False, "one switch, no per-product edits"
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_an_invalid_rights_value_is_refused(live: Any) -> None:
    async def body(conn: Any) -> None:
        import asyncpg

        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        try:
            with pytest.raises(asyncpg.PostgresError, match="VALIDATION_ERROR"):
                await conn.fetchval(
                    "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                    admin_id,
                    admin_email,
                    merchant_id,
                    "totally-licensed-trust-me",
                    "test",
                )
            with pytest.raises(asyncpg.PostgresError, match="VALIDATION_ERROR"):
                await conn.fetchval(
                    "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                    admin_id,
                    admin_email,
                    products[0],
                    "approved",
                    "test",
                )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_a_non_admin_cannot_change_rights(live: Any) -> None:
    async def body(conn: Any) -> None:
        import asyncpg

        merchant_id, _ = await _seed(conn, merchant_default="unknown")
        try:
            # A uuid that is not an active admin. The RPC asserts this itself,
            # so the console's permission check is defence in depth rather than
            # the only gate.
            with pytest.raises(asyncpg.PostgresError):
                await conn.fetchval(
                    "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                    str(uuid.uuid4()),
                    "nobody@example.test",
                    merchant_id,
                    "licensed",
                    "test",
                )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_the_tryon_image_rpc_still_refuses_unlicensed_imagery(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        target = products[0]
        try:
            await conn.fetchval(
                "select public.admin_set_product_tryon_image($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "https://cdn.invalid/chosen.jpg",
                "test",
            )
            row = await conn.fetchrow(
                "select try_on_status, tryon_image_url from public.products where id = $1::uuid",
                target,
            )
            assert row["tryon_image_url"] == "https://cdn.invalid/chosen.jpg"
            assert row["try_on_status"] == "unsupported", (
                "choosing an image does not create a licence"
            )
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_audit_records_before_and_after(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        target = products[0]
        try:
            merchant_audit = await conn.fetchval(
                "select public.admin_set_merchant_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                merchant_id,
                "licensed",
                "unit test",
            )
            row = await conn.fetchrow(
                "select action, target_type, target_id, before_data, after_data, metadata "
                "  from public.admin_audit_log where id = $1",
                merchant_audit,
            )
            assert row["action"] == "merchant_set_image_rights"
            assert row["target_type"] == "merchant"
            assert row["target_id"] == merchant_id
            import json

            # asyncpg hands jsonb back as a string unless a codec is registered.
            def j(value: object) -> dict:
                return json.loads(value) if isinstance(value, str) else dict(value or {})

            before = j(row["before_data"])
            after = j(row["after_data"])
            meta = j(row["metadata"])
            assert before["image_rights_default"] == "unknown"
            assert after["image_rights_default"] == "licensed"
            assert meta["scope"] == "merchant_default"
            assert meta["products_repointed"] == 3

            # Setting an override, then clearing it, are two DIFFERENT actions —
            # an audit reader should not have to infer which from a null.
            set_id = await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                "restricted",
                "unit test",
            )
            clear_id = await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                target,
                None,
                "unit test",
            )
            actions = await conn.fetch(
                "select id, action, metadata from public.admin_audit_log "
                " where id = any($1::bigint[])",
                [set_id, clear_id],
            )
            by_id = {r["id"]: r for r in actions}
            assert by_id[set_id]["action"] == "product_set_image_rights_override"
            assert by_id[clear_id]["action"] == "product_clear_image_rights_override"
        finally:
            await _cleanup(conn, merchant_id)

    live(body)


def test_live_the_preview_counts_what_a_change_would_touch(live: Any) -> None:
    async def body(conn: Any) -> None:
        admin_id, admin_email = await _admin(conn)
        merchant_id, products = await _seed(conn, merchant_default="unknown")
        try:
            await conn.fetchval(
                "select public.admin_set_product_image_rights($1::uuid,$2,$3::uuid,$4,$5)",
                admin_id,
                admin_email,
                products[0],
                "restricted",
                "test",
            )
            row = await conn.fetchrow(
                "select * from public.admin_merchant_rights_preview($1::uuid)", merchant_id
            )
            assert row["inheriting_products"] == 2
            assert row["overridden_products"] == 1
            # Both inheriting rows have an image and are not pending, so both are
            # one rights change away from eligible.
            assert row["would_become_ready"] == 2
            assert row["currently_ready"] == 0
            assert row["has_feed_config"] is True
        finally:
            await _cleanup(conn, merchant_id)

    live(body)
