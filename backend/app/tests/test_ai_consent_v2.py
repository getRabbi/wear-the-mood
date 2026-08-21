"""The v2 forced re-consent, and the traps a version bump sets.

Bumping `CURRENT_AI_CONSENT_VERSION` is one line. What that line does to a live
system is not obvious, and these tests pin the parts that are easy to get wrong:

  * an account that accepted v1 must be asked again — that is the whole point;
  * an account that accepts v2 must NOT be asked again, ever, until v3;
  * a build that still shows the v1 disclosure must NOT be able to record a v2
    agreement, and must NOT be walked into a consent loop either;
  * the gate is SERVER-side, so a client that skips the sheet gets refused with
    nothing sent to a provider and nothing charged;
  * bumping preserves history rather than erasing it.
"""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.errors import ApiError
from app.main import app
from app.models.common import ErrorCode
from app.services.privacy import (
    CURRENT_AI_CONSENT_VERSION,
    ConsentState,
    grant_ai_consent,
    read_ai_consent,
    require_ai_personal_image_consent,
    revoke_ai_consent,
)
from app.tests.test_giveaway_chat import _Conn, _Pool

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_A = "11111111-1111-4111-8111-111111111111"
USER_B = "22222222-2222-4222-8222-222222222222"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth(user: str = USER_A) -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": user,
            "aud": "authenticated",
            "email": "a@b.com",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


class _ConsentStore:
    """An in-memory stand-in for `user_privacy_consents` + its audit log.

    Models the two properties that matter: the state table holds ONE row per
    (user, type) and is overwritten in place, while the event log only ever
    grows.
    """

    def __init__(self, rows: dict[str, dict] | None = None) -> None:
        self.rows: dict[str, dict] = rows or {}
        self.events: list[dict] = []

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()

    @staticmethod
    def _norm(sql: str) -> str:
        return " ".join(sql.split()).lower()

    async def fetchrow(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.user_privacy_consents" in s:
            return self.rows.get(str(args[0]))
        if "update public.user_privacy_consents" in s:
            row = self.rows.get(str(args[0]))
            if row is None or row["revoked_at"] is not None:
                return None
            row["revoked_at"] = "now"
            return row
        return None

    async def execute(self, sql: str, *args):
        s = self._norm(sql)
        if "insert into public.user_privacy_consents" in s:
            self.rows[str(args[0])] = {
                "consent_version": args[2],
                "provider_scope": args[3],
                "revoked_at": None,
            }
            return "INSERT 0 1"
        if "insert into public.user_privacy_consent_events" in s:
            self.events.append({"user": str(args[0]), "action": args[2], "version": args[3]})
            return "INSERT 0 1"
        return "OK"


def _granted_at(version: int) -> dict:
    return {
        "consent_version": version,
        "provider_scope": "openai_moderation,fashn",
        "revoked_at": None,
    }


# ── the bump itself ──────────────────────────────────────────────────────────


def test_the_required_version_is_two() -> None:
    """The release contract. If this drops back to 1, no existing account is
    re-prompted and the whole requirement silently evaporates."""
    assert CURRENT_AI_CONSENT_VERSION == 2


def test_an_account_that_accepted_v1_is_no_longer_current() -> None:
    state = ConsentState(granted=True, version=1, provider_scope="x")
    assert state.is_current is False


def test_an_account_that_accepted_v2_is_current() -> None:
    state = ConsentState(granted=True, version=2, provider_scope="x")
    assert state.is_current is True


def test_a_newer_grant_than_we_require_still_counts() -> None:
    """A rolling deploy can leave an old process asking. Someone who agreed to
    MORE must not be re-prompted by it."""
    state = ConsentState(granted=True, version=3, provider_scope="x")
    assert state.is_current is True


def test_a_revoked_v2_grant_is_not_current() -> None:
    state = ConsentState(granted=False, version=2, provider_scope="x")
    assert state.is_current is False


# ── the server-side gate ─────────────────────────────────────────────────────


def _require(store: _ConsentStore, user: str = USER_A):
    return asyncio.run(require_ai_personal_image_consent(store, user))  # type: ignore[arg-type]


def test_an_existing_v1_account_is_blocked_before_anything_is_shared() -> None:
    store = _ConsentStore({USER_A: _granted_at(1)})
    try:
        _require(store)
    except ApiError as exc:
        assert exc.code == ErrorCode.AI_DATA_SHARING_CONSENT_REQUIRED
        assert exc.status_code == 403
        return
    raise AssertionError("a stale v1 grant must not authorise a render")


def test_an_account_with_no_consent_at_all_is_blocked() -> None:
    store = _ConsentStore()
    try:
        _require(store)
    except ApiError as exc:
        assert exc.code == ErrorCode.AI_DATA_SHARING_CONSENT_REQUIRED
        return
    raise AssertionError("no consent must not authorise a render")


def test_a_v2_account_passes_and_reports_the_version() -> None:
    store = _ConsentStore({USER_A: _granted_at(2)})
    assert _require(store) == 2


def test_the_gate_is_scoped_to_the_caller() -> None:
    """A's consent must never authorise B."""
    store = _ConsentStore({USER_A: _granted_at(2)})
    assert _require(store, USER_A) == 2
    try:
        _require(store, USER_B)
    except ApiError as exc:
        assert exc.code == ErrorCode.AI_DATA_SHARING_CONSENT_REQUIRED
        return
    raise AssertionError("one account's consent must not cover another")


# ── accepting, and not being asked again ─────────────────────────────────────


def test_accepting_v2_makes_the_next_render_pass() -> None:
    store = _ConsentStore({USER_A: _granted_at(1)})
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    # Second, third, hundredth render: no prompt, because the gate passes.
    assert _require(store) == 2
    assert _require(store) == 2


def test_re_granting_is_idempotent_for_the_gate() -> None:
    store = _ConsentStore()
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    assert _require(store) == 2
    assert len(store.rows) == 1


def test_revoking_asks_again() -> None:
    store = _ConsentStore()
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    asyncio.run(revoke_ai_consent(store, USER_A))  # type: ignore[arg-type]
    state = asyncio.run(read_ai_consent(store, USER_A))  # type: ignore[arg-type]
    assert state.is_current is False


# ── history is preserved, not overwritten ────────────────────────────────────


def test_the_v1_acceptance_survives_the_v2_grant() -> None:
    """The audit requirement. The state row is overwritten by design; the
    decision must still be recoverable afterwards."""
    store = _ConsentStore()
    asyncio.run(grant_ai_consent(store, USER_A, version=1))  # type: ignore[arg-type]
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]

    # State: only the current version.
    assert store.rows[USER_A]["consent_version"] == 2
    # History: both decisions, in order.
    assert [e["version"] for e in store.events] == [1, 2]
    assert {e["action"] for e in store.events} == {"granted"}


