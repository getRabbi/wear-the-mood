"""Try Look planning + full-look accounting (spec Phases 6/7/8/9/10, matrix §22).

The three production symptoms this file is the regression guard for:

  1. a single top rendered as a full outfit  -> explicit categories, never `auto`;
  2. a four-piece Full Look returning one shirt -> every selected piece is either
     a planned step or a recorded skip, and success requires all of them;
  3. an earlier garment vanishing under a later pass -> apparel before
     accessories, chained, with the provider's preservation prompt.
"""

from __future__ import annotations

import json

import pytest

from app.services.tryon import routing
from app.services.tryon import taxonomy as tax
from app.services.tryon.execution import ExecutedLook, LookIncompleteError, plan_steps_for
from app.services.tryon.planner import (
    CONFLICT_DUPLICATE_ROLE,
    CONFLICT_ONE_PIECE,
    EMPTY_PLAN,
    SKIP_NEEDS_REVIEW,
    SKIP_UNSUPPORTED,
    LookPlanError,
    SelectedGarment,
    build_plan,
)


def g(key: str, canonical: str | None, **kw: object) -> SelectedGarment:
    return SelectedGarment(
        item_key=key, image_url=f"https://cdn.test/{key}.jpg", canonical=canonical, **kw
    )


# ── single item (spec Phase 22, "Single item") ───────────────────────────────


@pytest.mark.parametrize(
    ("canonical", "fashn_category"),
    [(tax.TOP, "tops"), (tax.BOTTOM, "bottoms"), (tax.ONE_PIECE, "one-pieces")],
)
def test_single_garment_uses_its_explicit_category(canonical: str, fashn_category: str) -> None:
    plan = build_plan([g("x", canonical)])
    assert plan.total_steps == 1
    step = plan.steps[0]
    assert step.model_name == routing.APPAREL_MODEL
    assert step.category == fashn_category
    assert step.category != "auto"


def test_a_cutout_declares_flat_lay_and_a_raw_photo_does_not() -> None:
    cutout = build_plan([g("a", tax.TOP, is_cutout=True)]).steps[0]
    photo = build_plan([g("b", tax.TOP, is_cutout=False)]).steps[0]
    assert cutout.garment_photo_type == routing.PHOTO_TYPE_FLAT_LAY
    assert photo.garment_photo_type == routing.PHOTO_TYPE_AUTO


# ── full look ordering (spec Phases 6/8) ─────────────────────────────────────


def test_four_piece_look_plans_every_piece_in_render_order() -> None:
    """THE headline case: shirt + pants + hijab + glasses.

    Selection order is deliberately scrambled — the plan must not depend on
    which chip the user tapped first.
    """
    plan = build_plan(
        [
            g("glasses", tax.GLASSES),
            g("shirt", tax.TOP),
            g("hijab", tax.HIJAB_SCARF),
            g("pants", tax.BOTTOM),
        ]
    )
    assert plan.planned_item_keys == ["pants", "shirt", "hijab", "glasses"]
    assert plan.skipped == []
    assert plan.total_steps == 4
    # Apparel on the apparel model with explicit regions...
    assert [s.model_name for s in plan.steps[:2]] == [routing.APPAREL_MODEL] * 2
    assert [s.category for s in plan.steps[:2]] == ["bottoms", "tops"]
    # ...accessories on the accessory model, with preservation prompts.
    assert [s.model_name for s in plan.steps[2:]] == [routing.ACCESSORY_MODEL] * 2
    assert all(s.prompt for s in plan.steps[2:])


def test_tap_order_only_breaks_ties_within_one_role_group() -> None:
    a = build_plan([g("shoes", tax.SHOES), g("bag", tax.BAG)])
    b = build_plan([g("bag", tax.BAG), g("shoes", tax.SHOES)])
    # shoes render before bags regardless of tap order.
    assert a.planned_item_keys == b.planned_item_keys == ["shoes", "bag"]


