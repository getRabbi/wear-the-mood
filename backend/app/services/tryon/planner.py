"""Deterministic Try Look execution planner (CLAUDE.md §7; spec Phases 6, 7, 10).

Turns "the user tapped these four things" into an explicit, ordered, auditable
plan BEFORE a single credit or provider call is spent — and makes the plan the
thing the worker executes, so a look can never silently become fewer garments
than the person selected.

Three guarantees, in order of importance:

1. **Every selected item is accounted for.** A garment is either a planned step
   or a recorded skip with a reason. There is no third outcome, and "not in the
   output" is not one of them (§29).
2. **Roles are decided here, never by the provider.** A piece whose role we
   cannot establish from trustworthy metadata does not become a guess; it becomes
   a refusal the user can act on.
3. **Order is a property of the plan, not of tap order.** Apparel is applied
   before accessories because an apparel pass repaints a whole body region and
   would erase an accessory placed first — which is precisely how a four-piece
   look used to come back as one shirt.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from app.services.tryon import routing
from app.services.tryon import taxonomy as tax

#: Max garments in one look, mirrored by `app.models.tryon.MAX_GARMENTS`.
MAX_STEPS = 6

# ── skip reasons (stable codes; the message is what a user reads) ────────────
SKIP_NEEDS_REVIEW = "needs_review"
SKIP_UNSUPPORTED = "unsupported_category"

_SKIP_MESSAGES = {
    SKIP_NEEDS_REVIEW: (
        "We don't know what kind of piece this is yet. Open it and set a category, "
        "then try the look again."
    ),
    SKIP_UNSUPPORTED: "This kind of piece can't be rendered on a body yet.",
}

_GENERIC_SKIP_MESSAGE = "This piece couldn't be added to the look."


def skip_message(reason: str) -> str:
    """Current display copy for a stored skip reason.

    Plans store the CODE, not the sentence, so a job opened weeks later reads
    today's wording rather than whatever was shipped when it ran.
    """
    return _SKIP_MESSAGES.get(reason, _GENERIC_SKIP_MESSAGE)


class LookPlanError(ValueError):
    """The selection cannot be turned into a plan. Carries a user-facing message
    and a stable code so the router can map it to the §13 error contract."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


CONFLICT_DUPLICATE_ROLE = "duplicate_role"
CONFLICT_ONE_PIECE = "one_piece_conflict"
EMPTY_PLAN = "empty_plan"
TOO_MANY_STEPS = "too_many_steps"


@dataclass(frozen=True)
class SelectedGarment:
    """One thing the user tapped, with everything we managed to learn about it."""

    #: Stable identity for accounting. A wardrobe/product id when we have one,
    #: otherwise a deterministic token derived from the image reference — so a
    #: sample garment or a community image is still individually accountable.
    item_key: str
    image_url: str
    canonical: str | None = None
    #: Which field the category came from ("category" | "title" | ...), or
    #: "provider_auto" once the legacy escape hatch below has been taken.
    classification_source: str | None = None
    #: True only for a background-removed wardrobe cutout, where "flat-lay" is a
    #: fact about the file rather than a guess about the photo.
    is_cutout: bool = False
    wardrobe_item_id: str | None = None
    product_id: str | None = None
    #: Whether an unresolved role may fall back to the provider's own detector.
    #: Set ONLY for legacy URL-only requests from already-shipped clients, whose
    #: payload carries no way to say what a garment is. Recorded in the plan, so
    #: "how often does this still happen" is a query, not a guess.
    allow_auto_fallback: bool = False


@dataclass(frozen=True)
class PlanStep:
    """One provider call. Everything needed to submit it is resolved up front."""

    index: int
    item_key: str
    canonical: str
    model_name: str
    engine: str
    image_url: str
    category: str | None = None
    prompt: str | None = None
    garment_photo_type: str = routing.PHOTO_TYPE_AUTO

    def as_json(self) -> dict[str, object]:
        """Stored on the job. No signed URL: a plan is a durable record and a
        presigned URL is a credential that expires (§11). The worker re-resolves
        every image from the job's own stack at execution time."""
        return {
            "index": self.index,
            "item_key": self.item_key,
            "canonical": self.canonical,
            "model_name": self.model_name,
            "engine": self.engine,
            "category": self.category,
            "garment_photo_type": self.garment_photo_type,
            "has_prompt": self.prompt is not None,
        }


@dataclass(frozen=True)
class SkippedItem:
    item_key: str
    reason: str
    message: str
    canonical: str | None = None

    def as_json(self) -> dict[str, object]:
        return {
            "item_key": self.item_key,
            "reason": self.reason,
            "canonical": self.canonical,
        }


@dataclass
class ExecutionPlan:
    """What the worker will do, and what it must be able to prove afterwards."""

    steps: list[PlanStep] = field(default_factory=list)
    skipped: list[SkippedItem] = field(default_factory=list)
    selected_item_keys: list[str] = field(default_factory=list)

    @property
    def planned_item_keys(self) -> list[str]:
        return [s.item_key for s in self.steps]

    @property
    def skipped_item_keys(self) -> list[str]:
        return [s.item_key for s in self.skipped]

    @property
    def total_steps(self) -> int:
        return len(self.steps)

    def as_json(self) -> dict[str, object]:
        return {
            "version": 1,
            "steps": [s.as_json() for s in self.steps],
            "skipped": [s.as_json() for s in self.skipped],
            "selected_item_keys": list(self.selected_item_keys),
        }

    #: The ordered image stack the worker chains through. Kept alongside the plan
    #: (not inside it) because these are freshly-signed URLs, not durable record.
    def image_stack(self) -> list[str]:
        return [s.image_url for s in self.steps]