def test_a_withdrawal_is_recorded_too() -> None:
    store = _ConsentStore()
    asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    asyncio.run(revoke_ai_consent(store, USER_A))  # type: ignore[arg-type]
    assert [e["action"] for e in store.events] == ["granted", "revoked"]


def test_revoking_something_never_granted_records_nothing() -> None:
    store = _ConsentStore()
    asyncio.run(revoke_ai_consent(store, USER_A))  # type: ignore[arg-type]
    assert store.events == []


def test_a_failed_audit_write_never_blocks_the_consent() -> None:
    """Evidence beside the decision, not in front of it."""

    class _NoAuditStore(_ConsentStore):
        async def execute(self, sql: str, *args):
            if "user_privacy_consent_events" in self._norm(sql):
                raise RuntimeError("audit table unavailable")
            return await super().execute(sql, *args)

    store = _NoAuditStore()
    state = asyncio.run(grant_ai_consent(store, USER_A, version=2))  # type: ignore[arg-type]
    assert state.is_current is True


# ── the API, and the old-client trap ─────────────────────────────────────────


def _install(monkeypatch: pytest.MonkeyPatch, store: _ConsentStore):
    import app.routers.v1.privacy as privacy_mod

    monkeypatch.setattr(privacy_mod, "get_pool", lambda: _Pool(store))  # type: ignore[arg-type]
    return privacy_mod


