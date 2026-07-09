import asyncio
import json
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import (
    CreditsState,
    InsufficientCreditsError,
    _draw,
    authorize_premium_ai,
    authorize_tryon,
    has_credit,
    refund_credit,
    spend_credit,
)
from app.core.errors import ApiError
from app.core.plans import FREE_PLAN, HD_COST, STD_COST, Plan
from app.main import app

# HD / Try-On Max is Pro Max ONLY (founder decision): Pro's hd_allowed is false,
# matching migration 0036 + the plans seed.
_PRO = Plan(tier="pro", kind="subscription", monthly_credits=75, hd_allowed=False, priority=False)
_PRO_MAX = Plan(
    tier="pro_max", kind="subscription", monthly_credits=150, hd_allowed=True, priority=True
)

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token(sub: str = "user-123") -> str:
    now = int(time.time())
    payload = {
        "sub": sub,
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def test_credits_requires_token() -> None:
    # Auth is checked before the handler touches the DB, so this holds with no DSN.
    resp = client.get("/v1/credits")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_credits_rejects_bad_signature() -> None:
    bad = jwt.encode(
        {"sub": "user-123", "aud": "authenticated", "exp": int(time.time()) + 3600},
        "a-totally-different-wrong-secret-0123456789",
        algorithm="HS256",
    )
    resp = client.get("/v1/credits", headers={"Authorization": f"Bearer {bad}"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_daily_free_remaining_normal() -> None:
    state = CreditsState(balance=10, daily_free_used=2, daily_free_limit=5)
    assert state.daily_free_remaining == 3


def test_daily_free_remaining_clamps_to_zero() -> None:
    # Limit lowered below what's already been used must not go negative.
    state = CreditsState(balance=0, daily_free_used=7, daily_free_limit=5)
    assert state.daily_free_remaining == 0


def test_has_credit() -> None:
    assert has_credit(CreditsState(balance=0, daily_free_used=4, daily_free_limit=5)) is True
    assert has_credit(CreditsState(balance=2, daily_free_used=5, daily_free_limit=5)) is True
    assert has_credit(CreditsState(balance=0, daily_free_used=5, daily_free_limit=5)) is False


def test_free_trial_is_three_total_one_time(monkeypatch: pytest.MonkeyPatch) -> None:
    # Canonical rule (Issue 3/4): 3 free AI try-ons TOTAL, then the paywall.
    monkeypatch.delenv("FREE_TRYON_TRIAL_CREDITS", raising=False)
    get_settings.cache_clear()
    assert get_settings().free_tryon_trial_credits == 3
    # First three are free; the fourth has nothing left (no daily reset).
    assert has_credit(CreditsState(balance=0, daily_free_used=2, daily_free_limit=3)) is True
    assert has_credit(CreditsState(balance=0, daily_free_used=3, daily_free_limit=3)) is False


# ── _draw: free trial → plan balance → top-up, drawing across buckets ────────


def test_draw_free_first() -> None:
    # Free available: take from the trial, leave plan balance + top-up untouched.
    assert _draw(free_remaining=5, balance=10, topup=3, cost=1) == (1, 0, 0)


def test_draw_falls_through_to_plan_then_topup() -> None:
    assert _draw(free_remaining=0, balance=3, topup=9, cost=1) == (0, 1, 0)
    assert _draw(free_remaining=0, balance=0, topup=9, cost=2) == (0, 0, 2)


def test_draw_splits_across_buckets() -> None:
    # 1 free + 1 plan + 2 top-up covers a cost-4 HD render.
    assert _draw(free_remaining=1, balance=1, topup=5, cost=4) == (1, 1, 2)
    # 2 plan + 2 top-up.
    assert _draw(free_remaining=0, balance=2, topup=3, cost=4) == (0, 2, 2)


def test_draw_insufficient_returns_none() -> None:
    assert _draw(free_remaining=0, balance=1, topup=1, cost=4) is None
    assert _draw(free_remaining=0, balance=0, topup=0, cost=1) is None


def test_has_credit_is_cost_aware() -> None:
    s = CreditsState(balance=1, daily_free_used=5, daily_free_limit=5, topup_balance=2)
    assert s.total_available == 3
    assert has_credit(s, STD_COST) is True  # 3 >= 1
    assert has_credit(s, 3) is True
    assert has_credit(s, HD_COST) is False  # 3 < 4
    # HD needs 4: a Pro Max with full plan balance can afford it.
    assert has_credit(CreditsState(balance=150, daily_free_used=0, daily_free_limit=3), HD_COST)


# ── authorize_tryon: the HD/subscriber + cost policy gate (req #5/#6/#7/#8) ──


def _state(total: int) -> CreditsState:
    """Spendable `total` from the plan bucket (free trial exhausted)."""
    return CreditsState(balance=total, daily_free_used=999, daily_free_limit=3)


def test_authorize_free_user_cannot_hd_even_with_credits() -> None:
    # HD is Pro Max ONLY: a free user is locked even holding 10 credits.
    with pytest.raises(ApiError) as exc:
        authorize_tryon(hd=True, plan=FREE_PLAN, state=_state(10))
    assert exc.value.code == "HD_LOCKED"
    assert exc.value.status_code == 403
    assert exc.value.message == "Upgrade to Pro Max for HD."


def test_authorize_pro_hd_blocked_even_with_credits() -> None:
    # Pro is NOT eligible for HD (Pro Max only) — locked before cost is considered,
    # even holding 4 credits.
    with pytest.raises(ApiError) as exc:
        authorize_tryon(hd=True, plan=_PRO, state=_state(4))
    assert exc.value.code == "HD_LOCKED"
    assert exc.value.status_code == 403
    assert exc.value.message == "Upgrade to Pro Max for HD."


def test_authorize_pro_max_hd_costs_four() -> None:
    assert authorize_tryon(hd=True, plan=_PRO_MAX, state=_state(4)) == HD_COST


def test_authorize_pro_max_hd_insufficient_is_paywall() -> None:
    # Eligible for HD but short on credits → PAYWALL (not HD_LOCKED).
    with pytest.raises(ApiError) as exc:
        authorize_tryon(hd=True, plan=_PRO_MAX, state=_state(1))
    assert exc.value.code == "PAYWALL"
    assert exc.value.status_code == 402
    assert exc.value.message == "You need 4 credits for HD."


def test_authorize_pro_standard_costs_one() -> None:
    # Standard renders stay available to Pro (and Pro Max).
    assert authorize_tryon(hd=False, plan=_PRO, state=_state(1)) == STD_COST


def test_authorize_pro_max_standard_costs_one() -> None:
    assert authorize_tryon(hd=False, plan=_PRO_MAX, state=_state(1)) == STD_COST


def test_authorize_standard_costs_one_for_anyone() -> None:
    assert authorize_tryon(hd=False, plan=FREE_PLAN, state=_state(1)) == STD_COST


def test_authorize_standard_insufficient_is_paywall() -> None:
    with pytest.raises(ApiError) as exc:
        authorize_tryon(hd=False, plan=FREE_PLAN, state=_state(0))
    assert exc.value.code == "PAYWALL"
    assert exc.value.status_code == 402


# ── authorize_premium_ai: AI Studio (enhance / catalog) gate ─────────────────
# Subscriber-only (Pro OR Pro Max); HD within it is Pro Max only, consistent copy.


def test_premium_ai_free_user_blocked() -> None:
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=False, plan=FREE_PLAN, state=_state(10))
    assert exc.value.code == "PAYWALL"  # AI Studio is subscriber-only


def test_premium_ai_pro_standard_costs_one() -> None:
    assert authorize_premium_ai(hd=False, plan=_PRO, state=_state(1)) == STD_COST


def test_premium_ai_pro_hd_blocked() -> None:
    # Catalog HD is Pro Max only — a Pro user is HD_LOCKED with the SAME copy.
    with pytest.raises(ApiError) as exc:
        authorize_premium_ai(hd=True, plan=_PRO, state=_state(4))
    assert exc.value.code == "HD_LOCKED"
    assert exc.value.message == "Upgrade to Pro Max for HD."


def test_premium_ai_pro_max_hd_costs_four() -> None:
    assert authorize_premium_ai(hd=True, plan=_PRO_MAX, state=_state(4)) == HD_COST


# ── reserve (spend_credit) + refund_credit on a simulated credits row ────────


class _FakeConn:
    """In-memory stand-in for the asyncpg connection that backs spend_credit /
    refund_credit — enough to exercise the real bucket math, idempotency and the
    no-negative guard without a live DB (matches the codebase's unit-test style;
    the FOR UPDATE lock itself is covered by the live SQL test)."""

    def __init__(self, *, balance: int = 0, daily_free_used: int = 0, topup_balance: int = 0):
        self.credits = {
            "balance": balance,
            "daily_free_used": daily_free_used,
            "topup_balance": topup_balance,
        }
        self.txns: list[dict] = []

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

    async def execute(self, sql: str, *args):
        s = self._norm(sql)
        if "insert into public.credits" in s and "on conflict" in s:
            return "INSERT 0 0"
        if "update public.credits set balance" in s:
            self.credits["balance"] = args[1]
            self.credits["daily_free_used"] = args[2]
            self.credits["topup_balance"] = args[3]
            return "UPDATE 1"
        if "insert into public.credit_transactions" in s:
            reason = "spend" if "'spend'" in s else "refund" if "'refund'" in s else "other"
            meta_raw = args[5]
            meta = json.loads(meta_raw) if isinstance(meta_raw, str) else (meta_raw or {})
            self.txns.append(
                {"ref": args[3], "reason": reason, "delta": args[1], "meta": meta}
            )
            return "INSERT 0 1"
        raise AssertionError(f"unexpected execute: {s}")

    async def fetchrow(self, sql: str, *args):
        s = self._norm(sql)
        if "from public.credits" in s and "for update" in s:
            return dict(self.credits)
        if "from public.credit_transactions" in s and "reason = 'spend'" in s:
            for t in self.txns:
                if t["ref"] == args[1] and t["reason"] == "spend":
                    return {"delta": t["delta"], "meta": t["meta"]}
            return None
        raise AssertionError(f"unexpected fetchrow: {s}")

    async def fetchval(self, sql: str, *args):
        s = self._norm(sql)
        if "select 1 from public.credit_transactions" in s:
            return 1 if any(t["ref"] == args[1] for t in self.txns) else None
        raise AssertionError(f"unexpected fetchval: {s}")


def test_reserve_debits_standard_one() -> None:
    conn = _FakeConn(balance=10, daily_free_used=999, topup_balance=0)
    state = asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-std"))
    assert state.balance == 9
    assert conn.txns[-1]["meta"] == {"free": 0, "balance": 1, "topup": 0}


def test_reserve_debits_hd_four_and_records_split() -> None:
    # 1 free + 1 plan + 2 top-up covers a cost-4 HD render.
    conn = _FakeConn(balance=1, daily_free_used=2, topup_balance=5)
    state = asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job-hd"))
    assert (state.balance, state.topup_balance, state.daily_free_used) == (0, 3, 3)
    assert conn.txns[-1]["meta"] == {"free": 1, "balance": 1, "topup": 2}


def test_reserve_is_idempotent_per_job() -> None:
    conn = _FakeConn(balance=10, daily_free_used=999, topup_balance=0)
    s1 = asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job"))
    n = len(conn.txns)
    s2 = asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job"))  # replay
    assert s1.balance == s2.balance == 6
    assert len(conn.txns) == n  # no second debit


def test_reserve_never_goes_negative_under_pressure() -> None:
    # Two HD submits, only 4 credits: the first reserves, the second is rejected
    # and the balance never goes below zero (the parallel/double-submit guard).
    conn = _FakeConn(balance=4, daily_free_used=999, topup_balance=0)
    asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job-1"))
    assert conn.credits["balance"] == 0
    with pytest.raises(InsufficientCreditsError):
        asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job-2"))
    assert conn.credits["balance"] == 0


def test_refund_restores_the_exact_buckets() -> None:
    conn = _FakeConn(balance=1, daily_free_used=2, topup_balance=5)
    asyncio.run(spend_credit(conn, "u", cost=HD_COST, ref="job"))
    assert conn.credits == {"balance": 0, "daily_free_used": 3, "topup_balance": 3}

    assert asyncio.run(refund_credit(conn, "u", ref="job")) is True
    assert conn.credits == {"balance": 1, "daily_free_used": 2, "topup_balance": 5}

    # Idempotent: a second refund is a no-op, balance unchanged.
    assert asyncio.run(refund_credit(conn, "u", ref="job")) is False
    assert conn.credits == {"balance": 1, "daily_free_used": 2, "topup_balance": 5}


def test_refund_noop_when_nothing_was_reserved() -> None:
    conn = _FakeConn(balance=5, daily_free_used=0, topup_balance=0)
    assert asyncio.run(refund_credit(conn, "u", ref="never-charged")) is False
    assert conn.credits["balance"] == 5
