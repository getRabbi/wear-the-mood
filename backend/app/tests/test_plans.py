"""Plan config reads (credits come from the plans table, never hardcoded)."""

from __future__ import annotations

import asyncio

from app.core.plans import FREE_PLAN, HD_COST, STD_COST, get_plan, plan_for_product


class _Conn:
    def __init__(self, row=None) -> None:
        self.row = row

    async def fetchrow(self, sql, *a):
        return self.row


def test_costs_are_one_and_four() -> None:
    assert STD_COST == 1 and HD_COST == 4


def test_get_plan_from_row() -> None:
    p = asyncio.run(
        get_plan(
            _Conn({"tier": "pro_max", "kind": "subscription", "monthly_credits": 150,
                   "hd_allowed": True, "priority": True}),
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
            _Conn({"tier": "pro", "kind": "subscription", "monthly_credits": 75,
                   "hd_allowed": False, "priority": False}),
            "pro_monthly",
        )
    )
    assert p is not None and p.tier == "pro" and p.monthly_credits == 75
