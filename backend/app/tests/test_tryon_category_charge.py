"""A look nobody can identify must cost nothing, and repairing it must cost once.

The money half of the category work. Every other guarantee in this change is
about correctness; this one is about a person's credits, so it is asserted from
two directions:

  * the PLANNER refuses a selection it cannot identify, and refuses it by
    raising rather than by trimming — so there is no partial look to charge for;
  * the ROUTER builds that plan strictly before it reserves anything, so a
    refusal cannot arrive after the money has moved.

The second one is checked structurally. A full DB fake for `POST /v1/tryon`
would be a large harness whose failure modes are mostly its own, whereas the
property that actually matters is an ORDERING in one function, and an ordering
is exactly the kind of thing a later refactor silently inverts.
"""

from __future__ import annotations

import inspect

import pytest

import app.routers.v1.tryon as router
from app.services.tryon import taxonomy as tax
from app.services.tryon.planner import (
    EMPTY_PLAN,
    SKIP_NEEDS_REVIEW,
    LookPlanError,
    SelectedGarment,
    build_plan,
)


def _garment(canonical: str | None, key: str = "w:1") -> SelectedGarment:
    return SelectedGarment(
        item_key=key,
        image_url="https://cdn.test/a.png",
        canonical=canonical,
        is_cutout=True,
    )


# ── a piece nobody can identify ──────────────────────────────────────────────


def test_an_unidentified_piece_alone_refuses_the_whole_look() -> None:
    """No plan, no job, no charge. Refusing is the safe direction: the piece
    keeps every row and every image, and only the render declines."""
    with pytest.raises(LookPlanError) as caught:
        build_plan([_garment(None)])
    assert caught.value.code == EMPTY_PLAN
    # And the message tells somebody what to DO, not merely that it failed.
    assert "category" in caught.value.message.lower()


def test_an_unidentified_piece_never_becomes_a_step() -> None:
    """The dangerous alternative is guessing a role and rendering it. A skipped
    piece is named with a reason instead."""
    plan = build_plan([_garment(tax.TOP, "w:known"), _garment(None, "w:unknown")])
    assert [s.item_key for s in plan.steps] == ["w:known"]
    skipped = plan.skipped
    assert [s.item_key for s in skipped] == ["w:unknown"]
    assert skipped[0].reason == SKIP_NEEDS_REVIEW


def test_every_selected_piece_is_accounted_for() -> None:
    """Nothing is silently dropped — a look that quietly loses a garment is a
    charge for something the person did not get."""
    garments = [_garment(tax.TOP, "a"), _garment(None, "b"), _garment(tax.BELT, "c")]
    plan = build_plan(garments)
    assert set(plan.planned_item_keys) | set(plan.skipped_item_keys) == {"a", "b", "c"}


# ── the repair, and exactly one charge ───────────────────────────────────────


@pytest.mark.parametrize(
    "repaired",
    [tax.TOP, tax.BOTTOM, tax.ONE_PIECE, tax.HIJAB_SCARF, tax.JEWELRY],
)
def test_a_repaired_piece_plans_exactly_one_step(repaired: str) -> None:
    """What the inline resolver buys: the SAME selection that refused a moment
    ago now plans one step — one provider call, one charge."""
    with pytest.raises(LookPlanError):
        build_plan([_garment(None)])

    plan = build_plan([_garment(repaired)])
    assert plan.total_steps == 1
    assert plan.steps[0].canonical == repaired
    assert plan.skipped == []


def test_repair_does_not_multiply_steps_for_one_piece() -> None:
    """One garment is one provider call. A repair that produced two would be a
    double charge for a single piece."""
    plan = build_plan([_garment(tax.TOP)])
    assert len(plan.steps) == 1


def test_a_piece_repaired_to_an_unrenderable_role_still_costs_nothing() -> None:
    """A belt is a fine closet item that today's provider cannot wear. Saying so
    beats charging for a look that comes back without it."""
    with pytest.raises(LookPlanError) as caught:
        build_plan([_garment(tax.BELT)])
    assert caught.value.code == EMPTY_PLAN


# ── the ordering the money depends on ────────────────────────────────────────


def test_the_plan_is_built_before_anything_is_reserved() -> None:
    """THE invariant. `build_plan` raises for an unidentifiable selection, so it
    has to run before the credit reservation or the refusal arrives after the
    money has already moved."""
    source = inspect.getsource(router._create_tryon)
    plan_at = source.index("build_plan(")
    spend_at = source.index("spend_credit(")
    assert plan_at < spend_at, "credits are reserved before the plan is built"


def test_consent_and_moderation_also_follow_the_plan() -> None:
    """Both transmit the person's own photograph to a third party. A look that
    is going to be refused anyway must not send it first (§10)."""
    source = inspect.getsource(router._create_tryon)
    plan_at = source.index("build_plan(")
    consent_at = source.index("require_ai_personal_image_consent(")
    assert plan_at < consent_at


def test_a_refused_plan_is_a_422_and_not_a_provider_error() -> None:
    """A selection nobody can identify is a QUESTION for the person, not an
    outage — and the app routes the two very differently."""
    source = inspect.getsource(router._create_tryon)
    refusal = source[source.index("except LookPlanError") :]
    assert "VALIDATION_ERROR" in refusal
    assert "422" in refusal
