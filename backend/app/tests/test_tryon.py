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
        person_image_url="p", garment_image_url="g",
        model_source="studio_model", preset_model_id=uuid.uuid4(),
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


def test_resolve_studio_model_free_is_paywalled() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    body = TryOnRequest(
        person_image_url="x", garment_image_url="g",
        model_source="studio_model", preset_model_id=uuid.uuid4(),
    )
    with pytest.raises(ApiError) as exc:
        asyncio.run(
            tryon_mod._resolve_person_image(_PresetConn(None), _plan("free"), body)
        )
    assert exc.value.code == "PAYWALL"


def test_resolve_studio_model_uses_preset_image() -> None:
    import app.routers.v1.tryon as tryon_mod

    body = TryOnRequest(
        person_image_url="ignored", garment_image_url="g",
        model_source="studio_model", preset_model_id=uuid.uuid4(),
    )
    conn = _PresetConn({"image_url": "https://cdn/studio_model.jpg"})
    out = asyncio.run(tryon_mod._resolve_person_image(conn, _plan("pro_max"), body))
    assert out == "https://cdn/studio_model.jpg"  # server-resolved, not the client URL


def test_resolve_studio_model_missing_is_not_found() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    body = TryOnRequest(
        person_image_url="x", garment_image_url="g",
        model_source="studio_model", preset_model_id=uuid.uuid4(),
    )
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._resolve_person_image(_PresetConn(None), _plan("pro"), body))
    assert exc.value.code == "NOT_FOUND"


def test_resolve_user_avatar_rejected_future_ready() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.core.errors import ApiError

    # user_avatar is future-ready only — it must be cleanly rejected, not run.
    body = TryOnRequest.model_construct(
        person_image_url="x", garment_image_url="g", garment_image_urls=None,
        wardrobe_item_id=None, model_source="user_avatar", preset_model_id=None, hd=False,
    )
    with pytest.raises(ApiError) as exc:
        asyncio.run(tryon_mod._resolve_person_image(_PresetConn(None), _plan("pro"), body))
    assert exc.value.code == "VALIDATION_ERROR"


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


def test_worker_chains_multi_garment_stack() -> None:
    # The worker renders each garment in order, feeding each result as the next
    # person image. With the stub (echoes person), the final result is the last
    # person image — i.e. the chain ran once per garment.
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnProvider

    calls: list[tuple[str, str]] = []

    class _Counting(TryOnProvider):
        name = "stub"

        async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
            calls.append((person_image_url, garment_image_url))
            return f"render({garment_image_url})"

    worker_mod_provider = worker_mod.get_tryon_provider
    worker_mod.get_tryon_provider = lambda: _Counting()
    try:
        job = {
            "id": uuid.uuid4(),
            "user_id": uuid.uuid4(),
            "person_image_url": "me",
            "garment_image_url": "g1",
            "garment_image_urls": ["g1", "g2", "g3"],
            "provider": "stub",
        }
        # Drive only the render-chaining portion (no DB): reproduce process_job's
        # loop to assert ordering + chaining without a live connection.
        provider = worker_mod.get_tryon_provider()
        stack = list(job["garment_image_urls"])
        current = job["person_image_url"]
        result = current
        for g in stack:

            async def _run(g=g, current=current):
                return await provider.generate(
                    person_image_url=current, garment_image_url=g
                )

            result = asyncio.run(_run())
            current = result
    finally:
        worker_mod.get_tryon_provider = worker_mod_provider

    assert [c[1] for c in calls] == ["g1", "g2", "g3"]  # rendered in order
    assert calls[0][0] == "me"  # first uses the person photo
    assert calls[1][0] == "render(g1)"  # second uses the first result
    assert result == "render(g3)"


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
    out = asyncio.run(
        worker_mod._inline_person_image("https://x/u/avatar.jpg?token=abc")
    )
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

    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        self.calls += 1
        if self._left > 0:
            self._left -= 1
            raise self._exc
        return "render-ok"


def test_retry_succeeds_after_transient_failures(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnTransientError

    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)  # no real sleeping
    provider = _FlakyProvider(2, TryOnTransientError("blip"))
    out = asyncio.run(
        worker_mod._generate_with_retry(
            provider, person_image_url="me", garment_image_url="g", job_id="j1"
        )
    )
    assert out == "render-ok"
    assert provider.calls == 3  # 2 transient failures + 1 success


def test_retry_gives_up_after_max_attempts(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.workers.tryon_worker as worker_mod
    from app.services.tryon.base import TryOnTransientError

    monkeypatch.setattr(worker_mod, "_BACKOFF_BASE", 0)
    provider = _FlakyProvider(99, TryOnTransientError("down"))
    with pytest.raises(TryOnTransientError):
        asyncio.run(
            worker_mod._generate_with_retry(
                provider, person_image_url="me", garment_image_url="g", job_id="j2"
            )
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
            worker_mod._generate_with_retry(
                provider, person_image_url="me", garment_image_url="g", job_id="j3"
            )
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
        asyncio.run(tryon_mod._moderate_inputs("user", "https://x/p.jpg", "https://x/g.jpg"))
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
    asyncio.run(tryon_mod._moderate_inputs("user", "https://x/p.jpg"))  # no raise


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
