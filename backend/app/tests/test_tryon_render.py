"""The provider request shape and the worker's chaining/accounting (Phases 4/8/9/19).

Two halves:

* what actually goes ON THE WIRE to FASHN — mocked transport, no network, no key;
* what the worker does with a plan — a fake connection, so the chain, the
  completeness gate and the credit path are all exercised without a database.
"""

from __future__ import annotations

import asyncio
import json
import uuid

import httpx
import pytest

from app.core.config import get_settings
from app.services.tryon import routing
from app.services.tryon import taxonomy as tax
from app.services.tryon.base import RenderRequest, RenderResult
from app.services.tryon.fashn import FashnTryOnProvider, _poll_delay
from app.services.tryon.planner import SelectedGarment, build_plan


@pytest.fixture(autouse=True)
def _clear_settings():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _provider(sent: list[dict], **kw: object) -> FashnTryOnProvider:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/run":
            sent.append(json.loads(request.content))
            return httpx.Response(200, json={"id": "job-1"})
        return httpx.Response(
            200, json={"id": "job-1", "status": "completed", "output": ["https://cdn/r.jpg"]}
        )

    return FashnTryOnProvider(
        "test-key",
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        poll_interval=0.0,
        **kw,
    )


# ── the apparel request carries an EXPLICIT category (spec Phase 4) ──────────


def test_apparel_request_sends_the_planned_category_not_auto() -> None:
    sent: list[dict] = []
    asyncio.run(
        _provider(sent).render(
            RenderRequest(
                person_image="data:image/jpeg;base64,AAA",
                garment_image="https://cdn/g.jpg",
                model_name=routing.APPAREL_MODEL,
                category="tops",
                garment_photo_type="flat-lay",
            )
        )
    )
    assert sent[0]["model_name"] == routing.APPAREL_MODEL
    inputs = sent[0]["inputs"]
    assert inputs["category"] == "tops"
    assert inputs["garment_photo_type"] == "flat-lay"
    assert "prompt" not in inputs  # tryon-v1.6 has no prompt parameter


def test_accessory_request_carries_a_prompt_and_never_a_category() -> None:
    """Verified against the live API: tryon-max answers
    `"category" category is not allowed`."""
    sent: list[dict] = []
    route = routing.route_for(tax.GLASSES)
    asyncio.run(
        _provider(sent).render(
            RenderRequest(
                person_image="https://cdn/step1.jpg",
                garment_image="https://cdn/glasses.jpg",
                model_name=route.model_name,
                prompt=route.prompt,
            )
        )
    )
    inputs = sent[0]["inputs"]
    assert sent[0]["model_name"] == routing.ACCESSORY_MODEL
    assert "category" not in inputs
    assert "garment_image" not in inputs  # tryon-max takes `product_image`
    assert inputs["product_image"] == "https://cdn/glasses.jpg"
    assert "do not replace" in inputs["prompt"].lower()
    # Pinned to the 1-credit configuration, so routing an accessory to its own
    # model costs exactly what sending it to the apparel model would have (§14).
    assert (inputs["generation_mode"], inputs["resolution"]) == ("fast", "1k")


def test_render_mode_and_output_format_come_from_config() -> None:
    sent: list[dict] = []
    asyncio.run(
        _provider(sent, mode="performance", output_format="png").render(
            RenderRequest(
                person_image="p",
                garment_image="g",
                model_name=routing.APPAREL_MODEL,
                category="bottoms",
            )
        )
    )
    assert sent[0]["inputs"]["mode"] == "performance"
    assert sent[0]["inputs"]["output_format"] == "png"


def test_default_mode_is_balanced_not_quality() -> None:
    """`quality` measured 12-17 s per step in production and was 60 s of a 115 s
    four-piece look. `balanced` is FASHN's own default at ~8 s, and try-on is
    flat-priced, so this is latency only (§14)."""
    assert get_settings().fashn_tryon_mode == "balanced"
    assert get_settings().fashn_output_format == "jpeg"


def test_polling_is_dense_where_completions_happen(monkeypatch) -> None:
    """A flat 2 s interval added ~1 s of dead time to every step of every look."""
    delays = [_poll_delay(i) for i in range(6)]
    assert delays[0] >= 2.0  # nothing completes in the first second
    assert all(d <= 1.0 for d in delays[1:5])  # then tight
    assert sum(delays) < 12 * 1.0  # cheaper than six flat 2 s waits


# ── the worker: chaining, accounting, credit safety ──────────────────────────


