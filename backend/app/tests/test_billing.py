"""Subscriptions / entitlements (CLAUDE.md §18) — webhook→tier+credit mapping,
tier-based premium gate, grant idempotency key, live SQL schema."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.billing import EntitlementResponse
from app.services.billing import (
    apply_webhook_event,
    get_entitlement,
    grant_ref,
    is_premium,
)

WEBHOOK_SECRET = "whsec-test-123"
client = TestClient(app)


@pytest.fixture(autouse=True)
def _webhook_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH", WEBHOOK_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


class _FakeConn:
    """Routes fetchrow by table; records execute() + the app_grant_credits calls."""

    def __init__(self, *, plan_row=None, sub_row=None, ent_row=None, fk_error=False):
        self.plan_row = plan_row
        self.sub_row = sub_row
        self.ent_row = ent_row
        self.fk_error = fk_error
        self.execs: list[tuple[str, tuple]] = []
        self.grants: list[tuple] = []

    async def fetchrow(self, sql, *args):
        if "public.plans" in sql:
            return self.plan_row
        if "public.user_subscriptions" in sql:
            return self.sub_row
        if "public.entitlements" in sql:
            return self.ent_row
        return None

    async def execute(self, sql, *args):
        if self.fk_error:
            import asyncpg

            raise asyncpg.ForeignKeyViolationError("no such user")
        self.execs.append((sql, args))

    async def fetchval(self, sql, *args):
        if "app_grant_credits" in sql:
            self.grants.append(args)
            return True
        return None

    def execs_matching(self, needle: str) -> list[tuple]:
        return [a for (s, a) in self.execs if needle in s]


class _DedupConn(_FakeConn):
    """Faithfully simulates `app_grant_credits`: a REPEATED idempotency ref grants
    nothing (returns False, no second ledger row) — so a redelivered webhook can
    never double-credit. The base fake grants unconditionally; this one dedupes."""

    def __init__(self, **kw):
        super().__init__(**kw)
        self._seen_refs: set = set()

    async def fetchval(self, sql, *args):
        if "app_grant_credits" in sql:
            ref = args[3]
            if ref in self._seen_refs:
                return False
            self._seen_refs.add(ref)
            self.grants.append(args)
            return True
        return None


def _evt(**kw):
    base = {
        "type": "INITIAL_PURCHASE",
        "app_user_id": str(uuid.uuid4()),
        "store": "PLAY_STORE",
        "expiration_at_ms": int((datetime.now(UTC) + timedelta(days=30)).timestamp() * 1000),
        "purchased_at_ms": int(datetime.now(UTC).timestamp() * 1000),
    }
    base.update(kw)
    return base


def _plan(tier, kind, credits, hd):
    return {
        "tier": tier, "kind": kind, "monthly_credits": credits,
        "hd_allowed": hd, "priority": hd,
    }


# ── webhook: subscription tier + credit grant ────────────────────────────────


def test_pro_purchase_sets_tier_and_grants_75() -> None:
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    ok = asyncio.run(apply_webhook_event(conn, _evt(product_id="pro_monthly")))
    assert ok is True
    assert conn.execs_matching("public.user_subscriptions")  # tier upserted
    g = conn.grants[0]  # (user, amount, reason, ref, set_plan_balance, target)
    assert g[1] == 75 and g[4] is True and g[5] == "plan"


def test_pro_max_purchase_grants_150() -> None:
    conn = _FakeConn(plan_row=_plan("pro_max", "subscription", 150, True))
    asyncio.run(apply_webhook_event(conn, _evt(product_id="pro_max_monthly")))
    assert conn.grants[0][1] == 150


def test_renewal_grant_ref_is_per_period() -> None:
    # Same purchased_at → same ref (the DB dedupes); a new period → new ref.
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    uid = str(uuid.uuid4())

    def evt(ms):
        return _evt(app_user_id=uid, product_id="pro_monthly", purchased_at_ms=ms)

    asyncio.run(apply_webhook_event(conn, evt(1_000_000)))
    asyncio.run(apply_webhook_event(conn, evt(1_000_000)))
    asyncio.run(apply_webhook_event(conn, evt(9_999_000)))
    refs = [g[3] for g in conn.grants]
    assert refs[0] == refs[1] and refs[0] != refs[2]  # period 1 stable, period 2 distinct


def test_expiration_grants_nothing_and_marks_expired() -> None:
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    asyncio.run(apply_webhook_event(conn, _evt(type="EXPIRATION", product_id="pro_monthly")))
    assert conn.grants == []
    sub = conn.execs_matching("public.user_subscriptions")[0]
    assert "expired" in sub  # status arg


def test_renewal_grants_credits() -> None:
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    asyncio.run(apply_webhook_event(conn, _evt(type="RENEWAL", product_id="pro_monthly")))
    assert conn.grants and conn.grants[0][1] == 75


def test_cancellation_stays_entitled_without_granting() -> None:
    # Auto-renew off: still entitled until expiry, but NOT a new period → no grant.
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    asyncio.run(apply_webhook_event(conn, _evt(type="CANCELLATION", product_id="pro_monthly")))
    assert conn.grants == []
    sub = conn.execs_matching("public.user_subscriptions")[0]
    assert "canceled" in sub
    assert conn.execs_matching("public.entitlements")[0][1] is True  # entitled flag


def test_billing_issue_is_grace_without_granting() -> None:
    conn = _FakeConn(plan_row=_plan("pro_max", "subscription", 150, True))
    asyncio.run(apply_webhook_event(conn, _evt(type="BILLING_ISSUE", product_id="pro_max_monthly")))
    assert conn.grants == []
    assert "grace" in conn.execs_matching("public.user_subscriptions")[0]


def test_refund_revokes_without_granting() -> None:
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    asyncio.run(apply_webhook_event(conn, _evt(type="REFUND", product_id="pro_monthly")))
    assert conn.grants == []
    assert "expired" in conn.execs_matching("public.user_subscriptions")[0]
    assert conn.execs_matching("public.entitlements")[0][1] is False  # revoked


def test_topup_records_purchase_and_grants_to_topup_bucket() -> None:
    conn = _FakeConn(plan_row=_plan("topup_40", "topup", 40, False))
    ok = asyncio.run(
        apply_webhook_event(
            conn, _evt(type="NON_RENEWING_PURCHASE", product_id="topup_40", id="txn-1")
        )
    )
    assert ok is True
    assert conn.execs_matching("public.top_up_purchases")
    g = conn.grants[0]
    assert g[1] == 40 and g[5] == "topup" and g[3] == "topup:txn-1"


def test_colon_form_product_id_grants_pro_tier_via_webhook() -> None:
    # RevenueCat sends the Google Play subscription id as "pro_monthly:monthly";
    # the webhook must still set tier pro + grant 75 (plan_for_product strips the
    # base-plan suffix — normalization unit-tested in test_plans.py).
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False))
    ok = asyncio.run(apply_webhook_event(conn, _evt(product_id="pro_monthly:monthly")))
    assert ok is True
    sub = conn.execs_matching("public.user_subscriptions")[0]
    assert sub[1] == "pro"  # tier arg
    assert conn.grants and conn.grants[0][1] == 75 and conn.grants[0][5] == "plan"


def test_topup_does_not_grant_premium_tier() -> None:
    # topup_40 must NEVER confer premium: no user_subscriptions tier, no
    # entitlement row — only the top-up credit bucket grows.
    conn = _FakeConn(plan_row=_plan("topup_40", "topup", 40, False))
    asyncio.run(
        apply_webhook_event(
            conn, _evt(type="NON_RENEWING_PURCHASE", product_id="topup_40", id="txn-p")
        )
    )
    assert conn.execs_matching("public.user_subscriptions") == []
    assert conn.execs_matching("public.entitlements") == []
    assert conn.grants[0][5] == "topup"


def test_duplicate_topup_webhook_grants_credits_once() -> None:
    conn = _DedupConn(plan_row=_plan("topup_40", "topup", 40, False))
    evt = _evt(type="NON_RENEWING_PURCHASE", product_id="topup_40", id="txn-dup")
    asyncio.run(apply_webhook_event(conn, evt))
    asyncio.run(apply_webhook_event(conn, evt))  # RevenueCat redelivery
    topup_grants = [g for g in conn.grants if g[5] == "topup"]
    assert len(topup_grants) == 1  # 40 credits granted exactly once


def test_duplicate_initial_purchase_grants_credits_once() -> None:
    conn = _DedupConn(plan_row=_plan("pro", "subscription", 75, False))
    evt = _evt(product_id="pro_monthly", purchased_at_ms=1_234_000)
    asyncio.run(apply_webhook_event(conn, evt))
    asyncio.run(apply_webhook_event(conn, evt))  # same period → same ref
    plan_grants = [g for g in conn.grants if g[5] == "plan"]
    assert len(plan_grants) == 1


def test_unmapped_product_updates_entitlement_only() -> None:
    # Legacy/unknown product → entitlement back-compat row, no tier/grant.
    conn = _FakeConn(plan_row=None)
    ok = asyncio.run(apply_webhook_event(conn, _evt(product_id="annual")))
    assert ok is True
    assert conn.execs_matching("public.entitlements")
    assert conn.execs_matching("public.user_subscriptions") == []
    assert conn.grants == []


def test_non_uuid_app_user_id_is_ignored() -> None:
    conn = _FakeConn()
    ok = asyncio.run(
        apply_webhook_event(conn, _evt(app_user_id="$RCAnonymousID:x", product_id="pro_monthly"))
    )
    assert ok is False and conn.execs == []


def test_unknown_user_is_ignored() -> None:
    conn = _FakeConn(plan_row=_plan("pro", "subscription", 75, False), fk_error=True)
    ok = asyncio.run(apply_webhook_event(conn, _evt(product_id="pro_monthly")))
    assert ok is False


def test_grant_ref_is_deterministic() -> None:
    dt = datetime(2026, 6, 1, tzinfo=UTC)
    assert grant_ref("u1", dt) == grant_ref("u1", dt)
    assert grant_ref("u1", dt) != grant_ref("u1", datetime(2026, 7, 1, tzinfo=UTC))


# ── tier-based premium gate (reads user_subscriptions) ───────────────────────


def test_no_subscription_is_not_premium() -> None:
    conn = _FakeConn(sub_row=None)
    assert asyncio.run(is_premium(conn, str(uuid.uuid4()))) is False


def test_active_pro_max_is_premium() -> None:
    conn = _FakeConn(
        sub_row={
            "tier": "pro_max",
            "status": "active",
            "current_period_start": datetime.now(UTC),
            "current_period_end": datetime.now(UTC) + timedelta(days=10),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is True


def test_expired_period_is_not_premium() -> None:
    conn = _FakeConn(
        sub_row={
            "tier": "pro",
            "status": "active",
            "current_period_start": datetime.now(UTC) - timedelta(days=40),
            "current_period_end": datetime.now(UTC) - timedelta(days=1),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is False


@pytest.mark.parametrize("status", ["canceled", "grace"])
def test_canceled_or_grace_in_period_is_still_premium(status: str) -> None:
    conn = _FakeConn(
        sub_row={
            "tier": "pro_max",
            "status": status,
            "current_period_start": datetime.now(UTC),
            "current_period_end": datetime.now(UTC) + timedelta(days=5),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is True


def test_expired_status_is_not_premium_even_in_period() -> None:
    conn = _FakeConn(
        sub_row={
            "tier": "pro",
            "status": "expired",  # refund/revoke cuts access regardless of period
            "current_period_start": datetime.now(UTC),
            "current_period_end": datetime.now(UTC) + timedelta(days=5),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is False


# ── legacy entitlement read (existing endpoint contract) ─────────────────────


def test_get_entitlement_no_row() -> None:
    conn = _FakeConn(ent_row=None)
    assert asyncio.run(get_entitlement(conn, str(uuid.uuid4()))) == EntitlementResponse()


def test_get_entitlement_active() -> None:
    conn = _FakeConn(
        ent_row={
            "active": True,
            "product_id": "pro_monthly",
            "store": "play_store",
            "expires_at": datetime.now(UTC) + timedelta(days=10),
        }
    )
    assert asyncio.run(get_entitlement(conn, "u")).active is True


# ── endpoints ────────────────────────────────────────────────────────────────


def test_entitlement_requires_token() -> None:
    assert client.get("/v1/billing/entitlement").status_code == 401


def test_webhook_rejects_bad_secret() -> None:
    resp = client.post(
        "/v1/billing/webhook",
        json={"event": {"type": "INITIAL_PURCHASE"}},
        headers={"Authorization": "wrong"},
    )
    assert resp.status_code == 401


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_billing_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.services.billing import _SUB_UPSERT, _UPSERT

    stmts = [
        _UPSERT,
        _SUB_UPSERT,
        "select active, product_id, store, expires_at "
        "from public.entitlements where user_id = $1::uuid",
        "select tier, status, current_period_start, current_period_end "
        "from public.user_subscriptions where user_id = $1::uuid",
        "select tier, kind, monthly_credits, hd_allowed, priority from public.plans "
        "where play_product_id = $1 or app_product_id = $1",
        "select public.app_grant_credits($1::uuid, $2, $3, $4, $5, $6)",
        "insert into public.top_up_purchases (user_id, sku, credits, store, store_txn_id) "
        "values ($1::uuid, $2, $3, $4, $5) on conflict (store_txn_id) do nothing",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