def test_the_api_reports_the_required_version_so_the_client_can_tell(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, _ConsentStore({USER_A: _granted_at(1)}))
    body = client.get("/v1/privacy/ai-consent", headers=_auth()).json()
    assert body["version"] == 1
    assert body["required_version"] == 2
    assert body["is_current"] is False
    assert body["granted"] is True  # granted, but not to the current terms


def test_an_old_client_grant_is_refused_rather_than_stored(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """THE CONSENT-LOOP REGRESSION.

    A build that shows the v1 disclosure sends `consent_version: 1`. Storing it
    would write a row that can never satisfy the gate, so the user would tap
    Allow, be refused, be shown the sheet again — forever. Refusing lets the
    client say "update the app" instead.
    """
    store = _ConsentStore()
    _install(monkeypatch, store)
    resp = client.post("/v1/privacy/ai-consent", json={"consent_version": 1}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    # And crucially: nothing was written, so no unsatisfiable row exists.
    assert store.rows == {}
    assert store.events == []


def test_a_client_claiming_a_future_version_is_refused(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Nobody may record agreement to terms that have never been displayed."""
    store = _ConsentStore()
    _install(monkeypatch, store)
    resp = client.post("/v1/privacy/ai-consent", json={"consent_version": 99}, headers=_auth())
    assert resp.status_code == 422
    assert store.rows == {}


def test_the_current_client_grant_is_accepted(monkeypatch: pytest.MonkeyPatch) -> None:
    store = _ConsentStore()
    _install(monkeypatch, store)
    body = client.post(
        "/v1/privacy/ai-consent", json={"consent_version": 2}, headers=_auth()
    ).json()
    assert body["is_current"] is True
    assert body["version"] == 2
    assert store.rows[USER_A]["consent_version"] == 2


def test_consent_endpoints_require_a_token() -> None:
    assert client.get("/v1/privacy/ai-consent").status_code == 401
    assert client.post("/v1/privacy/ai-consent", json={}).status_code == 401
    assert client.delete("/v1/privacy/ai-consent").status_code == 401


# ── the bypass attempt ───────────────────────────────────────────────────────


def test_a_direct_tryon_call_without_consent_is_refused_before_any_spend(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The scripted-client case: skip the sheet, POST /v1/tryon directly.

    The gate is server-side and sits BEFORE moderation, before the provider and
    before the credit reserve, so the refusal costs the user nothing and shares
    nothing. Asserted by inspecting what SQL the request actually ran.
    """
    import app.routers.v1.tryon as tryon_mod

    conn = _Conn(
        [
            # idempotency replay lookup → no stored response
            ("fetchrow", "from public.idempotency_keys", None),
            # Flags, answered PER KEY: the kill switch is on, and
            # `tryon_strict_categories` is off — a blanket True would also turn
            # strict mode on, refusing the plan before the consent gate is even
            # reached and passing this test for entirely the wrong reason.
            (
                "fetchval",
                "from public.feature_flags",
                lambda sql, args: args[0] == "ai_tryon_enabled",
            ),
            # monetization config / experiments
            ("fetch", "from public.monetization_config", []),
            ("fetch", "from public.experiment_assignments", []),
            # plan + credits
            ("fetchrow", "from public.user_subscriptions", None),
            (
                "fetchrow",
                "from public.credits",
                {"balance": 10, "daily_free_used": 0, "topup_balance": 0},
            ),
            # consent: an account still on v1
            ("fetchrow", "from public.user_privacy_consents", _granted_at(1)),
        ]
    )
    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))

    called: list[str] = []
    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: called.append("moderator") or None)

    resp = client.post(
        "/v1/tryon",
        json={
            "person_image_url": "https://cdn.test/body.png",
            "garment_image_url": "https://cdn.test/shirt.png",
        },
        headers={**_auth(), "Idempotency-Key": str(uuid.uuid4())},
    )

    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "AI_DATA_SHARING_CONSENT_REQUIRED"
    # Nothing was moderated (no third-party transmission), no job row, no spend.
    assert called == []
    executed = " ".join(sql for _m, sql, _a in conn.calls).lower()
    assert "insert into public.tryon_jobs" not in executed
    assert "insert into public.credit_transactions" not in executed
