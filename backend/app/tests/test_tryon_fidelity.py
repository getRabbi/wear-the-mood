"""The AI fidelity gate (Issue 2) — garment identity, retry bounds, refunds.

`test_tryon_render.py` proves a look renders every garment that was planned.
This proves the rendered garment is the one that was CHOSEN: a top that came
back as a cropped button-up is a failure with a refund, never a charged success,
however convincing the photograph is.

No paid provider is ever contacted. The vision judge is a fake that returns
scripted verdicts, which is the only way to test "a crop top was detected"
deterministically — and the only responsible way to run this in CI.
"""

from __future__ import annotations

import asyncio
import json
import uuid

import pytest

from app.core.config import get_settings
from app.services.llm.anthropic_fidelity import (
    CODE_COLOR,
    CODE_GARMENT_CLASS,
    CODE_LENGTH,
    CODE_MISSING,
    CODE_PRINT,
    CODE_SLEEVE,
)
from app.services.llm.base import (
    GarmentFidelityFinding,
    GarmentFidelityJudge,
    GarmentFidelityReport,
)
from app.services.llm.stub import StubFidelityJudge
from app.services.tryon import taxonomy as tax
from app.services.tryon.base import RenderRequest, RenderResult
from app.services.tryon.fidelity import (
    INSPECTED_ROLES,
    STATUS_PASSED,
    STATUS_REJECTED,
    STATUS_SKIPPED,
    STATUS_UNVERIFIED,
    InspectionTarget,
    inspect_look,
)
from app.services.tryon.planner import SelectedGarment, build_plan

# ── fakes ────────────────────────────────────────────────────────────────────


class _ScriptedJudge(GarmentFidelityJudge):
    """Returns a scripted verdict per call; records what it was asked."""

    name = "scripted"

    def __init__(self, *verdicts: list[str]) -> None:
        # Each entry is the list of fault codes for that call ([] == faithful).
        self._verdicts = list(verdicts)
        self.seen: list[str] = []

    async def compare(
        self,
        *,
        garment: bytes,
        garment_media_type: str,
        render: bytes,
        render_media_type: str,
        canonical: str,
    ) -> GarmentFidelityReport:
        self.seen.append(canonical)
        codes = self._verdicts.pop(0) if self._verdicts else []
        return GarmentFidelityReport(
            faithful=not codes,
            findings=[GarmentFidelityFinding(code=c, detail="scripted") for c in codes],
            input_tokens=10,
            output_tokens=5,
        )


class _DeadJudge(GarmentFidelityJudge):
    name = "dead"

    async def compare(self, **kw: object) -> GarmentFidelityReport:
        raise RuntimeError("vision provider unreachable")


def _target(canonical: str, key: str = "g1") -> InspectionTarget:
    return InspectionTarget(
        item_key=key,
        canonical=canonical,
        garment_bytes=b"\xff\xd8\xff\xe0garment",
        garment_media_type="image/jpeg",
    )


def _inspect(judge: GarmentFidelityJudge, targets: list[InspectionTarget]):
    return asyncio.run(
        inspect_look(
            judge,
            render=b"\xff\xd8\xff\xe0render",
            render_media_type="image/jpeg",
            targets=targets,
        )
    )


# ── what the gate must catch ─────────────────────────────────────────────────


def test_a_faithful_top_passes() -> None:
    outcome = _inspect(_ScriptedJudge([]), [_target(tax.TOP)])
    assert outcome.status == STATUS_PASSED
    assert outcome.inspected == 1
    assert outcome.codes == []


@pytest.mark.parametrize(
    ("code", "what_went_wrong"),
    [
        (CODE_GARMENT_CLASS, "the top came back as a shirt/jacket"),
        (CODE_LENGTH, "a normal-length top came back cropped"),
        (CODE_SLEEVE, "long sleeves came back sleeveless"),
        (CODE_COLOR, "the dominant colour changed"),
        (CODE_PRINT, "the print vanished or was invented"),
        (CODE_MISSING, "the garment is not on the person at all"),
    ],
)
def test_every_material_change_is_rejected(code: str, what_went_wrong: str) -> None:
    outcome = _inspect(_ScriptedJudge([code]), [_target(tax.TOP)])
    assert outcome.status == STATUS_REJECTED, what_went_wrong
    assert outcome.codes == [code]


def test_normal_variation_is_not_a_fault() -> None:
    # Pose, folds and lighting always differ between a flat garment photo and
    # the same garment worn. A judge that finds nothing is a PASS, not a
    # near-miss — the gate must not be a similarity threshold in disguise.
    outcome = _inspect(_ScriptedJudge([], [], []), [_target(tax.TOP)])
    assert outcome.status == STATUS_PASSED


