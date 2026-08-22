"""One tap costs one credit, and a tap that fails costs nothing.

The whole user-facing credit contract, asserted in one place.

What it took to satisfy a render — HD, six garments chained through six provider
calls, a fallback model after the first refused, a worker that restarted halfway,
a poll that replayed — is OUR production cost. None of it is a second thing to
bill somebody for. The previous prices (HD = 4, AI Enhance = 4) leaked the
provider's cost structure onto the person paying, so the same button charged 1 or
4 depending on a toggle most people would never connect to the number.

The cap is deliberately enforced at three depths, and each has its own test here:

  1. the compiled constants,
  2. `build_credit_policy`, which clamps operator config and the v2 tier table,
  3. `spend_credit`, which refuses to debit more than the cap whatever reaches it.

Anything that gets around one of them still meets the next.
"""

from __future__ import annotations

import asyncio
import inspect
import json
import uuid

import pytest

import app.routers.v1.ai_studio as ai_studio
import app.routers.v1.tryon as tryon_router
from app.core.config import get_settings
from app.core.credits import refund_credit, spend_credit
from app.core.monetization import RENDER_QUALITIES, build_credit_policy
from app.core.plans import (
    AI_ENHANCE_COST,
    HD_COST,
    MAX_APP_CREDITS_PER_RENDER,
    STD_COST,
)

# ── the fake ledger ──────────────────────────────────────────────────────────


class _Conn:
    """An in-memory `credits` row plus its transaction log."""

    def __init__(self, *, balance: int = 0, free_used: int = 0, topup: int = 0) -> None:
        self.credits = {
            "balance": balance,
            "daily_free_used": free_used,
            "topup_balance": topup,
        }
        self.txns: list[dict] = []

    def transaction(self):
        return _Tx()

    async def execute(self, sql: str, *args: object) -> str:
        flat = " ".join(sql.split())
        if "update public.credits set balance" in flat:
            self.credits = {
                "balance": args[1],
                "daily_free_used": args[2],
                "topup_balance": args[3],
            }
        elif "insert into public.credit_transactions" in flat:
            self.txns.append(
                {
                    "delta": args[1],
                    "reason": "spend" if args[1] < 0 else "refund",
                    "ref": args[3],
                    "meta": json.loads(args[5]) if args[5] else None,
                }
            )
        return "OK"

    async def fetchrow(self, sql: str, *args: object):
        flat = " ".join(sql.split())
        if "select balance, daily_free_used, topup_balance" in flat:
            return dict(self.credits)
        if "select delta, meta from public.credit_transactions" in flat:
            for t in self.txns:
                if t["ref"] == args[1] and t["reason"] == "spend":
                    return {"delta": t["delta"], "meta": json.dumps(t["meta"])}
            return None
        return None

    async def fetchval(self, sql: str, *args: object):
        flat = " ".join(sql.split())
        if "from public.credit_transactions where user_id" in flat:
            return 1 if any(t["ref"] == args[1] for t in self.txns) else None
        return None

    @property
    def net(self) -> int:
        """What this user was charged, all in."""
        return -sum(t["delta"] for t in self.txns)


class _Tx:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *a: object) -> bool:
        return False


@pytest.fixture(autouse=True)
def _known_free_allowance(monkeypatch: pytest.MonkeyPatch):
    """Pin the allowance so these tests are about PRICE, not about generosity."""
    monkeypatch.setenv("FREE_TRYON_TRIAL_CREDITS", "3")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


# ── depth 1: the compiled prices ─────────────────────────────────────────────


def test_every_compiled_price_is_one() -> None:
    assert STD_COST == HD_COST == AI_ENHANCE_COST == MAX_APP_CREDITS_PER_RENDER == 1


# ── depth 2: the policy layer ────────────────────────────────────────────────