class _FakeConn:
    """Records writes; enough of asyncpg for the worker's happy and sad paths."""

    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []
        self.result_id = uuid.uuid4()

    async def execute(self, sql: str, *args: object) -> str:
        self.executed.append((sql, args))
        return "UPDATE 1"

    async def fetchval(self, sql: str, *args: object) -> object:
        self.executed.append((sql, args))
        return self.result_id

    async def fetchrow(self, sql: str, *args: object) -> None:
        return None

    async def fetch(self, sql: str, *args: object) -> list:
        return []

    def transaction(self):
        return _NoTxn()

    def sql(self, needle: str) -> list[tuple[str, tuple]]:
        return [row for row in self.executed if needle in row[0]]


class _NoTxn:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False


class _ChainProvider:
    """Renders `render(<garment>)`, recording what each step was handed."""

    name = "fashn"

    def __init__(self, fail_on: str | None = None) -> None:
        self.calls: list[RenderRequest] = []
        self._fail_on = fail_on

    async def render(self, request: RenderRequest) -> RenderResult:
        self.calls.append(request)
        if self._fail_on and self._fail_on in request.garment_image:
            from app.services.tryon.base import TryOnTransientError

            raise TryOnTransientError("provider down")
        return RenderResult(
            image_url=f"render({request.garment_image})",
            prediction_id=f"pred-{len(self.calls)}",
        )


def _wire(monkeypatch, provider: object) -> list[str]:
    """Stub every side effect the worker has outside the render chain."""
    import app.workers.tryon_worker as worker_mod

    refunds: list[str] = []
    monkeypatch.setattr(worker_mod, "get_tryon_provider", lambda: provider)
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


async def _passthrough(url: str) -> str:
    return url


async def _tiny_image(url: str) -> bytes:
    return b"\xff\xd8\xff\xe0jpegbytes"


async def _stored(user_id: str, image: bytes, content_type: str) -> str:
    return "stored/key.jpg"


async def _noop(*a: object, **kw: object) -> None:
    return None


def _job_row(plan, person: str = "https://cdn/me.jpg") -> dict:
    return {
        "id": uuid.uuid4(),
        "user_id": uuid.uuid4(),
        "person_image_url": person,
        "garment_image_url": plan.image_stack()[0],
        "garment_image_urls": plan.image_stack(),
        "provider": "fashn",
        "hd": False,
        "idempotency_key": "ab12cd34-ef56-7890-abcd-ef1234567890",
        "plan": json.dumps(plan.as_json()),
        "planned_item_keys": plan.planned_item_keys,
        "applied_item_keys": [],
    }


def _garment(key: str, canonical: str) -> SelectedGarment:
    return SelectedGarment(item_key=key, image_url=f"https://cdn/{key}.jpg", canonical=canonical)


def test_the_chain_feeds_each_result_into_the_next_step(monkeypatch) -> None:
    """The core of a Full Look: output N becomes the model image of step N+1, and
    the chain NEVER resets to the original photo mid-sequence."""
    import app.workers.tryon_worker as worker_mod

    provider = _ChainProvider()
    _wire(monkeypatch, provider)
    plan = build_plan(
        [
            _garment("glasses", tax.GLASSES),
            _garment("shirt", tax.TOP),
            _garment("hijab", tax.HIJAB_SCARF),
            _garment("pants", tax.BOTTOM),
        ]
    )
    conn = _FakeConn()
    asyncio.run(worker_mod.process_job(conn, _job_row(plan)))

    # Rendered in PLAN order, not tap order.
    assert [c.garment_image for c in provider.calls] == [
        "https://cdn/pants.jpg",
        "https://cdn/shirt.jpg",
        "https://cdn/hijab.jpg",
        "https://cdn/glasses.jpg",
    ]
    # Step 1 gets the inlined body; every later step gets the PREVIOUS output.
    assert provider.calls[0].person_image.startswith("data:image/")
    assert provider.calls[1].person_image == "render(https://cdn/pants.jpg)"
    assert provider.calls[2].person_image == "render(https://cdn/shirt.jpg)"
    assert provider.calls[3].person_image == "render(https://cdn/hijab.jpg)"
    # Explicit categories for apparel; prompts for accessories.
    assert [c.category for c in provider.calls[:2]] == ["bottoms", "tops"]
    assert all(c.prompt for c in provider.calls[2:])
    assert provider.calls[-1].is_final is True

    done = conn.sql("status = 'done'")
    assert len(done) == 1
    applied = done[0][1][1]
    assert applied == ["pants", "shirt", "hijab", "glasses"]


def test_the_body_photo_is_prepared_once_per_look(monkeypatch) -> None:
    """Not once per garment: only the first step sends the body, every later one
    chains a provider URL (spec Phase 14)."""
    provider = _ChainProvider()
    _wire(monkeypatch, provider)
    import app.workers.tryon_worker as worker_mod

    plan = build_plan([_garment("shirt", tax.TOP), _garment("pants", tax.BOTTOM)])
    asyncio.run(worker_mod.process_job(_FakeConn(), _job_row(plan)))
    inlined = [c for c in provider.calls if c.person_image.startswith("data:")]
    assert len(inlined) == 1


