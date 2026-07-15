"""Daily stylist push (CLAUDE.md §20) — sender resolver, stub, cron selection,
token endpoints, and live SQL validation."""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.cron.daily import _daily_message, run_daily_push
from app.main import app
from app.services.push import DeliveryStatus, PushMessage, StubSender, get_push_sender

client = TestClient(app)


@pytest.fixture(autouse=True)
def _clear_cache():
    get_push_sender.cache_clear()
    get_settings.cache_clear()
    yield
    get_push_sender.cache_clear()
    get_settings.cache_clear()


# ── stub sender + resolver ───────────────────────────────────────────────────


def test_stub_sender_reports_success() -> None:
    sent = asyncio.run(StubSender().send("devicetoken123", _daily_message()))
    assert sent == DeliveryStatus.ok
    assert StubSender().name == "stub"


def test_default_push_sender_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("PUSH_PROVIDER", raising=False)
    get_settings.cache_clear()
    get_push_sender.cache_clear()
    assert get_push_sender().name == "stub"


def test_fcm_without_creds_falls_back_to_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PUSH_PROVIDER", "fcm")
    monkeypatch.setenv("FCM_CREDENTIALS_JSON", "")  # no creds -> not usable
    get_settings.cache_clear()
    get_push_sender.cache_clear()
    assert get_push_sender().name == "stub"


def test_push_message_defaults_empty_data() -> None:
    msg = PushMessage(title="t", body="b")
    assert msg.data == {}


def test_daily_message_deep_links_to_stylist() -> None:
    msg = _daily_message()
    assert msg.data["route"] == "/stylist"
    assert msg.title and msg.body


# ── cron selection + send loop (fake conn + recording sender) ────────────────


class _RecordingSender:
    name = "recording"

    def __init__(
        self,
        fail_tokens: set[str] | None = None,
        *,
        fail_status: DeliveryStatus = DeliveryStatus.retryable,
    ) -> None:
        self.sent: list[tuple[str, PushMessage]] = []
        self._fail = fail_tokens or set()
        self._fail_status = fail_status

    async def send(self, token: str, message: PushMessage) -> DeliveryStatus:
        self.sent.append((token, message))
        return self._fail_status if token in self._fail else DeliveryStatus.ok


class _FetchConn:
    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows
        self.executed: list = []

    async def fetch(self, *args, **kwargs):
        return self._rows

    async def execute(self, *args, **kwargs):
        self.executed.append(args)


def test_run_daily_push_sends_to_each_due_device() -> None:
    rows = [{"token": "a", "user_id": "u1"}, {"token": "b", "user_id": "u2"}]
    sender = _RecordingSender()
    n = asyncio.run(run_daily_push(_FetchConn(rows), sender, target_hour=8))
    assert n == 2
    assert [t for t, _ in sender.sent] == ["a", "b"]
    assert sender.sent[0][1].data["route"] == "/stylist"


def test_run_daily_push_counts_only_delivered() -> None:
    rows = [{"token": "a", "user_id": "u1"}, {"token": "b", "user_id": "u2"}]
    sender = _RecordingSender(fail_tokens={"b"})  # transient failure
    conn = _FetchConn(rows)
    n = asyncio.run(run_daily_push(conn, sender, target_hour=8))
    assert n == 1  # b failed but the run still finished both
    assert len(sender.sent) == 2
    assert conn.executed == []  # a transient failure never prunes the token


def test_run_daily_push_prunes_invalid_tokens() -> None:
    rows = [{"token": "a", "user_id": "u1"}, {"token": "dead", "user_id": "u2"}]
    sender = _RecordingSender(fail_tokens={"dead"}, fail_status=DeliveryStatus.invalid_token)
    conn = _FetchConn(rows)
    n = asyncio.run(run_daily_push(conn, sender, target_hour=8))
    assert n == 1
    assert len(conn.executed) == 1  # the dead token is deactivated
    assert conn.executed[0][1] == ["dead"]  # (sql, [tokens]) → the token-array arg


# ── token endpoints require auth ─────────────────────────────────────────────


def test_register_push_token_requires_token() -> None:
    resp = client.put("/v1/profile/push-token", json={"token": "abc"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_delete_push_token_requires_token() -> None:
    resp = client.delete("/v1/profile/push-token", params={"token": "abc"})
    assert resp.status_code == 401


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_push_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.cron.daily import _DUE_TOKENS

    stmts = [
        _DUE_TOKENS,
        "select exists(select 1 from pg_timezone_names where name = $1)",
        "update public.profiles set timezone = $2, updated_at = now() where id = $1::uuid",
        "insert into public.device_tokens (user_id, token, platform, push_opt_in) "
        "values ($1::uuid, $2, $3, true) "
        "on conflict (user_id, token) do update "
        "set platform = excluded.platform, push_opt_in = true, "
        "invalidated_at = null, updated_at = now()",
        "delete from public.device_tokens where user_id = $1::uuid and token = $2",
        "update public.device_tokens set invalidated_at = now() "
        "where user_id = $1::uuid and token = any($2::text[]) and invalidated_at is null",
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
