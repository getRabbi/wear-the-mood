"""Background removal that has no garment yet — `cutout_temp` (0071).

Add Garment must be able to run: photo -> removal -> show the cutout -> ask what
the piece is -> save. The cloud remover's work queue is the wardrobe table, so
the only previous way to get a cloud cutout was to create the final garment
first — before the user had been asked to name it. These tests pin the escape
hatch and, more importantly, pin that it is not a hole:

  * a temp cutout is not a garment and never becomes one on its own;
  * adopting one does NOT buy exemption from the mandatory name + category;
  * a storage key is not a capability — you may only adopt your OWN finished,
    unclaimed job;
  * adopting never re-queues the worker to redo work that is already done.
"""

from __future__ import annotations

import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

import app.routers.v1.wardrobe as mod
from app.core.config import get_settings
from app.main import app

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_ID = "11111111-1111-4111-8111-111111111111"
OTHER_USER = "22222222-2222-4222-8222-222222222222"
ORIGINAL_KEY = f"{USER_ID}/wardrobe/{uuid.uuid4().hex}.jpg"
CUTOUT_KEY = f"{USER_ID}/cutout/{uuid.uuid4().hex}.png"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth(sub: str = USER_ID) -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": sub,
            "aud": "authenticated",
            "email": "a@b.com",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def _enable_r2(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("R2_ENDPOINT", "https://acc.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "realkeyid123")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "realsecret456")
    monkeypatch.setenv("R2_PUBLIC_BASE_URL", "https://cdn.example.com")
    monkeypatch.setenv("STORAGE_WRITES", "r2")
    get_settings.cache_clear()


class _Conn:
    """Fake connection. `job_row` is what a cutout_temp lookup answers with."""

    def __init__(self, *, job_row: dict | None = None, claim_key: str | None = None) -> None:
        self.calls: list[tuple[str, tuple]] = []
        self.job_row = job_row
        self.claim_key = claim_key
        self.item = {
            "id": uuid.uuid4(),
            "title": "Linen shirt",
            "category": "Tops",
            "subcategory": None,
            "color": None,
            "pattern": None,
            "brand": None,
            "image_url": None,
            "cutout_url": None,
            "thumbnail_url": None,
            "cover_image_url": None,
            "ai_enhanced": False,
            "ai_status": None,
            "tags": [],
            "cost": None,
            "purchase_date": None,
            "last_worn_at": None,
            "wear_count": 0,
            "cutout_status": None,
            "canonical_category": "top",
            "classification_status": "valid",
            "created_at": __import__("datetime").datetime.now(),
        }

    #: An item an earlier attempt already created, for the replay tests.
    existing_item: object | None = None

    def transaction(self):
        return _Tx()

    def _record(self, sql: str, args: tuple) -> str:
        flat = " ".join(sql.split())
        self.calls.append((flat, args))
        return flat

    async def fetchrow(self, sql: str, *args: object):
        flat = self._record(sql, args)
        if "job_type = 'cutout_temp'" in flat or "'cutout_temp'" in flat:
            return self.job_row
        return self.item

    async def fetchval(self, sql: str, *args: object):
        flat = self._record(sql, args)
        # Two different queries mention `cutout_temp`, and they mean opposite
        # things: one CLAIMS the finished job, the other asks whether an earlier
        # attempt at this same create already produced an item. Matching the
        # substring alone answered "yes, it exists" to both, so every create
        # looked like a replay. Keyed on the projection instead.
        if "output_urls[1] end" in flat:
            return self.claim_key
        if "from public.ai_jobs j" in flat:
            return self.existing_item
        return None

    async def fetch(self, sql: str, *args: object):
        self._record(sql, args)
        return []

    async def execute(self, sql: str, *args: object):
        self._record(sql, args)
        return "UPDATE 1"

    def written(self, needle: str) -> list[tuple[str, tuple]]:
        return [c for c in self.calls if needle in c[0]]


class _Tx:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self):
        return _Acquire(self.conn)


class _Acquire:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


def _wire(monkeypatch: pytest.MonkeyPatch, conn: _Conn) -> list[tuple[str, str]]:
    """Wire the router's collaborators. Returns the list signals land in."""
    signals: list[tuple[str, str]] = []
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    async def _flag(*a: object, **kw: object) -> bool:
        return True

    async def _noop(*a: object, **kw: object) -> None:
        return None

    async def _limit(*a: object, **kw: object) -> None:
        return None

    async def _enqueue(kind: str, job_id: str, **kw: object) -> bool:
        signals.append((kind, job_id))
        return True

    async def _sign(*a: object, **kw: object) -> str:
        return "https://cdn.example.com/signed.png"

    monkeypatch.setattr(mod, "flag_enabled", _flag)
    monkeypatch.setattr(mod, "insert_asset", _noop)
    monkeypatch.setattr(mod, "enforce_rate_limit", _limit)
    monkeypatch.setattr(mod, "enqueue_signal", _enqueue)
    monkeypatch.setattr(mod, "_cutout_job_output_url", _sign)
    return signals


# ── starting a removal with no garment ───────────────────────────────────────


def test_a_cutout_job_reserves_no_credits_and_creates_no_garment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable_r2(monkeypatch)
    job_id = uuid.uuid4()
    conn = _Conn(
        job_row={"id": job_id, "status": "queued", "output_urls": [], "error_message": None}
    )
    signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/cutout-job",
        json={"object_key": ORIGINAL_KEY},
        headers=_auth(),
    )

    assert resp.status_code == 202
    body = resp.json()
    assert body["job_type"] == "cutout_temp"
    assert body["status"] == "queued"
    # THE property: a removal that has not produced a piece has not produced a
    # piece. Nothing in the closet, nothing to exclude from it later.
    assert conn.written("insert into public.wardrobe_items") == []
    # Zero credits are reserved — the insert pins the literal.
    insert = conn.written("insert into public.ai_jobs")
    assert insert, "the job row was written"
    assert "'cutout_temp', 'queued'" in insert[0][0]
    assert ", 0" in insert[0][0]
    # The worker was woken on the shared AI queue.
    assert signals == [("ai", str(job_id))]