@pytest.mark.parametrize("v2", [False, True])
@pytest.mark.parametrize("quality", RENDER_QUALITIES)
def test_no_quality_tier_can_cost_more_than_one(v2: bool, quality: str) -> None:
    policy = build_credit_policy({}, v2=v2)
    assert policy.tryon_cost(hd=True, quality=quality) <= MAX_APP_CREDITS_PER_RENDER


@pytest.mark.parametrize("key", ["render_cost_standard", "render_cost_hd", "render_cost_enhance"])
def test_an_operator_cannot_price_a_render_above_the_cap(key: str) -> None:
    """A database row nobody reviewed must not be able to outprice the promise."""
    policy = build_credit_policy({key: 99}, v2=False)
    assert policy.tryon_cost(hd=False) <= 1
    assert policy.tryon_cost(hd=True) <= 1
    assert policy.premium_ai_cost(hd=False, enhance=True) <= 1


def test_an_operator_may_still_make_a_render_free() -> None:
    """The clamp is a ceiling, not a fixed price — a promotion still works."""
    policy = build_credit_policy({"render_cost_standard": 0}, v2=False)
    assert policy.tryon_cost(hd=False) == 0


# ── depth 3: the debit itself ────────────────────────────────────────────────


@pytest.mark.parametrize("requested", [2, 4, 8, 100])
def test_a_debit_above_the_cap_is_clamped(requested: int) -> None:
    conn = _Conn(balance=200)
    asyncio.run(spend_credit(conn, "u", cost=requested, ref="job"))
    assert conn.net == MAX_APP_CREDITS_PER_RENDER
    assert len(conn.txns) == 1


def test_a_successful_render_charges_exactly_one() -> None:
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    assert conn.net == 1
    assert conn.credits["balance"] == 9


# ── retries, replays and restarts: still one ─────────────────────────────────


def test_a_double_tap_charges_once() -> None:
    """Two submits of the SAME logical render — the job id is the billing
    identity, so the second is a no-op rather than a second debit."""
    conn = _Conn(balance=10, free_used=999)
    for _ in range(2):
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-1"))
    assert conn.net == 1
    assert len(conn.txns) == 1


def test_an_api_replay_charges_once() -> None:
    conn = _Conn(balance=10, free_used=999)
    for _ in range(5):  # client retry, poll, webhook replay, worker restart…
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-1"))
    assert conn.net == 1


def test_a_multi_stage_render_charges_once() -> None:
    """Six garments chained through six provider calls is ONE render.

    The worker reserves against the job id once and then executes as many
    provider steps as the plan needs; the steps are our cost, not the user's.
    """
    conn = _Conn(balance=10, free_used=999)
    job = "look-1"
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref=job))
    for _step in range(6):  # each chained provider call
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref=job))
    assert conn.net == 1


def test_a_fallback_model_does_not_add_a_charge() -> None:
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))  # after fallback
    assert conn.net == 1


# ── failure leaves the user whole ────────────────────────────────────────────


def test_a_failed_render_nets_zero() -> None:
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    assert asyncio.run(refund_credit(conn, "u", ref="job")) is True
    assert conn.net == 0
    assert conn.credits["balance"] == 10


def test_a_refund_happens_at_most_once() -> None:
    """A worker that retries its own failure handling must not pay twice."""
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    assert asyncio.run(refund_credit(conn, "u", ref="job")) is True
    for _ in range(3):
        assert asyncio.run(refund_credit(conn, "u", ref="job")) is False
    assert conn.net == 0
    assert conn.credits["balance"] == 10


def test_a_refund_returns_to_the_exact_bucket() -> None:
    """Free credits must not launder into paid ones, in either direction."""
    conn = _Conn(balance=5, free_used=0, topup=5)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    assert conn.txns[0]["meta"] == {"free": 1, "balance": 0, "topup": 0}
    asyncio.run(refund_credit(conn, "u", ref="job"))
    assert conn.credits == {"balance": 5, "daily_free_used": 0, "topup_balance": 5}


