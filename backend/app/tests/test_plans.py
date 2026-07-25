"""Plan config reads (credits come from the plans table, never hardcoded)."""

from __future__ import annotations

import asyncio

from app.core.plans import FREE_PLAN, HD_COST, STD_COST, get_plan, plan_for_product


class _Conn:
    def __init__(self, row=None) -> None:
        self.row = row

    async def fetchrow(self, sql, *a):
        return self.row


class _SeedConn:
    """Arg-aware fake: returns a plan row ONLY when the queried product id exactly
    matches a seeded (bare) play/app id — mirrors the real `where play_product_id
    = $1 or app_product_id = $1`. Lets us prove the colon-form normalization."""

    _SEED = {
        "pro_monthly": {
            "tier": "pro",
            "kind": "subscription",
            "monthly_credits": 75,
            "hd_allowed": False,
            "priority": False,
        },
        "pro_max_monthly": {
            "tier": "pro_max",
            "kind": "subscription",
            "monthly_credits": 150,
            "hd_allowed": True,
            "priority": True,
        },
        "topup_40": {
            "tier": "topup_40",
            "kind": "topup",
            "monthly_credits": 40,
            "hd_allowed": False,
            "priority": False,
        },
    }

    def __init__(self) -> None:
        self.queried: list[str] = []

    async def fetchrow(self, sql, *a):
        product_id = a[0]
        self.queried.append(product_id)
        return self._SEED.get(product_id)


def test_costs_are_one_and_four() -> None:
    assert STD_COST == 1 and HD_COST == 4


def test_get_plan_from_row() -> None:
    p = asyncio.run(
        get_plan(
            _Conn(
                {
                    "tier": "pro_max",
                    "kind": "subscription",
                    "monthly_credits": 150,
                    "hd_allowed": True,
                    "priority": True,
                }
            ),
            "pro_max",
        )
    )
    assert p.tier == "pro_max" and p.monthly_credits == 150 and p.hd_allowed is True


def test_get_plan_unknown_is_free() -> None:
    p = asyncio.run(get_plan(_Conn(None), "nope"))
    assert p == FREE_PLAN and p.monthly_credits == 0 and p.hd_allowed is False


def test_plan_for_product_none_when_unknown() -> None:
    assert asyncio.run(plan_for_product(_Conn(None), "")) is None
    assert asyncio.run(plan_for_product(_Conn(None), "mystery")) is None


def test_plan_for_product_maps() -> None:
    p = asyncio.run(
        plan_for_product(
            _Conn(
                {
                    "tier": "pro",
                    "kind": "subscription",
                    "monthly_credits": 75,
                    "hd_allowed": False,
                    "priority": False,
                }
            ),
            "pro_monthly",
        )
    )
    assert p is not None and p.tier == "pro" and p.monthly_credits == 75


# ── Google Play subscription:base-plan id normalization (RevenueCat sends
#    "pro_monthly:monthly"; the plans seed stores the bare "pro_monthly"). ──


def test_colon_form_pro_maps_to_pro_75() -> None:
    conn = _SeedConn()
    p = asyncio.run(plan_for_product(conn, "pro_monthly:monthly"))
    assert p is not None and p.tier == "pro" and p.monthly_credits == 75
    # Tried the exact colon id first, then fell back to the bare base id.
    assert conn.queried == ["pro_monthly:monthly", "pro_monthly"]


def test_colon_form_pro_max_maps_to_pro_max_150() -> None:
    p = asyncio.run(plan_for_product(_SeedConn(), "pro_max_monthly:monthly"))
    assert p is not None and p.tier == "pro_max" and p.monthly_credits == 150
    assert p.hd_allowed is True


def test_bare_ids_still_match_exactly_without_stripping() -> None:
    # A bare id (topup in-app, or a store that omits the base plan) matches on
    # the first exact query — the colon fallback never runs.
    conn = _SeedConn()
    p = asyncio.run(plan_for_product(conn, "topup_40"))
    assert p is not None and p.kind == "topup" and p.monthly_credits == 40
    assert conn.queried == ["topup_40"]


def test_topup_colon_never_false_matches_a_subscription() -> None:
    # A genuinely unknown colon id must NOT map to any plan (no accidental base
    # collision) — proves the fallback only strips, never guesses.
    assert asyncio.run(plan_for_product(_SeedConn(), "mystery:base")) is None