def test_a_finished_job_is_not_re_signalled(monkeypatch: pytest.MonkeyPatch) -> None:
    """Idempotent on the object key: a retry resumes the SAME removal. Re-waking a
    completed job would hand the worker a finished row to redo."""
    _enable_r2(monkeypatch)
    conn = _Conn(
        job_row={
            "id": uuid.uuid4(),
            "status": "completed",
            "output_urls": [CUTOUT_KEY],
            "error_message": None,
        }
    )
    signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/cutout-job", json={"object_key": ORIGINAL_KEY}, headers=_auth()
    )

    assert resp.status_code == 202
    assert resp.json()["status"] == "completed"
    assert resp.json()["output_url"], "a finished cutout is returned for display"
    assert signals == [], "no second removal for work already done"


@pytest.mark.parametrize(
    "key",
    [
        f"{OTHER_USER}/wardrobe/abc.jpg",  # another user's object
        f"{USER_ID}/tryon_photo/abc.jpg",  # biometric sector, never a garment
        f"{USER_ID}/wardrobe/../../etc/passwd",  # traversal
        "wardrobe/abc.jpg",  # unscoped
    ],
)
def test_a_foreign_or_malformed_key_is_404_and_starts_nothing(
    monkeypatch: pytest.MonkeyPatch, key: str
) -> None:
    _enable_r2(monkeypatch)
    conn = _Conn()
    signals = _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/cutout-job", json={"object_key": key}, headers=_auth())

    assert resp.status_code == 404
    assert conn.written("insert into public.ai_jobs") == []
    assert signals == []


def test_without_private_storage_it_is_unavailable_not_broken(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """No R2 private writes means nowhere safe to put a cutout. A clear
    feature-unavailable lets the client fall back instead of failing the add."""
    monkeypatch.setenv("STORAGE_WRITES", "legacy")
    get_settings.cache_clear()
    conn = _Conn()
    _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/cutout-job", json={"object_key": ORIGINAL_KEY}, headers=_auth()
    )

    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"
    assert conn.written("insert into public.ai_jobs") == []


# ── adopting the result ──────────────────────────────────────────────────────


def test_adopting_a_cutout_still_requires_a_name_and_a_category(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """THE test. The whole point of the temp job is to delay the metadata question,
    NOT to answer it for the user. A create that arrives with a finished cutout and
    no name is exactly as invalid as one without."""
    _enable_r2(monkeypatch)
    conn = _Conn(claim_key=CUTOUT_KEY)
    _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe",
        json={"object_key": ORIGINAL_KEY, "cutout_job_id": str(uuid.uuid4())},
        headers=_auth(),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert conn.written("insert into public.wardrobe_items") == []


def test_adopting_marks_the_item_done_and_never_re_queues_the_worker(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable_r2(monkeypatch)
    job_id = uuid.uuid4()
    conn = _Conn(claim_key=CUTOUT_KEY)
    signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe",
        json={
            "object_key": ORIGINAL_KEY,
            "title": "Linen shirt",
            "category": "Tops",
            "cutout_job_id": str(job_id),
        },
        headers=_auth(),
    )

    assert resp.status_code == 201
    insert = conn.written("insert into public.wardrobe_items")[0]
    # Born done: the cutout exists and the user has already seen it.
    assert "done" in insert[1], "the item is created with the finished cutout"
    # Re-queuing would spend minutes of GPU to reproduce the image on screen.
    assert signals == [], "the rembg worker is never woken for an adopted cutout"
    # The job is stamped in the SAME transaction, so the reaper can never sweep an
    # object a garment now owns.
    assert conn.written("update public.ai_jobs set adopted_at = now()"), "adoption stamped"


def test_a_job_you_do_not_own_or_that_is_unfinished_cannot_be_adopted(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A storage key is not a capability. The lookup is scoped to the JWT user and
    to a completed, unclaimed job; anything else is 404 — never a hint that
    somebody else's job exists."""
    _enable_r2(monkeypatch)
    conn = _Conn(claim_key=None)  # the scoped lookup finds nothing
    _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe",
        json={
            "object_key": ORIGINAL_KEY,
            "title": "Linen shirt",
            "category": "Tops",
            "cutout_job_id": str(uuid.uuid4()),
        },
        headers=_auth(),
    )

    assert resp.status_code == 404
    assert conn.written("insert into public.wardrobe_items") == []


def test_a_create_without_a_cutout_job_still_queues_the_worker(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The pre-existing path is untouched: no temp job means the removal still
    happens the old way, after the item exists."""
    _enable_r2(monkeypatch)
    conn = _Conn()
    signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe",
        json={"object_key": ORIGINAL_KEY, "title": "Linen shirt", "category": "Tops"},
        headers=_auth(),
    )

    assert resp.status_code == 201
    assert [k for k, _ in signals] == ["rembg"]