def _conflict(code: str, message: str) -> LookPlanError:
    return LookPlanError(code, message)


def _duplicate_message(canonical: str) -> str:
    spec = tax.role_spec(canonical)
    region = spec.region if spec else "same"
    return f"You've picked two pieces for the {region}. Choose one of them for this look."


#: Which piece a user is asked to remove, per whole-body role. Named after what
#: they PICKED, because "a dress and a top" is not something a person can act on
#: unless they are told which of the two is the problem.
_EXCLUSION_MESSAGES = {
    tax.ONE_PIECE: (
        "A dress or jumpsuit already covers the whole body, so remove the "
        "separate top or bottom from this look."
    ),
    tax.LOOK_REFERENCE: (
        "This look already includes a full outfit, so remove the separate clothing pieces from it."
    ),
}


def _exclusion_message(canonical: str) -> str:
    return _EXCLUSION_MESSAGES.get(
        canonical, "These pieces can't be worn together. Remove one of them from this look."
    )


def build_plan(garments: list[SelectedGarment]) -> ExecutionPlan:
    """Build the ordered plan, or raise `LookPlanError` if the selection cannot
    be rendered as one coherent look.

    Raises rather than trims. A conflicting selection is a question only the user
    can answer — resolving it here would mean silently rendering an outfit they
    did not choose, and charging them for it.
    """
    if len(garments) > MAX_STEPS:
        raise _conflict(TOO_MANY_STEPS, f"A look can have at most {MAX_STEPS} pieces.")

    plan = ExecutionPlan(selected_item_keys=[g.item_key for g in garments])
    routable: list[tuple[SelectedGarment, str, routing.ProviderRoute]] = []

    for garment in garments:
        canonical = garment.canonical
        if canonical is None:
            if garment.allow_auto_fallback:
                # LEGACY ESCAPE HATCH, and the only one in the pipeline. An
                # already-shipped client sends bare image URLs with no way to say
                # what they are, and we could not resolve them from storage or the
                # catalog either. Refusing would break every installed app; the
                # provider's own detector is what those builds have always used,
                # so behaviour is preserved exactly — but it is now RECORDED as
                # `provider_auto` on the job rather than being invisible.
                routable.append(
                    (
                        garment,
                        tax.TOP,  # placeholder role for ordering only
                        routing.ProviderRoute(
                            routing.APPAREL_MODEL, routing.ENGINE_APPAREL, category="auto"
                        ),
                    )
                )
                continue
            plan.skipped.append(
                SkippedItem(garment.item_key, SKIP_NEEDS_REVIEW, _SKIP_MESSAGES[SKIP_NEEDS_REVIEW])
            )
            continue

        route = routing.route_for(canonical)
        if route is None:
            plan.skipped.append(
                SkippedItem(
                    garment.item_key,
                    SKIP_UNSUPPORTED,
                    _SKIP_MESSAGES[SKIP_UNSUPPORTED],
                    canonical=canonical,
                )
            )
            continue
        routable.append((garment, canonical, route))

    _check_conflicts([canonical for _, canonical, route in routable if route.category != "auto"])

    # Stable sort: render order first, then the user's own tap order for ties, so
    # a plan is reproducible from the same selection every time.
    ordered = sorted(enumerate(routable), key=lambda pair: (tax.render_order(pair[1][1]), pair[0]))
    for index, (garment, canonical, route) in enumerate(item for _, item in ordered):
        plan.steps.append(
            PlanStep(
                index=index,
                item_key=garment.item_key,
                canonical=canonical,
                model_name=route.model_name,
                engine=route.engine,
                image_url=garment.image_url,
                category=route.category,
                prompt=route.prompt,
                garment_photo_type=routing.garment_photo_type(is_cutout=garment.is_cutout),
            )
        )

    if not plan.steps:
        # Everything was skipped. Fail here, before any charge: a look with no
        # renderable piece is not a look, and returning "success" with the user's
        # untouched photo would be the fake success §29 forbids.
        first = plan.skipped[0] if plan.skipped else None
        raise _conflict(
            EMPTY_PLAN,
            first.message if first else "Pick at least one piece for this look.",
        )
    return plan


def _check_conflicts(canonicals: list[str]) -> None:
    """Deterministic compatibility rules (Phase 10). Order-independent."""
    seen: set[str] = set()
    for canonical in canonicals:
        if canonical in seen:
            raise _conflict(CONFLICT_DUPLICATE_ROLE, _duplicate_message(canonical))
        seen.add(canonical)

    for canonical in sorted(seen):
        spec = tax.role_spec(canonical)
        if spec is None:
            continue
        clash = spec.excludes & seen
        if clash:
            raise _conflict(CONFLICT_ONE_PIECE, _exclusion_message(canonical))