def test_a_retry_after_a_refund_is_a_new_render_and_costs_one() -> None:
    """Explicitly retrying is a new logical request — and only one credit."""
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-1"))
    asyncio.run(refund_credit(conn, "u", ref="job-1"))
    assert conn.net == 0
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-2"))
    assert conn.net == 1


def test_a_success_is_never_refunded_by_a_lost_response() -> None:
    """Losing the response is a client problem; the render exists and is
    retrievable, so the charge stands and the replay does not add another."""
    conn = _Conn(balance=10, free_used=999)
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))
    asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job"))  # client retried
    assert conn.net == 1
    assert len(conn.txns) == 1


# ── the free lifetime allowance ──────────────────────────────────────────────


def test_three_lifetime_free_renders_then_the_paywall() -> None:
    """Three, and the fourth is refused — with no partial charge for it."""
    from app.core.credits import InsufficientCreditsError

    conn = _Conn(balance=0, free_used=0, topup=0)
    for n in range(3):
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref=f"job-{n}"))
    assert conn.credits["daily_free_used"] == 3
    assert conn.net == 3

    with pytest.raises(InsufficientCreditsError):
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="job-4"))
    assert conn.net == 3, "the blocked fourth render charged nothing"


def test_the_free_allowance_does_not_reset() -> None:
    """Lifetime, not daily. `daily_free_used` keeps its historical column name;
    nothing decrements it."""
    conn = _Conn(balance=0, free_used=3)
    from app.core.credits import InsufficientCreditsError

    with pytest.raises(InsufficientCreditsError):
        asyncio.run(spend_credit(conn, "u", cost=STD_COST, ref="tomorrow"))
    assert conn.net == 0


# ── nothing is charged before it is earned ───────────────────────────────────


def _order(fn) -> list[str]:
    src = inspect.getsource(fn)
    marks = {
        "category/plan": "build_plan(",
        "consent": "require_ai_personal_image_consent(",
        "moderation": "_moderate_",
        "debit": "spend_credit(",
    }
    found = sorted((src.index(needle), label) for label, needle in marks.items() if needle in src)
    return [label for _position, label in found]


def test_nothing_is_charged_before_the_plan_consent_and_moderation() -> None:
    """The order IS the guarantee for half the matrix at once.

    A refusal for a missing category, missing consent or a moderation block can
    only cost zero if it happens before the debit — so this asserts the sequence
    rather than mocking four separate refusals and hoping the ordering holds.
    """
    assert _order(tryon_router._create_tryon) == [
        "category/plan",
        "consent",
        "moderation",
        "debit",
    ]


def test_ai_studio_reserves_only_after_entitlement_and_ownership() -> None:
    src = inspect.getsource(ai_studio._create_ai_job)
    assert src.index("_assert_owns_item(") < src.index("spend_credit(")
    assert src.index("authorize_premium_ai(") < src.index("spend_credit(")
    # And an in-flight job is handed back rather than reserved against again.
    assert src.index("_job_in_flight(") < src.index("spend_credit(")


def test_a_failed_job_is_refunded_by_the_worker() -> None:
    """Both workers own the reversal, so a provider failure cannot leave a hold."""
    import app.workers.ai_jobs_worker as ai_worker
    import app.workers.tryon_worker as tryon_worker

    for module in (ai_worker, tryon_worker):
        assert "refund_credit(" in inspect.getsource(module)


def test_the_billing_identity_is_the_job_id() -> None:
    """One server-minted id per user-visible render, attached to every attempt.

    Not the idempotency key: a client picks that, and a client that picks a new
    one for a retry would otherwise buy a second render by accident.
    """
    sig = inspect.signature(spend_credit)
    assert "ref" in sig.parameters
    src = inspect.getsource(tryon_router._create_tryon)
    assert "ref=str(job_id)" in src
    assert "ref=idempotency_key" not in src


def test_ai_studio_also_bills_against_its_job_id() -> None:
    src = inspect.getsource(ai_studio._create_ai_job)
    assert "ref=str(job_id)" in src
    assert uuid.UUID  # imported for the reader; the ids are uuids server-side