def test_it_stops_at_the_first_rejection() -> None:
    # A look that already has to fail should not pay for a second opinion.
    judge = _ScriptedJudge([CODE_GARMENT_CLASS], [])
    outcome = _inspect(judge, [_target(tax.TOP, "a"), _target(tax.BOTTOM, "b")])
    assert outcome.status == STATUS_REJECTED
    assert len(judge.seen) == 1


def test_a_multi_garment_look_inspects_every_apparel_piece() -> None:
    judge = _ScriptedJudge([], [], [])
    outcome = _inspect(
        judge,
        [
            _target(tax.BOTTOM, "b"),
            _target(tax.TOP, "t"),
            _target(tax.OUTERWEAR, "o"),
        ],
    )
    assert outcome.status == STATUS_PASSED
    assert judge.seen == [tax.BOTTOM, tax.TOP, tax.OUTERWEAR]
    assert outcome.inspected == 3


def test_accessories_are_not_inspected() -> None:
    # Cost control, stated as a rule: a vision call per earring on a look that
    # already paid for several renders is not what this budget is for, and a
    # slightly different bracelet is not the failure the gate exists to catch.
    judge = _ScriptedJudge()
    outcome = _inspect(judge, [_target(tax.JEWELRY, "j"), _target(tax.GLASSES, "g")])
    assert outcome.status == STATUS_SKIPPED
    assert judge.seen == []


def test_the_inspected_roles_are_the_apparel_roles() -> None:
    assert INSPECTED_ROLES == {
        tax.TOP,
        tax.BOTTOM,
        tax.ONE_PIECE,
        tax.OUTERWEAR,
        tax.LOOK_REFERENCE,
    }


# ── "nobody looked" is its own answer ────────────────────────────────────────


def test_a_dead_judge_is_unverified_not_unfaithful() -> None:
    outcome = _inspect(_DeadJudge(), [_target(tax.TOP)])
    assert outcome.status == STATUS_UNVERIFIED
    assert outcome.codes == []


def test_the_stub_judge_refuses_to_claim_it_looked() -> None:
    # The important half: a no-key environment must not report 100% fidelity
    # coverage while inspecting nothing.
    with pytest.raises(NotImplementedError):
        asyncio.run(
            StubFidelityJudge().compare(
                garment=b"x",
                garment_media_type="image/jpeg",
                render=b"y",
                render_media_type="image/jpeg",
                canonical=tax.TOP,
            )
        )


def test_defaults_are_gate_on_fail_open() -> None:
    settings = get_settings()
    assert settings.fashn_fidelity_gate_enabled is True
    assert settings.fashn_fidelity_fail_closed is False
    assert settings.fashn_fidelity_max_retries == 1


# ── the worker: rejection, bounded retry, refund ─────────────────────────────


class _Provider:
    name = "fashn"

    def __init__(self) -> None:
        self.calls: list[RenderRequest] = []

    async def render(self, request: RenderRequest) -> RenderResult:
        self.calls.append(request)
        return RenderResult(
            image_url=f"render({request.garment_image})",
            prediction_id=f"pred-{len(self.calls)}",
        )


def _garment(key: str, canonical: str) -> SelectedGarment:
    return SelectedGarment(item_key=key, image_url=f"https://cdn/{key}.jpg", canonical=canonical)


def _job_row(plan) -> dict:
    return {
        "id": uuid.uuid4(),
        "user_id": uuid.uuid4(),
        "person_image_url": "https://cdn/me.jpg",
        "garment_image_url": plan.image_stack()[0],
        "garment_image_urls": plan.image_stack(),
        "provider": "fashn",
        "hd": False,
        "idempotency_key": "test-job",
        "plan": json.dumps(plan.as_json()),
        "planned_item_keys": plan.planned_item_keys,
        "applied_item_keys": [],
    }


def _wire(monkeypatch, provider: object, judge: object) -> list[str]:
    import app.workers.tryon_worker as worker_mod
    from app.tests.test_tryon_render import (  # reuse the proven fakes
        _noop,
        _passthrough,
        _stored,
        _tiny_image,
    )

    refunds: list[str] = []
    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: provider)
    monkeypatch.setattr(worker_mod, "get_fidelity_judge", lambda: judge)
    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)
    monkeypatch.setattr(worker_mod, "freshen_media_url", _passthrough)
    monkeypatch.setattr(worker_mod, "download_image", _tiny_image)
    monkeypatch.setattr(worker_mod, "upload_tryon_result", _stored)
    monkeypatch.setattr(worker_mod, "insert_asset", _noop)
    monkeypatch.setattr(worker_mod, "create_notification", _noop)
    monkeypatch.setattr(worker_mod, "_log_usage", _noop)

    async def _refund(conn: object, user_id: str, *, ref: str) -> None:
        refunds.append(ref)

    monkeypatch.setattr(worker_mod, "refund_credit", _refund)
    return refunds


