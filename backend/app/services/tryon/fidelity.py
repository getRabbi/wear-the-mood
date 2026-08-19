"""The AI fidelity gate (spec Issue 2; CLAUDE.md §7, §14, §19, §29).

`execution.require_complete()` already proves every planned garment produced an
output. This proves something harder and more important: that the output is the
garment the user actually chose.

A visually plausible render is not automatically an acceptable one. FASHN can
return a beautiful photograph of a person wearing a garment that is simply not
the one submitted — a plain top comes back as a cropped button-up, a long sleeve
comes back bare — and every downstream signal (job completed, image stored,
credit charged) says success. This module is the line between "the provider
finished" and "the result may be shown and charged for".

## Three terminal states, never two

    passed      a judge looked and the garments survived
    rejected    a judge looked and a material property changed
    unverified  no judge could look

`unverified` exists because the alternatives are both dishonest. Returning
`passed` when no vision provider is configured would report 100% fidelity
coverage in an environment doing zero inspection. Returning `rejected` would
fail every try-on the moment the vision key lapsed — punishing users for our
outage. So it is its own state: the render is delivered, and the fact that
nobody inspected it is recorded and countable. `fidelity_fail_closed` flips that
trade for an operator who would rather refuse than ship uninspected.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from app.services.llm.base import GarmentFidelityJudge

log = logging.getLogger("fashionos.tryon.fidelity")

STATUS_PASSED = "passed"
STATUS_REJECTED = "rejected"
STATUS_UNVERIFIED = "unverified"
STATUS_SKIPPED = "skipped"

#: Roles worth inspecting. The apparel roles are where a material change is both
#: likely and unacceptable; a pair of earrings rendered slightly differently is
#: not the failure this gate exists for, and inspecting them would spend a vision
#: call per accessory on a look that already costs several renders.
INSPECTED_ROLES = frozenset({"top", "bottom", "one_piece", "outerwear", "look_reference"})


class LookFidelityError(RuntimeError):
    """The render did not preserve the selected garment.

    Raised so the job takes the ordinary FAILURE path — marked failed, credits
    refunded, the user told the truth. Showing the render instead would be the
    fake success §29 forbids, with the added insult of a charge.
    """

    def __init__(self, codes: list[str], detail: str) -> None:
        super().__init__(f"fidelity rejected: {', '.join(codes)}")
        self.codes = codes
        self.detail = detail


@dataclass(frozen=True)
class InspectionTarget:
    """One garment to check, and the reference image it must still look like."""

    item_key: str
    canonical: str
    garment_bytes: bytes
    garment_media_type: str


@dataclass
class FidelityOutcome:
    """What the gate concluded, in a shape that can be stored and counted."""

    status: str
    codes: list[str] = field(default_factory=list)
    detail: str | None = None
    inspected: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    @property
    def rejected(self) -> bool:
        return self.status == STATUS_REJECTED

    def as_json(self) -> dict[str, object]:
        return {
            "status": self.status,
            "codes": list(self.codes),
            "inspected": self.inspected,
            "detail": self.detail,
        }


async def inspect_look(
    judge: GarmentFidelityJudge,
    *,
    render: bytes,
    render_media_type: str,
    targets: list[InspectionTarget],
) -> FidelityOutcome:
    """Inspect a finished render against the garments it was supposed to apply.

    One vision call per inspected garment, and it stops at the FIRST rejection:
    a look that already has to fail does not need to pay to discover a second
    reason, and one actionable reason is what the user is told anyway.

    Never raises for a provider problem. An unjudgeable look is `unverified`,
    which the caller decides what to do with.
    """
    inspectable = [t for t in targets if t.canonical in INSPECTED_ROLES]
    if not inspectable:
        return FidelityOutcome(status=STATUS_SKIPPED)

    outcome = FidelityOutcome(status=STATUS_PASSED)
    for target in inspectable:
        try:
            report = await judge.compare(
                garment=target.garment_bytes,
                garment_media_type=target.garment_media_type,
                render=render,
                render_media_type=render_media_type,
                canonical=target.canonical,
            )
        except Exception as exc:  # noqa: BLE001 — a dead judge is not a bad render
            log.warning("fidelity judge unavailable (%s): %s", judge.name, exc)
            outcome.status = STATUS_UNVERIFIED
            outcome.detail = f"{exc.__class__.__name__}: {exc}"[:200]
            return outcome

        outcome.inspected += 1
        outcome.input_tokens += report.input_tokens or 0
        outcome.output_tokens += report.output_tokens or 0
        if not report.faithful:
            outcome.status = STATUS_REJECTED
            outcome.codes = [f.code for f in report.findings]
            outcome.detail = "; ".join(
                f"{f.code}({target.canonical}): {f.detail or ''}".strip() for f in report.findings
            )[:400]
            return outcome
    return outcome


def user_message_for(codes: list[str]) -> str:
    """What the wearer is told when a render is refused.

    Truthful about WHY without blaming them for it, and explicit about the
    refund — a user who is charged for nothing and told nothing assumes the
    charge was for the bad image they never received.
    """
    return (
        "The studio couldn't render your piece accurately — what came back was a "
        "different garment, so we haven't kept it. Your credits were refunded. "
        "A clearer, flat photo of the item usually fixes this."
    )