def test_a_look_that_loses_a_garment_fails_and_refunds(monkeypatch) -> None:
    """Four selected, one rendered: the exact production symptom. It must be a
    refunded failure, never a charged success (spec Phases 7/29)."""
    import app.workers.tryon_worker as worker_mod

    provider = _ChainProvider(fail_on="hijab")
    refunds = _wire(monkeypatch, provider)
    plan = build_plan(
        [
            _garment("shirt", tax.TOP),
            _garment("pants", tax.BOTTOM),
            _garment("hijab", tax.HIJAB_SCARF),
        ]
    )
    conn = _FakeConn()
    job = _job_row(plan)
    asyncio.run(worker_mod.process_job(conn, job))

    assert conn.sql("status = 'done'") == []  # no fake success
    assert conn.sql("insert into public.tryon_results") == []  # nothing persisted
    failed = conn.sql("status = 'failed'")
    assert len(failed) == 1
    assert refunds == [str(job["id"])]  # exactly one refund, for this job


def test_progress_is_written_per_step_so_a_stuck_job_says_where(monkeypatch) -> None:
    import app.workers.tryon_worker as worker_mod

    provider = _ChainProvider()
    _wire(monkeypatch, provider)
    plan = build_plan([_garment("shirt", tax.TOP), _garment("pants", tax.BOTTOM)])
    conn = _FakeConn()
    asyncio.run(worker_mod.process_job(conn, _job_row(plan)))
    progress = conn.sql("set applied_item_keys")
    assert [row[1][4] for row in progress] == [1, 2]  # current_step after each


def test_a_retry_re_renders_one_step_and_never_replays_the_chain(monkeypatch) -> None:
    """Credit safety (spec Phase 19): retries happen INSIDE a step, so a flaky
    accessory cannot cause the shirt to be re-rendered or re-charged."""
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnTransientError

    class _FlakySecondStep:
        name = "fashn"

        def __init__(self) -> None:
            self.calls: list[str] = []
            self._fails = 2

        async def render(self, request: RenderRequest) -> RenderResult:
            self.calls.append(request.garment_image)
            if "glasses" in request.garment_image and self._fails:
                self._fails -= 1
                raise TryOnTransientError("blip")
            return RenderResult(f"render({request.garment_image})", "pred-x")

    provider = _FlakySecondStep()
    refunds = _wire(monkeypatch, provider)
    plan = build_plan([_garment("shirt", tax.TOP), _garment("glasses", tax.GLASSES)])
    conn = _FakeConn()
    asyncio.run(worker_mod.process_job(conn, _job_row(plan)))

    # The shirt was rendered exactly once despite two retries on the glasses.
    assert provider.calls.count("https://cdn/shirt.jpg") == 1
    assert provider.calls.count("https://cdn/glasses.jpg") == 3
    assert refunds == []  # it succeeded, so nothing to refund
    assert len(conn.sql("status = 'done'")) == 1


def test_each_step_records_the_provider_run_that_produced_it(monkeypatch) -> None:
    """A job id must be enough to reach the provider's own record (spec §18/§24).

    Without this, diagnosing a production failure gets as far as "step 3 failed"
    and stops: the correlation to FASHN's side lived only in a log line, which is
    not evidence once it has aged out of retention.
    """
    import app.workers.tryon_worker as worker_mod

    provider = _ChainProvider()
    _wire(monkeypatch, provider)
    plan = build_plan([_garment("shirt", tax.TOP), _garment("glasses", tax.GLASSES)])
    conn = _FakeConn()
    asyncio.run(worker_mod.process_job(conn, _job_row(plan)))

    state = json.loads(conn.sql("status = 'done'")[0][1][3])
    assert [state[k]["prediction_id"] for k in ("0", "1")] == ["pred-1", "pred-2"]
    assert state["1"]["model"] == routing.ACCESSORY_MODEL


def test_the_fashn_client_returns_the_run_id_it_polled(monkeypatch) -> None:
    sent: list[dict] = []
    result = asyncio.run(
        _provider(sent).render(
            RenderRequest(
                person_image="p",
                garment_image="g",
                model_name=routing.APPAREL_MODEL,
                category="tops",
            )
        )
    )
    assert result.image_url == "https://cdn/r.jpg"
    assert result.prediction_id == "job-1"


def test_the_worker_never_charges_credits_itself(monkeypatch) -> None:
    """Credits are RESERVED once at submit. A re-processed job (recovery, a late
    duplicate signal) must not be able to charge again — the worker has no
    charging path at all, only a refund."""
    import inspect

    import app.workers.tryon_worker as worker_mod

    source = inspect.getsource(worker_mod)
    assert "spend_credit" not in source
    assert "refund_credit" in source