def _run(monkeypatch, judge, garments) -> tuple[object, list[str], object]:
    import app.workers.tryon_worker as worker_mod
    from app.tests.test_tryon_render import _FakeConn

    provider = _Provider()
    refunds = _wire(monkeypatch, provider, judge)
    plan = build_plan(garments)
    conn = _FakeConn()
    job = _job_row(plan)
    asyncio.run(worker_mod.process_job(conn, job))
    return conn, refunds, (job, provider)


def test_a_wrong_garment_is_refunded_never_delivered(monkeypatch) -> None:
    """THE headline case: the user's top came back as a different garment."""
    conn, refunds, (job, _) = _run(
        monkeypatch,
        _ScriptedJudge([CODE_GARMENT_CLASS], [CODE_GARMENT_CLASS]),
        [_garment("top", tax.TOP)],
    )
    assert conn.sql("status = 'done'") == [], "a wrong garment must not complete"
    assert conn.sql("insert into public.tryon_results") == [], "nothing persisted"
    assert len(conn.sql("status = 'failed'")) == 1
    assert refunds == [str(job["id"])], "exactly one refund, for this job"


def test_the_retry_is_bounded_and_re_renders_the_whole_chain(monkeypatch) -> None:
    """A cumulative chain cannot be patched from the middle, so a rejected look
    is rebuilt from the user's own photo — and only as many times as configured."""
    judge = _ScriptedJudge([CODE_LENGTH], [CODE_LENGTH])
    _, _, (_, provider) = _run(
        monkeypatch, judge, [_garment("top", tax.TOP), _garment("pants", tax.BOTTOM)]
    )
    retries = get_settings().fashn_fidelity_max_retries
    # Two garments, rendered (1 + retries) times. No third pass, no loop.
    assert len(provider.calls) == 2 * (retries + 1)
    assert len(judge.seen) == retries + 1
    # Each attempt started from the body photo, not from the poisoned render.
    assert sum(1 for c in provider.calls if c.person_image.startswith("data:")) == retries + 1


def test_a_retry_that_succeeds_delivers_the_look(monkeypatch) -> None:
    # Rejected once, faithful on the re-render: the user gets their result and
    # is charged for it exactly once.
    conn, refunds, _ = _run(
        monkeypatch, _ScriptedJudge([CODE_SLEEVE], []), [_garment("top", tax.TOP)]
    )
    assert len(conn.sql("status = 'done'")) == 1
    assert refunds == []


def test_a_faithful_look_is_untouched_by_the_gate(monkeypatch) -> None:
    conn, refunds, (_, provider) = _run(monkeypatch, _ScriptedJudge([]), [_garment("top", tax.TOP)])
    assert len(conn.sql("status = 'done'")) == 1
    assert refunds == []
    assert len(provider.calls) == 1, "a passing look renders exactly once"


def test_an_unverified_look_is_still_delivered_by_default(monkeypatch) -> None:
    """Our vision provider being down must not cost users their renders."""
    conn, refunds, _ = _run(monkeypatch, _DeadJudge(), [_garment("top", tax.TOP)])
    assert len(conn.sql("status = 'done'")) == 1
    assert refunds == []


def test_fail_closed_refuses_an_uninspected_look(monkeypatch) -> None:
    """The other side of that trade, for an operator who wants it."""
    monkeypatch.setenv("FASHN_FIDELITY_FAIL_CLOSED", "true")
    get_settings.cache_clear()
    try:
        conn, refunds, (job, _) = _run(monkeypatch, _DeadJudge(), [_garment("top", tax.TOP)])
        assert conn.sql("status = 'done'") == []
        assert refunds == [str(job["id"])]
    finally:
        get_settings.cache_clear()


def test_the_gate_can_be_switched_off_entirely(monkeypatch) -> None:
    monkeypatch.setenv("FASHN_FIDELITY_GATE_ENABLED", "false")
    get_settings.cache_clear()
    try:
        judge = _ScriptedJudge([CODE_GARMENT_CLASS])
        conn, refunds, _ = _run(monkeypatch, judge, [_garment("top", tax.TOP)])
        assert len(conn.sql("status = 'done'")) == 1
        assert judge.seen == [], "a disabled gate spends nothing"
    finally:
        get_settings.cache_clear()


# ── the planner still refuses impossible looks BEFORE inference ──────────────


def test_a_one_piece_with_separates_is_rejected_before_any_render() -> None:
    """The third terminal state: rejected before inference because the selection
    itself is invalid. No credit, no provider call, no gate needed."""
    from app.services.tryon.planner import CONFLICT_ONE_PIECE, LookPlanError

    with pytest.raises(LookPlanError) as exc:
        build_plan([_garment("dress", tax.ONE_PIECE), _garment("top", tax.TOP)])
    assert exc.value.code == CONFLICT_ONE_PIECE
