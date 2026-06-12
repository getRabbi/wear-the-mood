"""Subscriptions / entitlements (CLAUDE.md §18) — webhook auth + event mapping,
entitlement read, premium gate, live SQL schema."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.billing import EntitlementResponse
from app.services.billing import apply_webhook_event, get_entitlement, is_premium

WEBHOOK_SECRET = "whsec-test-123"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _webhook_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH", WEBHOOK_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


class _FakeConn:
    """Records the upsert and serves a canned entitlement row."""

    def __init__(self, row=None, fk_error: bool = False) -> None:
        self._row = row
        self._fk_error = fk_error
        self.upserts: list[tuple] = []

    async def execute(self, sql: str, *args):
        if self._fk_error:
            import asyncpg

            raise asyncpg.ForeignKeyViolationError("no such user")
        self.upserts.append(args)

    async def fetchrow(self, sql: str, *args):
        return self._row


# ── webhook event mapping ────────────────────────────────────────────────────


def test_purchase_event_sets_active() -> None:
    conn = _FakeConn()
    future_ms = int((datetime.now(UTC) + timedelta(days=30)).timestamp() * 1000)
    ok = asyncio.run(
        apply_webhook_event(
            conn,
            {
                "type": "INITIAL_PURCHASE",
                "app_user_id": str(uuid.uuid4()),
                "product_id": "annual",
                "store": "PLAY_STORE",
                "expiration_at_ms": future_ms,
            },
        )
    )
    assert ok is True
    # args: (app_user_id, active, product_id, store, expires_at)
    args = conn.upserts[0]
    assert args[1] is True and args[2] == "annual" and args[3] == "play_store"


def test_expiration_event_clears_active() -> None:
    conn = _FakeConn()
    asyncio.run(apply_webhook_event(conn, {"type": "EXPIRATION", "app_user_id": str(uuid.uuid4())}))
    assert conn.upserts[0][1] is False


def test_past_expiry_is_inactive_even_on_renewal() -> None:
    conn = _FakeConn()
    past_ms = int((datetime.now(UTC) - timedelta(days=1)).timestamp() * 1000)
    asyncio.run(
        apply_webhook_event(
            conn,
            {"type": "RENEWAL", "app_user_id": str(uuid.uuid4()), "expiration_at_ms": past_ms},
        )
    )
    assert conn.upserts[0][1] is False


def test_non_uuid_app_user_id_is_ignored() -> None:
    conn = _FakeConn()
    ok = asyncio.run(
        apply_webhook_event(conn, {"type": "INITIAL_PURCHASE", "app_user_id": "$RCAnonymousID:x"})
    )
    assert ok is False and conn.upserts == []


def test_unknown_user_is_ignored() -> None:
    conn = _FakeConn(fk_error=True)
    ok = asyncio.run(
        apply_webhook_event(conn, {"type": "INITIAL_PURCHASE", "app_user_id": str(uuid.uuid4())})
    )
    assert ok is False


# ── entitlement read + premium gate ──────────────────────────────────────────


def test_no_row_means_not_premium() -> None:
    conn = _FakeConn(row=None)
    ent = asyncio.run(get_entitlement(conn, str(uuid.uuid4())))
    assert ent == EntitlementResponse()
    assert asyncio.run(is_premium(conn, str(uuid.uuid4()))) is False


def test_active_row_in_future_is_premium() -> None:
    conn = _FakeConn(
        row={
            "active": True,
            "product_id": "annual",
            "store": "play_store",
            "expires_at": datetime.now(UTC) + timedelta(days=10),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is True


def test_active_flag_but_expired_is_not_premium() -> None:
    conn = _FakeConn(
        row={
            "active": True,
            "product_id": "annual",
            "store": "play_store",
            "expires_at": datetime.now(UTC) - timedelta(days=1),
        }
    )
    assert asyncio.run(is_premium(conn, "u")) is False


# ── endpoints ────────────────────────────────────────────────────────────────


def test_entitlement_requires_token() -> None:
    resp = client.get("/v1/billing/entitlement")
    assert resp.status_code == 401


def test_webhook_rejects_bad_secret() -> None:
    resp = client.post(
        "/v1/billing/webhook",
        json={"event": {"type": "INITIAL_PURCHASE"}},
        headers={"Authorization": "wrong"},
    )
    assert resp.status_code == 401


def test_webhook_rejects_missing_auth() -> None:
    resp = client.post("/v1/billing/webhook", json={"event": {}})
    assert resp.status_code == 401


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_billing_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.services.billing import _UPSERT

    stmts = [
        _UPSERT,
        "select active, product_id, store, expires_at "
        "from public.entitlements where user_id = $1::uuid",
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