@pytest.mark.parametrize(
    "combo",
    [
        [tax.TOP, tax.BOTTOM],
        [tax.TOP, tax.BOTTOM, tax.HIJAB_SCARF],
        [tax.TOP, tax.BOTTOM, tax.GLASSES],
        [tax.TOP, tax.BOTTOM, tax.HIJAB_SCARF, tax.GLASSES],
        [tax.ONE_PIECE, tax.HIJAB_SCARF],
        [tax.ONE_PIECE, tax.GLASSES],
        [tax.TOP, tax.BOTTOM, tax.OUTERWEAR],
    ],
)
def test_supported_combinations_plan_completely(combo: list[str]) -> None:
    plan = build_plan([g(f"i{n}", c) for n, c in enumerate(combo)])
    assert len(plan.steps) == len(combo)
    assert plan.skipped == []


# ── conflicts (spec Phase 10) ────────────────────────────────────────────────


def test_two_pieces_for_the_same_region_are_refused() -> None:
    with pytest.raises(LookPlanError) as err:
        build_plan([g("a", tax.TOP), g("b", tax.TOP)])
    assert err.value.code == CONFLICT_DUPLICATE_ROLE
    assert "upper body" in err.value.message


@pytest.mark.parametrize("part", [tax.TOP, tax.BOTTOM])
def test_one_piece_cannot_share_a_look_with_separates(part: str) -> None:
    with pytest.raises(LookPlanError) as err:
        build_plan([g("dress", tax.ONE_PIECE), g("other", part)])
    assert err.value.code == CONFLICT_ONE_PIECE


def test_a_conflict_is_refused_rather_than_silently_trimmed() -> None:
    """Dropping one of the two would render an outfit the user did not choose,
    and charge them for it."""
    with pytest.raises(LookPlanError):
        build_plan([g("a", tax.BOTTOM), g("b", tax.BOTTOM), g("c", tax.TOP)])


def test_a_whole_look_reference_conflicts_with_separate_clothing() -> None:
    with pytest.raises(LookPlanError) as err:
        build_plan([g("post", tax.LOOK_REFERENCE), g("shirt", tax.TOP)])
    assert err.value.code == CONFLICT_ONE_PIECE
    assert "full outfit" in err.value.message


# ── accounting: nothing is dropped silently (spec Phases 7/29) ───────────────


def test_an_unknown_piece_is_skipped_with_a_reason_not_guessed() -> None:
    plan = build_plan([g("shirt", tax.TOP), g("mystery", None)])
    assert plan.planned_item_keys == ["shirt"]
    assert [(s.item_key, s.reason) for s in plan.skipped] == [("mystery", SKIP_NEEDS_REVIEW)]
    assert "category" in plan.skipped[0].message


def test_an_unsupported_piece_is_skipped_with_its_own_reason() -> None:
    plan = build_plan([g("shirt", tax.TOP), g("belt", tax.BELT)])
    assert plan.planned_item_keys == ["shirt"]
    assert [(s.item_key, s.reason) for s in plan.skipped] == [("belt", SKIP_UNSUPPORTED)]


def test_every_selected_piece_is_either_planned_or_skipped() -> None:
    """The invariant, stated directly. There is no third outcome."""
    selected = [g("a", tax.TOP), g("b", tax.BELT), g("c", None), g("d", tax.SHOES)]
    plan = build_plan(selected)
    assert set(plan.planned_item_keys) | set(plan.skipped_item_keys) == {
        s.item_key for s in selected
    }
    assert not set(plan.planned_item_keys) & set(plan.skipped_item_keys)


def test_a_look_with_nothing_renderable_fails_rather_than_returning_the_photo() -> None:
    with pytest.raises(LookPlanError) as err:
        build_plan([g("mystery", None)])
    assert err.value.code == EMPTY_PLAN


def test_too_many_pieces_is_refused() -> None:
    with pytest.raises(LookPlanError):
        build_plan([g(f"i{n}", tax.TOP) for n in range(7)])


# ── the legacy escape hatch is recorded, not invisible ───────────────────────


def test_legacy_url_only_requests_keep_working_and_are_marked() -> None:
    """An already-shipped client sends bare URLs. Refusing would break every
    installed app; guessing invisibly is what we are fixing. So: same behaviour
    as before, recorded as `auto` on the job."""
    plan = build_plan([g("legacy", None, allow_auto_fallback=True)])
    assert plan.total_steps == 1
    assert plan.steps[0].category == "auto"
    assert plan.skipped == []


