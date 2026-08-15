import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.tryon import TryOnRequest
from app.services.tryon.base import TryOnProvider

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token() -> str:
    now = int(time.time())
    payload = {
        "sub": "user-123",
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def _auth(extra: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {_token()}"}
    if extra:
        headers.update(extra)
    return headers


# ── auth + header gates (run before any DB access) ───────────────────────────


def test_tryon_requires_token() -> None:
    resp = client.post("/v1/tryon", json={"person_image_url": "x", "garment_image_url": "y"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_tryon_requires_idempotency_key() -> None:
    resp = client.post(
        "/v1/tryon",
        json={"person_image_url": "x", "garment_image_url": "y"},
        headers=_auth(),
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_tryon_rejects_bad_body() -> None:
    # Neither garment source supplied -> model validator fails before DB.
    resp = client.post(
        "/v1/tryon",
        json={"person_image_url": "x"},
        headers=_auth({"Idempotency-Key": str(uuid.uuid4())}),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_get_tryon_requires_token() -> None:
    resp = client.get(f"/v1/tryon/{uuid.uuid4()}")
    assert resp.status_code == 401


def test_get_tryon_rejects_non_uuid() -> None:
    resp = client.get("/v1/tryon/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


def test_results_requires_token() -> None:
    assert client.get("/v1/tryon/results").status_code == 401


def test_results_route_not_shadowed_by_job_id() -> None:
    # /tryon/results must hit the list handler, not get_tryon({job_id}) — which
    # would 422 trying to parse "results" as a UUID.
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/tryon/results", headers=_auth())
    assert resp.status_code not in (401, 422)


# ── pure model + provider ────────────────────────────────────────────────────


def test_request_requires_exactly_one_garment_source() -> None:
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p")  # neither
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_url="g", wardrobe_item_id=uuid.uuid4())
    # Each single source is valid.
    assert TryOnRequest(person_image_url="p", garment_image_url="g").garment_image_url == "g"
    assert TryOnRequest(person_image_url="p", wardrobe_item_id=uuid.uuid4()).wardrobe_item_id


def test_request_validates_model_source() -> None:
    # studio_model needs a preset id; an unknown source is rejected; own_photo is
    # the unchanged default.
    assert TryOnRequest(person_image_url="p", garment_image_url="g").model_source == "own_photo"
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_url="g", model_source="studio_model")
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_url="g", model_source="bogus")
    ok = TryOnRequest(
        person_image_url="p",
        garment_image_url="g",
        model_source="studio_model",
        preset_model_id=uuid.uuid4(),
    )
    assert ok.model_source == "studio_model"


# ── Try-On Body System: person-image resolution + studio gating ──────────────


class _PresetConn:
    """Minimal conn for _resolve_person_image: returns a preset row (or None)."""

    def __init__(self, row: dict | None) -> None:
        self._row = row

    async def fetchrow(self, sql: str, *args):
        return self._row


def _plan(tier: str):
    from app.core.plans import Plan

    return Plan(tier=tier, kind="subscription", monthly_credits=0, hd_allowed=False, priority=False)


def test_resolve_own_photo_passthrough() -> None:
    import app.routers.v1.tryon as tryon_mod

    body = TryOnRequest(person_image_url="my-body", garment_image_url="g")
    out = asyncio.run(tryon_mod._resolve_person_image(_PresetConn(None), _plan("pro"), body))
    assert out == "my-body"


def test_resolve_studio_model_free_blocked_on_pro_only() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    body = TryOnRequest(
        person_image_url="x",
        garment_image_url="g",
        model_source="studio_model",
        preset_model_id=uuid.uuid4(),
    )
    conn = _PresetConn({"image_url": "https://cdn/m.jpg", "is_pro_only": True})
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._resolve_person_image(conn, _plan("free"), body))
    assert exc.value.code == "PAYWALL"


def test_resolve_studio_model_free_allowed_on_free_model() -> None:
    import app.routers.v1.tryon as tryon_mod

    # A free base model (is_pro_only=false) is usable by a free user.
    body = TryOnRequest(
        person_image_url="x",
        garment_image_url="g",
        model_source="studio_model",
        preset_model_id=uuid.uuid4(),
    )
    conn = _PresetConn({"image_url": "https://cdn/free.jpg", "is_pro_only": False})
    out = asyncio.run(tryon_mod._resolve_person_image(conn, _plan("free"), body))
    assert out == "https://cdn/free.jpg"


def test_resolve_studio_model_uses_preset_image() -> None:
    import app.routers.v1.tryon as tryon_mod

    body = TryOnRequest(
        person_image_url="ignored",
        garment_image_url="g",
        model_source="studio_model",
        preset_model_id=uuid.uuid4(),
    )
    conn = _PresetConn({"image_url": "https://cdn/studio_model.jpg", "is_pro_only": True})
    out = asyncio.run(tryon_mod._resolve_person_image(conn, _plan("pro_max"), body))
    assert out == "https://cdn/studio_model.jpg"  # server-resolved, not the client URL


def test_resolve_studio_model_missing_is_not_found() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    body = TryOnRequest(
        person_image_url="x",
        garment_image_url="g",
        model_source="studio_model",
        preset_model_id=uuid.uuid4(),
    )
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._resolve_person_image(_PresetConn(None), _plan("pro"), body))
    assert exc.value.code == "NOT_FOUND"


def test_resolve_user_avatar_rejected_future_ready() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    # user_avatar is future-ready only — it must be cleanly rejected, not run.
    body = TryOnRequest.model_construct(
        person_image_url="x",
        garment_image_url="g",
        garment_image_urls=None,
        wardrobe_item_id=None,
        model_source="user_avatar",
        preset_model_id=None,
        hd=False,
    )
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._resolve_person_image(_PresetConn(None), _plan("pro"), body))
    assert exc.value.code == "VALIDATION_ERROR"


def test_moderate_one_body_and_garment_have_distinct_messages(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An unreadable input must name the BODY vs the GARMENT so the user fixes the
    right one instead of blindly retrying the same broken source (§13)."""
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationInputError

    class _Reject:
        async def check_image(self, url: str):
            raise ModerationInputError("could not download file")

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _Reject())

    with pytest.raises(ApiError) as body_exc:
        asyncio.run(tryon_mod._moderate_one("u1", "url", kind="body"))
    with pytest.raises(ApiError) as garment_exc:
        asyncio.run(tryon_mod._moderate_one("u1", "url", kind="garment"))

    assert body_exc.value.code == "VALIDATION_ERROR"
    assert garment_exc.value.code == "VALIDATION_ERROR"
    assert "body photo" in body_exc.value.message
    assert "garment" in garment_exc.value.message
    assert body_exc.value.message != garment_exc.value.message


def test_moderate_one_allows_clean_image(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.services.moderation.base import ModerationResult

    class _Allow:
        async def check_image(self, url: str):
            return ModerationResult(allowed=True)

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _Allow())
    # No raise == pass.
    asyncio.run(tryon_mod._moderate_one("u1", "url", kind="garment"))


def test_request_accepts_garment_stack() -> None:
    from app.models.tryon import MAX_GARMENTS

    req = TryOnRequest(
        person_image_url="p",
        garment_image_urls=["a", "b", "c"],
    )
    assert req.garment_image_urls == ["a", "b", "c"]
    # blanks are dropped
    assert TryOnRequest(
        person_image_url="p", garment_image_urls=["a", "", "  "]
    ).garment_image_urls == ["a"]
    # stack is an exclusive source — can't combine with a single garment
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_url="g", garment_image_urls=["a"])
    # empty stack is rejected
    with pytest.raises(ValueError):
        TryOnRequest(person_image_url="p", garment_image_urls=[])
    # over the cap is rejected
    with pytest.raises(ValueError):
        TryOnRequest(
            person_image_url="p",
            garment_image_urls=[f"g{i}" for i in range(MAX_GARMENTS + 1)],
        )


def test_stub_provider_echoes_person_image() -> None:
    # Test the stub directly — get_tryon_provider routing depends on env keys.
    from app.services.tryon.stub import StubTryOnProvider

    out = asyncio.run(
        StubTryOnProvider().generate(person_image_url="person", garment_image_url="garment")
    )
    assert out == "person"


# ── person image is inlined as base64 (the try-on timeout fix) ───────────────


def test_inline_person_image_returns_jpeg_data_uri(monkeypatch: pytest.MonkeyPatch) -> None:
    import base64

    import app.workers.tryon_worker as worker_mod

    async def _fake_download(url: str) -> bytes:
        return b"\xff\xd8\xff-jpeg-bytes"

    monkeypatch.setattr(worker_mod, "download_image", _fake_download)
    out = asyncio.run(worker_mod._inline_person_image("https://x/u/avatar.jpg?token=abc"))
    assert out.startswith("data:image/jpeg;base64,")
    assert base64.b64decode(out.split(",", 1)[1]) == b"\xff\xd8\xff-jpeg-bytes"


def test_inline_person_image_detects_png(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod

    async def _fake_download(url: str) -> bytes:
        return b"\x89PNG"

    monkeypatch.setattr(worker_mod, "download_image", _fake_download)
    out = asyncio.run(worker_mod._inline_person_image("https://x/u/a.PNG?sig=1"))
    assert out.startswith("data:image/png;base64,")


def test_inline_person_image_failure_is_friendly(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod

    async def _boom(url: str) -> bytes:
        raise RuntimeError("403 Forbidden / expired signature")

    monkeypatch.setattr(worker_mod, "download_image", _boom)
    with pytest.raises(RuntimeError) as exc:
        asyncio.run(worker_mod._inline_person_image("https://x/expired"))
    # The user must see an actionable message, never the raw httpx/storage error.
    assert "re-select" in str(exc.value).lower()


# ── FASHN provider async contract + terminal-state handling ──────────────────


class _FakeResp:
    def __init__(self, data: dict) -> None:
        self._data = data

    def raise_for_status(self) -> None:  # pragma: no cover - trivial
        pass

    def json(self) -> dict:
        return self._data


class _FakeClient:
    """Minimal stand-in for httpx.AsyncClient: records the POST body and returns
    the queued status payloads in order."""

    def __init__(self, run_id: str, statuses: list[dict]) -> None:
        self._run_id = run_id
        self._statuses = list(statuses)
        self.posted: dict | None = None

    async def post(self, url: str, headers=None, json=None) -> _FakeResp:
        self.posted = json
        return _FakeResp({"id": self._run_id})

    async def get(self, url: str, headers=None) -> _FakeResp:
        return _FakeResp(self._statuses.pop(0))


def _fashn(client: _FakeClient):
    from app.services.tryon.fashn import FashnTryOnProvider

    # poll_interval=0 keeps the test instant.
    return FashnTryOnProvider("test-key", client=client, poll_interval=0)


def test_fashn_completes_and_passes_inputs_through() -> None:
    client = _FakeClient(
        "pred-1",
        [
            {"status": "processing"},
            {"status": "completed", "output": ["https://cdn.fashn.ai/out_0.png"]},
        ],
    )
    out = asyncio.run(
        _fashn(client).generate(
            person_image_url="data:image/jpeg;base64,QUJD",
            garment_image_url="https://pub/g.jpg",
        )
    )
    assert out == "https://cdn.fashn.ai/out_0.png"
    # Async contract + base64 person image forwarded verbatim (CLAUDE.md §7).
    assert client.posted is not None
    assert client.posted["model_name"] == "tryon-v1.6"
    assert client.posted["inputs"]["model_image"] == "data:image/jpeg;base64,QUJD"
    assert client.posted["inputs"]["garment_image"] == "https://pub/g.jpg"


def test_fashn_failed_status_maps_friendly_message() -> None:
    client = _FakeClient("p", [{"status": "failed", "error": {"name": "PoseError"}}])
    with pytest.raises(RuntimeError) as exc:
        asyncio.run(_fashn(client).generate(person_image_url="p", garment_image_url="g"))
    assert "full-body" in str(exc.value).lower()


def test_fashn_time_out_status_is_terminal() -> None:
    # Only one status is queued; if 'time_out' were not treated as terminal the
    # provider would poll again and pop an empty list (IndexError), so a clean
    # RuntimeError proves the terminal-state handling.
    client = _FakeClient("p", [{"status": "time_out"}])
    with pytest.raises(RuntimeError):
        asyncio.run(_fashn(client).generate(person_image_url="p", garment_image_url="g"))


# ── transient vs permanent classification + retry (Issue 7a) ─────────────────


def test_fashn_pose_error_is_permanent_input_error() -> None:
    from app.services.tryon.base import TryOnInputError

    client = _FakeClient("p", [{"status": "failed", "error": {"name": "PoseError"}}])
    with pytest.raises(TryOnInputError):
        asyncio.run(_fashn(client).generate(person_image_url="p", garment_image_url="g"))


def test_fashn_generic_failure_is_transient() -> None:
    # An unknown/unnamed terminal failure is the intermittent "works on retry"
    # case → transient, so the worker retries it.
    from app.services.tryon.base import TryOnTransientError

    client = _FakeClient("p", [{"status": "failed", "error": {"name": "ServerError"}}])
    with pytest.raises(TryOnTransientError):
        asyncio.run(_fashn(client).generate(person_image_url="p", garment_image_url="g"))


def test_fashn_empty_output_is_transient() -> None:
    from app.services.tryon.base import TryOnTransientError

    client = _FakeClient("p", [{"status": "completed", "output": []}])
    with pytest.raises(TryOnTransientError):
        asyncio.run(_fashn(client).generate(person_image_url="p", garment_image_url="g"))


def test_fashn_http_5xx_is_transient() -> None:
    import httpx

    from app.services.tryon.base import TryOnTransientError

    class _Boom:
        async def post(self, url, headers=None, json=None):
            req = httpx.Request("POST", url)
            raise httpx.HTTPStatusError(
                "server error", request=req, response=httpx.Response(502, request=req)
            )

        async def get(self, url, headers=None):  # pragma: no cover - never reached
            raise AssertionError("status must not be polled after a failed submit")

    with pytest.raises(TryOnTransientError):
        asyncio.run(_fashn(_Boom()).generate(person_image_url="p", garment_image_url="g"))


class _FlakyProvider(TryOnProvider):
    """Fails with `exc` the first `fail_times` calls, then returns a result."""

    name = "fashn"

    def __init__(self, fail_times: int, exc: Exception) -> None:
        self._left = fail_times
        self._exc = exc
        self.calls = 0

    async def render(self, request: object) -> str:
        self.calls += 1
        if self._left > 0:
            self._left -= 1
            raise self._exc
        return "render-ok"


def _one_step_request():
    from app.services.tryon.base import RenderRequest

    return RenderRequest(
        person_image="me", garment_image="g", model_name="tryon-v1.6", category="tops"
    )


def test_retry_succeeds_after_transient_failures(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnTransientError

    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)  # no real sleeping
    provider = _FlakyProvider(2, TryOnTransientError("blip"))
    out, attempts = asyncio.run(
        worker_mod._render_with_retry(provider, _one_step_request(), job_id="j1", step_index=0)
    )
    assert out == "render-ok"
    assert provider.calls == 3  # 2 transient failures + 1 success
    assert attempts == 3  # and the job records how hard the step was


def test_retry_gives_up_after_max_attempts(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnTransientError

    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)
    provider = _FlakyProvider(99, TryOnTransientError("down"))
    with pytest.raises(TryOnTransientError):
        asyncio.run(
            worker_mod._render_with_retry(provider, _one_step_request(), job_id="j2", step_index=0)
        )
    assert provider.calls == worker_mod._MAX_ATTEMPTS


def test_retry_does_not_retry_permanent_input_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnInputError

    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)
    provider = _FlakyProvider(99, TryOnInputError("bad pose"))
    with pytest.raises(TryOnInputError):
        asyncio.run(
            worker_mod._render_with_retry(provider, _one_step_request(), job_id="j3", step_index=0)
        )
    assert provider.calls == 1  # permanent error is not retried


# ── input moderation (§19) ───────────────────────────────────────────────────


def test_moderate_inputs_blocks_flagged(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult

    class _Block:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=False, reason="sexual")

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _Block())
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._moderate_one("user", "https://x/g.jpg", kind="garment"))
    assert exc.value.code == "MODERATION_BLOCKED"
    assert exc.value.status_code == 422


def test_moderate_inputs_allows_clean(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.services.moderation.base import ModerationResult

    class _Allow:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            return ModerationResult(allowed=True)

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _Allow())
    asyncio.run(tryon_mod._moderate_one("user", "https://x/p.jpg", kind="garment"))  # no raise


# Regression (Phase 5 §14.2): an unfetchable person_image_url used to let
# openai.BadRequestError escape _moderate_inputs, so the client got an unhandled
# HTTP 500 instead of a documented typed error (CLAUDE.md §13).


def test_moderate_inputs_unfetchable_url_is_validation_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationInputError, ModerationResult

    class _BadInput:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            raise ModerationInputError("Failed to download image from file_url")

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _BadInput())
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._moderate_one("user", "https://example.invalid/p.jpg", kind="body"))
    assert exc.value.code == "VALIDATION_ERROR"
    assert exc.value.status_code == 422


def test_moderate_inputs_provider_down_fails_closed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """§19 makes moderation mandatory, so an unavailable provider must BLOCK the
    job (PROVIDER_ERROR), never fail open and let an unchecked image through."""
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError
    from app.services.moderation.base import ModerationResult, ModerationUnavailable

    class _Down:
        name = "x"

        async def check_image(self, url: str) -> ModerationResult:
            raise ModerationUnavailable("503 upstream")

    monkeypatch.setattr(tryon_mod, "get_moderator", lambda: _Down())
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._moderate_one("user", "https://x/p.jpg", kind="garment"))
    assert exc.value.code == "PROVIDER_ERROR"
    assert exc.value.status_code == 503


def test_openai_moderator_maps_400_to_input_error() -> None:
    """The provider adapter, not the router, decides which failures are the
    caller's fault. A 400 from the moderations endpoint means our INPUT was bad."""
    import asyncio as _asyncio

    from app.services.moderation.base import ModerationInputError, ModerationUnavailable
    from app.services.moderation.openai_moderator import OpenAIModerator

    class _Err(Exception):
        def __init__(self, status: int) -> None:
            super().__init__(f"status {status}")
            self.status_code = status

    class _Client:
        def __init__(self, status: int) -> None:
            self._status = status
            self.moderations = self

        async def create(self, **_: object) -> object:
            raise _Err(self._status)

    bad = OpenAIModerator("k", "m", client=_Client(400))
    with pytest.raises(ModerationInputError):
        _asyncio.run(bad.check_image("https://example.invalid/x.jpg"))

    down = OpenAIModerator("k", "m", client=_Client(503))
    with pytest.raises(ModerationUnavailable):
        _asyncio.run(down.check_image("https://example.invalid/x.jpg"))


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_tryon_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        # multi-garment + Try-On Body System insert (migrations 0014, 0033)
        "insert into public.tryon_jobs "
        "(user_id, status, person_image_url, garment_image_url, garment_image_urls, "
        "wardrobe_item_id, provider, idempotency_key, hd, model_source, preset_model_id) "
        "values ($1::uuid, 'queued', $2, $3, $4::text[], $5, $6, $7, $8, $9, $10) returning id",
        # worker claim returns the full stack + the hd flag
        "update public.tryon_jobs set status = 'processing' where id = "
        "(select id from public.tryon_jobs where status = 'queued' "
        "order by created_at for update skip locked limit 1) "
        "returning id, user_id, person_image_url, garment_image_url, "
        "garment_image_urls, provider, hd",
        "select id, status, error from public.tryon_jobs "
        "where id = $1::uuid and user_id = $2::uuid",
        "select result_image_url from public.tryon_results "
        "where job_id = $1::uuid and user_id = $2::uuid order by created_at desc limit 1",
        "select coalesce(cutout_url, image_url) from public.wardrobe_items "
        "where id = $1::uuid and user_id = $2::uuid",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())


# ── the user is told when a try-on fails, and that the refund happened ───────
# A try-on runs 5-20s and users leave the generating screen. Silently refunding
# leaves them believing they paid for a render that never arrived.


class _NotifyConn:
    """Tracks whether the notification was written inside the failure/refund
    transaction, and what it said."""

    def __init__(self) -> None:
        self.in_txn = False
        self.notified: list[dict] = []
        self.notified_in_txn: list[bool] = []
        self.calls: list[str] = []

    def transaction(self):
        outer = self

        class _Tx:
            async def __aenter__(self):
                outer.in_txn = True
                return self

            async def __aexit__(self, *_a):
                outer.in_txn = False
                return False

        return _Tx()

    async def execute(self, sql: str, *args):
        self.calls.append(" ".join(sql.split()))
        return "UPDATE 1"

    async def fetchval(self, sql: str, *args):
        self.calls.append(" ".join(sql.split()))
        return None

    async def fetchrow(self, sql: str, *args):
        return None


def _tryon_failure(monkeypatch, error: str) -> _NotifyConn:
    import app.workers.tryon_worker as worker

    conn = _NotifyConn()

    async def _refund(c, user_id, *, ref):
        return True

    async def _create(c, **kwargs):
        conn.notified.append(kwargs)
        conn.notified_in_txn.append(conn.in_txn)
        from app.services.notifications import NotificationOutcome

        return NotificationOutcome(True, "n-1")

    async def _log(*a, **k):
        return None

    monkeypatch.setattr(worker, "refund_credit", _refund)
    monkeypatch.setattr(worker, "create_notification", _create)
    monkeypatch.setattr(worker, "_log_usage", _log)

    asyncio.run(
        worker._fail_and_refund(
            conn,
            job_id="job-1",
            user_id="u1",
            error=error,
            provider="fashn",
            latency_ms=1200,
            images=1,
        )
    )
    return conn


def test_tryon_failure_notifies_and_confirms_the_refund(monkeypatch) -> None:
    conn = _tryon_failure(
        monkeypatch,
        "We couldn't detect your body in your photo. Use a clear, full-body photo.",
    )

    assert len(conn.notified) == 1
    note = conn.notified[0]
    assert note["type"] == "try_on_ready"
    assert "didn't work out" in note["title"]
    # The refund confirmation comes FIRST and is unconditional.
    assert note["body"].startswith("Your credits were refunded.")
    # And the actionable reason survives alongside it.
    assert "full-body photo" in note["body"]
    assert note["dedupe_key"] == "tryon_job:job-1:failed"
    assert note["target_type"] == "tryon_result"


def test_tryon_failure_notification_shares_the_refund_transaction(monkeypatch) -> None:
    """If the refund rolls back, the message claiming it happened must roll back
    with it."""
    conn = _tryon_failure(monkeypatch, "Something went wrong.")
    assert conn.notified_in_txn == [True]


def test_tryon_failure_never_leaks_provider_internals(monkeypatch) -> None:
    """Last gate before a lock screen: no signed URLs, payload dumps or traces."""
    for leaky in [
        "https://cdn.fashn.ai/x.png?X-Amz-Signature=deadbeef",
        "{'name': 'PoseError', 'message': 'internal'}",
        "Traceback (most recent call last): ...",
        "Bearer sk-live-abcdef",
    ]:
        conn = _tryon_failure(monkeypatch, leaky)
        body = conn.notified[0]["body"]
        assert body.startswith("Your credits were refunded.")
        for marker in ("http", "X-Amz", "Traceback", "Bearer", "{"):
            assert marker not in body, f"{marker!r} leaked from {leaky!r}"


def test_tryon_timeout_still_refunds_and_tells_the_user(monkeypatch) -> None:
    conn = _tryon_failure(monkeypatch, "That took too long to render. Please try again.")
    assert conn.notified[0]["body"].startswith("Your credits were refunded.")
    assert "too long" in conn.notified[0]["body"]


def test_tryon_failure_is_deduped_per_job(monkeypatch) -> None:
    """A recovery re-claim of the same job must not say it twice."""
    first = _tryon_failure(monkeypatch, "err")
    second = _tryon_failure(monkeypatch, "err")
    assert first.notified[0]["dedupe_key"] == second.notified[0]["dedupe_key"]


# ── shopping origin on a job (DISCOVER §13; Phase 5.1) ───────────────────────


def test_a_closet_render_carries_no_source() -> None:
    """The default, and the shape every job written before this feature has."""
    import app.routers.v1.tryon as tryon_mod

    body = TryOnRequest(person_image_url="p", garment_image_url="g")
    assert body.source_product_id is None
    assert asyncio.run(tryon_mod._resolve_shopping_source(_PresetConn(None), body)) is None


def test_the_merchant_is_derived_from_the_product_never_from_the_client() -> None:
    """Attribution decides who gets paid, so the client does not get to state it.

    There is deliberately no `source_merchant_id` on the request at all — the
    only way to be attributed is to name a product that really exists.
    """
    import app.routers.v1.tryon as tryon_mod

    product_id = uuid.uuid4()
    merchant_id = uuid.uuid4()
    body = TryOnRequest(person_image_url="p", garment_image_url="g", source_product_id=product_id)
    assert "source_merchant_id" not in body.model_fields_set
    assert not hasattr(body, "source_merchant_id")

    # `tryon_ready` comes back with the row now: naming a product is not enough
    # on its own, the catalog must still be clearing it for AI rendering (0067).
    conn = _PresetConn({"id": product_id, "merchant_id": merchant_id, "tryon_ready": True})
    resolved = asyncio.run(tryon_mod._resolve_shopping_source(conn, body))
    assert resolved == (str(product_id), str(merchant_id), "affiliate_product")


def test_an_unknown_product_drops_the_source_rather_than_the_render() -> None:
    """A stale back-link is a broken link; refusing the job would lose the
    render someone is paying credits for."""
    import app.routers.v1.tryon as tryon_mod

    body = TryOnRequest(person_image_url="p", garment_image_url="g", source_product_id=uuid.uuid4())
    assert asyncio.run(tryon_mod._resolve_shopping_source(_PresetConn(None), body)) is None


def test_a_withdrawn_product_leaves_no_source_to_shop() -> None:
    """`on delete set null` empties the id but leaves the kind behind. That is
    not a source — offering to shop it would dead-end."""
    import app.routers.v1.tryon as tryon_mod

    row = {
        "source_kind": "affiliate_product",
        "source_product_id": None,
        "source_merchant_id": None,
        "source_placement": "feed_grid",
        "source_campaign_id": None,
    }
    assert tryon_mod._source_of(row) is None


def test_a_live_source_row_becomes_a_source_block() -> None:
    import app.routers.v1.tryon as tryon_mod

    product_id, merchant_id = uuid.uuid4(), uuid.uuid4()
    source = tryon_mod._source_of(
        {
            "source_kind": "affiliate_product",
            "source_product_id": product_id,
            "source_merchant_id": merchant_id,
            "source_placement": "product_details",
            "source_campaign_id": "spring",
        }
    )
    assert source is not None
    assert source.product_id == str(product_id)
    assert source.merchant_id == str(merchant_id)
    assert source.placement == "product_details"


def test_an_older_result_row_without_source_columns_is_not_a_source() -> None:
    """Backward compatibility: a row from before the migration has no keys at
    all, and must read as an ordinary look rather than raising."""
    import app.routers.v1.tryon as tryon_mod

    assert tryon_mod._source_of({"id": "r1", "result_image_url": "u"}) is None


def test_the_source_block_carries_no_price_url_or_tag() -> None:
    """Everything a purchase decision needs is re-read live (§35, §38). A price
    stored on a job would be a claim nobody re-verified."""
    from app.models.tryon import TryOnSource

    fields = set(TryOnSource.model_fields)
    assert fields == {"kind", "product_id", "merchant_id", "placement", "campaign_id"}
    for banned in ("price", "url", "tag", "affiliate", "commission"):
        assert not any(banned in f for f in fields), banned
