"""Executing a stored Try Look plan, and proving the look is complete (Phase 7/8).

The planner decides WHAT a look is; this module is what the worker uses to run it
and what forbids the worker from calling a partial look a success.

Two things live here on purpose:

* `plan_steps_for` rehydrates the plan a job was created with, pairing each
  planned step with its (freshly signed) image from the job's own stack. It also
  understands a job created BEFORE plans existed, so a row stranded across the
  deploy still runs instead of dying.
* `ExecutedLook` is the accounting. Every step either lands in `applied` or in
  `failed`; `require_complete()` is the single gate between "the chain finished"
  and "the job may be marked done".
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from app.services.tryon import routing


class LookIncompleteError(RuntimeError):
    """A look finished its chain without applying every planned garment.

    Raised so the job takes the ordinary FAILURE path — marked failed, credits
    refunded, the user told. Returning the half-rendered image instead would be
    the exact behaviour this whole change exists to remove: a four-piece
    selection coming back as one shirt, reported as success, and charged for.
    """

    def __init__(self, missing: list[str]) -> None:
        super().__init__(f"look incomplete: {len(missing)} garment(s) not applied")
        self.missing = missing


@dataclass(frozen=True)
class ExecutableStep:
    """One planned step paired with the image the worker will actually send."""

    index: int
    item_key: str
    canonical: str
    model_name: str
    image_url: str
    category: str | None = None
    prompt: str | None = None
    garment_photo_type: str = routing.PHOTO_TYPE_AUTO

    def to_request(self, *, person_image: str, is_final: bool) -> object:
        from app.services.tryon.base import RenderRequest

        return RenderRequest(
            person_image=person_image,
            garment_image=self.image_url,
            model_name=self.model_name,
            category=self.category,
            prompt=self.prompt,
            garment_photo_type=self.garment_photo_type,
            is_final=is_final,
        )


def _prompt_for(canonical: str) -> str | None:
    """Re-derive the accessory preservation prompt from the CURRENT routing table.

    Plans store `has_prompt`, not the prompt text. A prompt is tuning, and a job
    re-run by recovery an hour after a wording fix should get the fixed wording —
    while the ROLE it was planned with, which is a decision about the user's
    selection, stays exactly as it was recorded.
    """
    route = routing.route_for(canonical)
    return route.prompt if route else None


def plan_steps_for(job: object) -> list[ExecutableStep]:
    """The ordered steps to run for this job.

    Images come from `garment_image_urls`, which the submit endpoint writes in
    PLAN order and the worker re-signs fresh — so the plan never has to store a
    credential, and a job recovered hours later still resolves its own images.
    """
    stack: list[str] = list(job["garment_image_urls"] or [])
    if not stack and job["garment_image_url"]:
        stack = [job["garment_image_url"]]

    raw_plan = job["plan"] if "plan" in job else None
    steps = _parse_steps(raw_plan)

    if not steps:
        # PRE-PLAN JOB (created before 0069, or by a path that predates it). It
        # has URLs and nothing else, so it runs the way it always did — one
        # apparel call per garment with the provider's own detection. Marked
        # `legacy_auto` so these are countable rather than indistinguishable.
        return [
            ExecutableStep(
                index=i,
                item_key=f"legacy:{i}",
                canonical="legacy_auto",
                model_name=routing.APPAREL_MODEL,
                image_url=url,
                category="auto",
            )
            for i, url in enumerate(stack)
        ]

    executable: list[ExecutableStep] = []
    for step in steps:
        index = int(step.get("index", len(executable)))
        if index >= len(stack):
            # The plan and the stack disagree, which should be impossible: both
            # are written in the same transaction. Skipping is the safe read —
            # the completeness check below then fails the job rather than
            # silently rendering fewer garments than were planned.
            continue
        canonical = str(step.get("canonical", ""))
        executable.append(
            ExecutableStep(
                index=index,
                item_key=str(step.get("item_key", f"step:{index}")),
                canonical=canonical,
                model_name=str(step.get("model_name") or routing.APPAREL_MODEL),
                image_url=stack[index],
                category=step.get("category"),
                prompt=_prompt_for(canonical) if step.get("has_prompt") else None,
                garment_photo_type=str(step.get("garment_photo_type") or routing.PHOTO_TYPE_AUTO),
            )
        )
    return executable


def _parse_steps(raw_plan: object) -> list[dict]:
    if not raw_plan:
        return []
    try:
        data = raw_plan if isinstance(raw_plan, dict) else json.loads(raw_plan)
    except (ValueError, TypeError):
        return []
    steps = data.get("steps") if isinstance(data, dict) else None
    return [s for s in (steps or []) if isinstance(s, dict)]


@dataclass
class ExecutedLook:
    """Running record of a look's execution, and the completeness gate."""

    planned: list[str]
    applied: list[str] = field(default_factory=list)
    failed: list[str] = field(default_factory=list)
    #: index -> {prediction/status/attempts/duration}. Written to `step_state`.
    step_state: dict[str, dict] = field(default_factory=dict)

    def record_success(self, step: ExecutableStep, *, attempts: int, duration_ms: int) -> None:
        self.applied.append(step.item_key)
        self.step_state[str(step.index)] = {
            "item_key": step.item_key,
            "canonical": step.canonical,
            "model": step.model_name,
            "category": step.category,
            "status": "applied",
            "attempts": attempts,
            "duration_ms": duration_ms,
        }

    def record_failure(self, step: ExecutableStep, *, attempts: int, duration_ms: int) -> None:
        self.failed.append(step.item_key)
        self.step_state[str(step.index)] = {
            "item_key": step.item_key,
            "canonical": step.canonical,
            "model": step.model_name,
            "category": step.category,
            "status": "failed",
            "attempts": attempts,
            "duration_ms": duration_ms,
        }

    @property
    def missing(self) -> list[str]:
        applied = set(self.applied)
        return [key for key in self.planned if key not in applied]

    def require_complete(self) -> None:
        """THE FULL LOOK INVARIANT. Every planned garment must have been applied.

        Called before the result is persisted, so a look that lost a garment
        never reaches `tryon_results` at all — there is no window in which a
        partial render exists as a finished one.
        """
        missing = self.missing
        if missing:
            raise LookIncompleteError(missing)