def test_strict_mode_removes_the_escape_hatch() -> None:
    with pytest.raises(LookPlanError):
        build_plan([g("legacy", None, allow_auto_fallback=False)])


def test_a_legacy_auto_step_is_excluded_from_conflict_checks() -> None:
    """We do not know what it is, so we cannot claim it clashes with anything —
    and inventing a clash would refuse a look that used to work."""
    plan = build_plan([g("legacy", None, allow_auto_fallback=True), g("shirt", tax.TOP)])
    assert len(plan.steps) == 2


# ── the stored plan carries no credential ────────────────────────────────────


def test_the_stored_plan_contains_no_image_url() -> None:
    """A plan is a durable record; a presigned URL is an expiring credential
    (§11). The images live on the job's own stack and are re-signed at run time."""
    plan = build_plan([g("shirt", tax.TOP), g("glasses", tax.GLASSES)])
    blob = json.dumps(plan.as_json())
    assert "https://" not in blob
    assert "cdn.test" not in blob
    # ...and the prompt text is not frozen into it either, so a wording fix
    # reaches a job that recovery re-runs later.
    assert "Keep the person" not in blob
    assert json.loads(blob)["steps"][1]["has_prompt"] is True


# ── executing the plan (spec Phase 8) ────────────────────────────────────────


def _job(plan_json: dict | None, stack: list[str]) -> dict:
    return {
        "plan": json.dumps(plan_json) if plan_json else None,
        "garment_image_urls": stack,
        "garment_image_url": stack[0] if stack else None,
    }


def test_steps_pair_with_the_job_stack_in_plan_order() -> None:
    plan = build_plan([g("glasses", tax.GLASSES), g("shirt", tax.TOP)])
    job = _job(plan.as_json(), plan.image_stack())
    steps = plan_steps_for(job)
    assert [s.item_key for s in steps] == ["shirt", "glasses"]
    assert [s.image_url for s in steps] == plan.image_stack()
    # The accessory prompt is rehydrated from the CURRENT routing table.
    assert steps[1].prompt == routing.route_for(tax.GLASSES).prompt


def test_a_pre_plan_job_still_runs_the_way_it_always_did() -> None:
    """A row stranded across the deploy must not die."""
    steps = plan_steps_for(_job(None, ["a", "b"]))
    assert [s.category for s in steps] == ["auto", "auto"]
    assert [s.canonical for s in steps] == ["legacy_auto", "legacy_auto"]
    assert [s.model_name for s in steps] == [routing.APPAREL_MODEL] * 2


def test_a_complete_look_passes_the_invariant() -> None:
    look = ExecutedLook(planned=["a", "b"])
    for key in ("a", "b"):
        look.applied.append(key)
    look.require_complete()  # does not raise


def test_a_partial_look_is_a_failure_not_a_result() -> None:
    """The four-pieces-in, one-shirt-out case. It must never reach the user as a
    finished render."""
    look = ExecutedLook(planned=["shirt", "pants", "hijab", "glasses"])
    look.applied.append("shirt")
    with pytest.raises(LookIncompleteError) as err:
        look.require_complete()
    assert err.value.missing == ["pants", "hijab", "glasses"]


def test_step_state_records_which_step_failed_and_how_hard_it_tried() -> None:
    plan = build_plan([g("shirt", tax.TOP), g("glasses", tax.GLASSES)])
    steps = plan_steps_for(_job(plan.as_json(), plan.image_stack()))
    look = ExecutedLook(planned=plan.planned_item_keys)
    look.record_success(steps[0], attempts=1, duration_ms=8000)
    look.record_failure(steps[1], attempts=3, duration_ms=25000)
    assert look.applied == ["shirt"]
    assert look.failed == ["glasses"]
    assert look.step_state["1"]["status"] == "failed"
    assert look.step_state["1"]["attempts"] == 3
    assert look.step_state["1"]["model"] == routing.ACCESSORY_MODEL
    with pytest.raises(LookIncompleteError):
        look.require_complete()
