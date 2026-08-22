"""Gated local-first cutout ingestion — POST /v1/wardrobe/local-cutout (local BG §6).

The device segmented the garment and uploaded the original straight to R2; here it
sends only the soft mask. The properties these tests defend, in rough order of how
much damage getting them wrong would do:

  * a local success NEVER enqueues the rembg worker — otherwise Azure races a row
    that is already `done` and can overwrite a good cutout;
  * the same original object key can never produce two items or two active media
    rows, including under concurrency;
  * an item is never `done` pointing at objects that do not exist, and a failed
    DB write never leaks the objects it just uploaded — nor touches the original;
  * soft alpha survives byte-exactly, so lace and straps do not become a stencil;
  * nothing here spends a credit or consults membership.
"""

from __future__ import annotations

import io
import time
import uuid

import httpx
import jwt
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.core.config import get_settings
from app.main import app
from app.routers.v1 import wardrobe as mod
from app.services.media import repo as repo_mod
from app.services.media.base import StoredObject
from app.services.media.r2 import R2StorageProvider

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_ID = "user-123"
OTHER_USER = "user-999"

client = TestClient(app)
no_raise = TestClient(app, raise_server_exceptions=False)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token(sub: str = USER_ID) -> str:
    now = int(time.time())
    return jwt.encode(
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


def _auth(sub: str = USER_ID) -> dict:
    return {"Authorization": f"Bearer {_token(sub)}"}


# ── image fixtures ───────────────────────────────────────────────────────────

SIZE = (20, 16)
ORIGINAL_KEY = f"{USER_ID}/wardrobe/{uuid.uuid4().hex}.jpg"


def _jpeg(size: tuple[int, int] = SIZE) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (200, 10, 10)).save(buf, format="JPEG")
    return buf.getvalue()


def _mask(size: tuple[int, int] = SIZE, value: int = 140) -> bytes:
    buf = io.BytesIO()
    Image.new("L", size, value).save(buf, format="PNG")
    return buf.getvalue()


def _files(mask_bytes: bytes | None = None) -> dict:
    return {"mask": ("mask.png", mask_bytes if mask_bytes is not None else _mask(), "image/png")}


def _form(**overrides: object) -> dict:
    data = {
        "original_object_key": ORIGINAL_KEY,
        "engine": "google_mlkit",
        "platform": "android",
        "engine_version": "16.0.0-beta1",
        "local_latency_ms": "1200",
        "subject_count": "1",
        # Name and category are MANDATORY on every manual create path, this one
        # included (spec Phase 1). A gate only one of the two upload doors
        # honours is not a gate, so the local-cutout door carries it too and the
        # fixture supplies it like a real client does.
        "title": "Linen Shirt",
        "category": "Tops",
    }
    data.update({k: str(v) for k, v in overrides.items()})
    return data


def _enable(monkeypatch: pytest.MonkeyPatch, *, r2: bool = True, gate: bool = True) -> None:
    monkeypatch.setenv("LOCAL_CUTOUT_UPLOAD_ENABLED", "true" if gate else "false")
    monkeypatch.setenv("R2_ENDPOINT", "https://acc.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "realkeyid123")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "realsecret456")
    monkeypatch.setenv("R2_PUBLIC_BASE_URL", "https://cdn.example.com")
    monkeypatch.setenv("STORAGE_WRITES", "r2" if r2 else "legacy")
    get_settings.cache_clear()


# ── fake storage provider ────────────────────────────────────────────────────


class _FakeR2(R2StorageProvider):
    """Records puts/deletes instead of talking to R2. Subclasses the real provider
    because `discard_uploaded_objects` isinstance-checks it before deleting."""

    def __init__(self, *, fail_on_put: int | None = None) -> None:
        self.puts: list[tuple[str, bytes, bool]] = []  # (prefix, data, make_thumbnail)
        self.deleted: list[str] = []
        self._fail_on_put = fail_on_put
        self._put_count = 0

    async def put(
        self,
        data: bytes,
        *,
        visibility: str,
        prefix: str,
        content_type: str,
        make_thumbnail: bool = False,
    ) -> StoredObject:
        self._put_count += 1
        if self._fail_on_put == self._put_count:
            raise RuntimeError("R2 unavailable")
        self.puts.append((prefix, data, make_thumbnail))
        key = f"{prefix}/{self._put_count}.png"
        return StoredObject(
            object_key=key,
            bucket="private",
            visibility="private",
            content_hash=f"hash-{self._put_count}",
            thumbnail_key=f"{key}.thumb" if make_thumbnail else None,
        )

    async def view_url(self, *, object_key: str, visibility: str, public_url=None) -> str:
        return f"https://signed.example.com/{object_key}"

    async def delete(self, *, object_key: str, visibility: str, thumbnail_key=None) -> None:
        self.deleted.append(object_key)
        if thumbnail_key:
            self.deleted.append(thumbnail_key)

    def put_bytes(self, prefix_contains: str) -> bytes | None:
        for prefix, data, _ in self.puts:
            if prefix_contains in prefix:
                return data
        return None


# ── scripted fake pool ───────────────────────────────────────────────────────
# Handlers: (method, sql-substring) -> value or callable(sql, args). First match
# wins; anything unmatched returns None / "UPDATE 0".

_COLUMN_ROW = {
    "id": "11111111-1111-1111-1111-111111111111",
    "title": None,
    "category": None,
    "subcategory": None,
    "color": None,
    "pattern": None,
    "brand": None,
    "image_url": ORIGINAL_KEY,
    "cutout_url": "user-123/cutout/1.png",
    "thumbnail_url": "user-123/cutout/1.png",
    "cover_image_url": None,
    "ai_enhanced": False,
    "ai_status": None,
    "tags": [],
    "cost": None,
    "purchase_date": None,
    "last_worn_at": None,
    "wear_count": 0,
    "cutout_status": "done",
    "canonical_category": "top",
    "classification_status": "valid",
    "created_at": "2026-07-27T00:00:00+00:00",
}


class _Tx:
    async def __aenter__(self) -> _Tx:
        return self

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Conn:
    def __init__(self, handlers: list[tuple[str, str, object]]) -> None:
        self.handlers = handlers
        self.calls: list[tuple[str, str, tuple]] = []

    def transaction(self) -> _Tx:
        return _Tx()

    def _dispatch(self, method: str, sql: str, args: tuple) -> object:
        flat = " ".join(sql.split())
        self.calls.append((method, flat, args))
        for m, frag, value in self.handlers:
            if m == method and frag in flat:
                return value(flat, args) if callable(value) else value
        return "UPDATE 0" if method == "execute" else None

    async def fetchrow(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchrow", sql, args)

    async def fetchval(self, sql: str, *args: object) -> object:
        return self._dispatch("fetchval", sql, args)

    async def fetch(self, sql: str, *args: object) -> object:
        return self._dispatch("fetch", sql, args) or []

    async def execute(self, sql: str, *args: object) -> object:
        return self._dispatch("execute", sql, args)

    def sql_calls(self, fragment: str) -> list[tuple[str, str, tuple]]:
        return [c for c in self.calls if fragment in c[1]]


class _Acquire:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _Conn:
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self) -> _Acquire:
        return _Acquire(self.conn)


def _base_handlers(existing_item: object = None) -> list[tuple[str, str, object]]:
    """The happy path: limiter allows, no existing item, inserts succeed."""
    return [
        ("fetchval", "app_rate_limit", True),
        ("fetchval", "from public.media_assets m", existing_item),
        ("fetchrow", "insert into public.wardrobe_items", dict(_COLUMN_ROW)),
        ("fetchval", "insert into public.media_assets", lambda s, a: str(uuid.uuid4())),
        ("fetchrow", "select id, title", dict(_COLUMN_ROW)),
        ("fetch", "from public.media_assets", []),
    ]


def _wire(
    monkeypatch: pytest.MonkeyPatch,
    conn: _Conn,
    provider: _FakeR2 | None = None,
    *,
    original: bytes | None = None,
    download_error: Exception | None = None,
) -> tuple[_FakeR2, list[tuple[str, str]]]:
    r2 = provider or _FakeR2()
    signals: list[tuple[str, str]] = []

    async def _download(url: str) -> bytes:
        if download_error is not None:
            raise download_error
        return original if original is not None else _jpeg()

    async def _enqueue(kind: str, job_id: str, **kw: object) -> bool:
        signals.append((kind, job_id))
        return True

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    monkeypatch.setattr(mod, "get_storage_provider", lambda: r2)
    monkeypatch.setattr(repo_mod, "get_storage_provider", lambda: r2)
    monkeypatch.setattr(mod, "download_image", _download)
    monkeypatch.setattr(mod, "enqueue_signal", _enqueue)
    return r2, signals


# ── gates ────────────────────────────────────────────────────────────────────


def test_requires_a_token() -> None:
    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files())
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_gate_off_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    # Dormant by default: the endpoint is invisible even to an authenticated owner,
    # so a deploy of this branch changes nothing.
    monkeypatch.delenv("LOCAL_CUTOUT_UPLOAD_ENABLED", raising=False)
    get_settings.cache_clear()
    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"


def test_the_emergency_switch_returns_503_not_404(monkeypatch: pytest.MonkeyPatch) -> None:
    """An incident is a different answer from "this build never had the feature".

    404 means the endpoint does not exist in this deployment; 503 means it exists
    and is switched off right now. The client falls back to the cloud path either
    way, so the user is unaffected -- but the two are distinguishable in telemetry,
    and an outage that reads as "feature was never here" is precisely how the last
    one stayed invisible for a whole release.
    """
    _enable(monkeypatch)
    monkeypatch.setenv("LOCAL_CUTOUT_EMERGENCY_DISABLE", "true")
    get_settings.cache_clear()
    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"


def test_the_emergency_switch_defaults_off(monkeypatch: pytest.MonkeyPatch) -> None:
    # Deploying this code must not switch anything off. Absent == normal operation.
    _enable(monkeypatch)
    monkeypatch.delenv("LOCAL_CUTOUT_EMERGENCY_DISABLE", raising=False)
    get_settings.cache_clear()
    assert get_settings().local_cutout_emergency_disable is False


def test_r2_disabled_returns_503(monkeypatch: pytest.MonkeyPatch) -> None:
    # Gate on but no private storage → a clear feature-unavailable so the app
    # falls back to the existing cloud create rather than failing the add.
    _enable(monkeypatch, r2=False)
    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"


def test_unknown_engine_or_platform_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    for override in ({"engine": "some_paid_api"}, {"platform": "web"}):
        resp = client.post(
            "/v1/wardrobe/local-cutout",
            data=_form(**override),
            files=_files(),
            headers=_auth(),
        )
        assert resp.status_code == 422, override
        assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


# ── mandatory metadata, on THIS door too (spec Phase 1) ──────────────────────
#
# This endpoint is a CREATE, not a pure processing call: it ingests the device's
# mask AND inserts the wardrobe row. So it carries the same mandatory name +
# category as `POST /v1/wardrobe`, and a client that runs the background removal
# before collecting them has nowhere to put the result.
#
# That is exactly what shipped: the Atelier add screen created the piece first
# and asked for its name afterwards, so every add died here with
# "Give this piece a name before saving it." at the end of a removal that had
# worked perfectly. The fix is client-side — the metadata is collected before the
# removal starts — and these tests pin the server half of the contract so the
# enforcement can never be quietly relaxed to accommodate a client that forgets.


@pytest.mark.parametrize(
    "missing",
    [("title",), ("category",), ("title", "category")],
    ids=["no-name", "no-category", "neither"],
)
def test_local_ingest_without_name_or_category_is_refused(
    monkeypatch: pytest.MonkeyPatch, missing: tuple[str, ...]
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    form = {k: v for k, v in _form().items() if k not in missing}
    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=form,
        files=_files(),
        headers=_auth(),
    )

    assert resp.status_code == 422, missing
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    # Checked before the original is fetched and the mask decoded, so a rejected
    # request costs nothing but a round trip — and leaks no half-made piece.
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


def test_local_ingest_with_blank_metadata_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    """Whitespace is not a name. A client that "supplies" both fields as spaces
    must not be able to create the very row the rule exists to prevent."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(title="   ", category="  "),
        files=_files(),
        headers=_auth(),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


# ── object-key ownership + prefix ────────────────────────────────────────────


@pytest.mark.parametrize(
    "key",
    [
        f"{OTHER_USER}/wardrobe/abc.jpg",  # another user's object
        f"{USER_ID}/avatar/abc.jpg",  # right user, WRONG private sector
        f"{USER_ID}/tryon_photo/abc.jpg",  # biometric sector — never a garment
        f"{USER_ID}/wardrobe/",  # prefix only, no object
        f"{USER_ID}/wardrobe/../../etc/passwd",  # traversal
        f"{USER_ID}/wardrobe//abc.jpg",  # double slash
        "wardrobe/abc.jpg",  # unscoped
        "   ",  # whitespace only
        f"{USER_ID}/wardrobe/{'x' * 600}.jpg",  # over the 512-char cap
    ],
)
def test_foreign_or_malformed_object_keys_are_404(
    monkeypatch: pytest.MonkeyPatch, key: str
) -> None:
    # 404 (not 403) on every failure: the endpoint must never confirm whether
    # another user's object exists.
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(original_object_key=key),
        files=_files(),
        headers=_auth(),
    )
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"
    # Rejected before any download, upload, insert or signal.
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


def test_a_blank_object_key_is_rejected_and_creates_nothing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A blank key never reaches the handler: the framework rejects a required
    ``Form`` field supplied as an empty string as MISSING, so it is a 422.

    This assertion used to expect 404, on the reasoning that a blank key is a valid
    ``str`` and would reach the handler to be refused indistinguishably from
    someone else's key. That stopped being true when the pinned Starlette/FastAPI
    began treating an empty required form value as absent — the request is rejected
    at validation, before any handler code runs. The expectation was describing the
    framework, not our contract, so it follows the framework.

    The security property is unaffected and is NOT weakened here: an empty string
    is not a probe (there is nothing to enumerate with it). What matters is that a
    well-formed key belonging to someone else is indistinguishable from a malformed
    one, and `test_foreign_or_malformed_object_keys_are_404` asserts exactly that,
    for real keys, and still passes.

    What this test is really for — that a rejected request creates NOTHING — is
    unchanged and still asserted below.
    """
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(original_object_key=""),
        files=_files(),
        headers=_auth(),
    )
    assert resp.status_code == 422
    # Rejected before any download, upload, insert or signal — the point of the test.
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


def test_an_absent_object_key_is_rejected_and_creates_nothing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Omitting the field entirely never reaches the handler: the required Form
    field fails first, so this one IS a 422. Still creates nothing."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    without_key = {k: v for k, v in _form().items() if k != "original_object_key"}
    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=without_key,
        files=_files(),
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


# ── mask validation ──────────────────────────────────────────────────────────


def _rgba_mask_with_opaque_alpha(size: tuple[int, int] = SIZE, value: int = 140) -> bytes:
    """The mask shape that broke the device flow: confidence in R/G/B, alpha 0xFF.

    This is exactly what Android's `Bitmap.compress(PNG)` produced before the
    2026-07-29 fix — and `compress` emits RGBA even when every alpha byte is 0xFF,
    so it is a shape a client can very plausibly send again.
    """
    buf = io.BytesIO()
    Image.new("RGBA", size, (value, value, value, 255)).save(buf, format="PNG")
    return buf.getvalue()


def test_an_rgba_mask_with_opaque_alpha_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """The server reduces an alpha-bearing mask via its ALPHA band, never luminance
    (`imaging._extract_mask_channel` checks RGBA/LA/PA first). A uniformly opaque
    alpha therefore measures coverage 1.0, above `_MAX_LOCAL_ALPHA_AREA`, and must be
    refused — creating nothing and spending nothing.

    Pinned from this side too because the client is what got this wrong: it wrote the
    confidence into R/G/B with `alpha = 0xFF`, which made the mask read as fully
    present and 422'd every single ingest while all client tests stayed green.
    """
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(),
        files=_files(_rgba_mask_with_opaque_alpha()),
        headers=_auth(),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    # Nothing persisted: no cutout/mask objects, no item row, no usage signal.
    assert r2.puts == [] and signals == []
    assert conn.sql_calls("insert into public.wardrobe_items") == []


def test_an_rgba_mask_carrying_the_value_in_alpha_is_accepted(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The counterpart, so the pair documents the whole contract: the SAME RGBA
    container is fine once the confidence is in the alpha band — which is what the
    fixed Android encoder now emits."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, _ = _wire(monkeypatch, conn)

    buf = io.BytesIO()
    Image.new("RGBA", SIZE, (140, 140, 140, 140)).save(buf, format="PNG")

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(),
        files=_files(buf.getvalue()),
        headers=_auth(),
    )

    assert resp.status_code == 201
    assert r2.puts != []


def test_oversized_mask_is_rejected_before_decode(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    monkeypatch.setenv("BG_MASK_UPLOAD_MAX_BYTES", "64")
    get_settings.cache_clear()
    conn = _Conn(_base_handlers())
    r2, _ = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(),
        files=_files(_mask((400, 400), 200)),
        headers=_auth(),
    )
    assert resp.status_code == 413
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert r2.puts == []  # nothing decoded, nothing stored


@pytest.mark.parametrize(
    ("mask_bytes", "label"),
    [
        (b"not-a-png", "malformed"),
        (_jpeg(SIZE), "a JPEG rather than a PNG"),
        (_mask((8, 8)), "wrong dimensions"),
        (_mask(SIZE, 0), "empty (nothing selected)"),
        (_mask(SIZE, 255), "near-full (segmentation failed open)"),
    ],
)
def test_invalid_masks_are_422_and_create_nothing(
    monkeypatch: pytest.MonkeyPatch, mask_bytes: bytes, label: str
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout", data=_form(), files=_files(mask_bytes), headers=_auth()
    )
    assert resp.status_code == 422, label
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    # No item is created, so the app can safely fall back to the cloud create
    # with the SAME original object key (§6.3).
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert r2.puts == [] and signals == []


def test_an_unclassifiable_read_error_is_treated_as_retryable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Phase 7 taxonomy: an error we cannot classify defaults to TRANSIENT.

    Guessing "terminal" would strand a recoverable add behind a reselect-the-photo
    message. Only a definitively absent object (403/404/410) or bytes that will not
    decode are terminal — see the SOURCE_MISSING tests below.
    """
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn, download_error=RuntimeError("something odd"))

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert r2.puts == [] and signals == []


def test_error_message_never_leaks_the_object_key(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn, download_error=RuntimeError("https://signed.example.com/secret"))

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    body = resp.text
    assert ORIGINAL_KEY not in body
    assert "signed.example.com" not in body


# ── success ──────────────────────────────────────────────────────────────────


def test_success_creates_a_done_item_without_queuing_birefnet(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 201
    assert resp.json()["cutout_status"] == "done"

    # THE critical property: no rembg signal, so the Azure worker can never claim
    # and re-process a row that is already finished.
    assert all(kind != "rembg" for kind, _ in signals), signals
    # Enrichment (tagging/embedding) still runs, off the visual critical path.
    assert [kind for kind, _ in signals] == ["enrichment"]

    inserts = conn.sql_calls("insert into public.wardrobe_items")
    assert len(inserts) == 1
    assert "'done'" in inserts[0][1]


def test_success_stores_cutout_with_thumbnail_and_editable_mask(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, _ = _wire(monkeypatch, conn)

    client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    prefixes = {prefix: thumb for prefix, _, thumb in r2.puts}
    assert prefixes == {f"{USER_ID}/cutout": True, f"{USER_ID}/cutout-mask": False}


def test_success_writes_exactly_three_active_media_rows(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    ledger = conn.sql_calls("insert into public.media_assets")
    assert len(ledger) == 3
    roles = [call[2][2] for call in ledger]  # $3 = role
    assert roles == ["original", "cutout", "cutout_mask"]
    # The original row points at the key the CLIENT uploaded, untouched.
    assert ledger[0][2][6] == ORIGINAL_KEY


def test_success_preserves_soft_alpha_byte_exactly(monkeypatch: pytest.MonkeyPatch) -> None:
    # 140 is an intermediate value. If anything in the path thresholds the mask,
    # lace, chiffon and thin straps turn into a hard stencil.
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, _ = _wire(monkeypatch, conn)

    client.post(
        "/v1/wardrobe/local-cutout", data=_form(), files=_files(_mask(SIZE, 140)), headers=_auth()
    )

    cutout = Image.open(io.BytesIO(r2.put_bytes("cutout") or b""))
    assert cutout.mode == "RGBA" and cutout.size == SIZE
    assert cutout.getpixel((10, 8))[3] == 140

    stored_mask = Image.open(io.BytesIO(r2.put_bytes("cutout-mask") or b""))
    assert stored_mask.mode == "L" and stored_mask.getpixel((10, 8)) == 140


def test_success_logs_a_zero_cost_usage_row(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    usage = conn.sql_calls("insert into public.ai_usage_log")
    assert len(usage) == 1
    sql, args = usage[0][1], usage[0][2]
    assert "estimated_usd" in sql and ", 0," in sql  # literal zero cost
    assert args[1] == "local:google_mlkit"


def test_success_never_touches_credits_or_membership(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 201
    touched = [c for c in conn.calls if "credits" in c[1] or "entitlement" in c[1]]
    assert touched == []


def test_apple_vision_engine_is_accepted(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(engine="apple_vision", platform="ios"),
        files=_files(),
        headers=_auth(),
    )
    assert resp.status_code == 201
    assert conn.sql_calls("insert into public.ai_usage_log")[0][2][1] == "local:apple_vision"


# ── idempotency ──────────────────────────────────────────────────────────────


def test_retry_after_a_lost_response_returns_the_existing_item(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The commit succeeded but the client never saw the response. The retry must
    # return that item — not a second one, and not a second cutout.
    _enable(monkeypatch)
    existing = "22222222-2222-2222-2222-222222222222"
    conn = _Conn(_base_handlers(existing_item=existing))
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 200  # 200, not 201 — nothing new was created
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert conn.sql_calls("insert into public.media_assets") == []
    assert r2.puts == [] and r2.deleted == [] and signals == []


def test_lost_race_serves_the_winner_and_discards_our_objects(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Two concurrent requests with the same key: the unlocked pre-check misses for
    both, then the advisory lock serialises them and the loser finds the winner's
    item. The loser must create nothing and leak nothing."""
    _enable(monkeypatch)
    winner = "33333333-3333-3333-3333-333333333333"
    seen = {"n": 0}

    def _lookup(sql: str, args: tuple) -> object:
        seen["n"] += 1
        return None if seen["n"] == 1 else winner  # miss unlocked, hit under lock

    handlers = _base_handlers()
    handlers[1] = ("fetchval", "from public.media_assets m", _lookup)
    conn = _Conn(handlers)
    r2, signals = _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 200
    # Exactly one item exists overall — the loser inserted nothing.
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert conn.sql_calls("insert into public.media_assets") == []
    # ...and its two uploaded objects (+ the cutout thumbnail) were cleaned up.
    assert len(r2.puts) == 2
    assert {p.rsplit("/", 1)[-1] for p in r2.deleted} >= {"1.png", "2.png"}
    # The client's ORIGINAL is never deleted — the winner's item references it.
    assert ORIGINAL_KEY not in r2.deleted
    assert signals == []


def test_the_advisory_lock_is_taken_before_the_authoritative_lookup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Ordering is the whole guarantee: lock -> re-check -> insert.
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    order = [
        i
        for i, (_, sql, _) in enumerate(conn.calls)
        if "pg_advisory_xact_lock" in sql
        or "from public.media_assets m" in sql
        or "insert into public.wardrobe_items" in sql
    ]
    kinds = [
        "lock"
        if "pg_advisory_xact_lock" in conn.calls[i][1]
        else "lookup"
        if "from public.media_assets m" in conn.calls[i][1]
        else "insert"
        for i in order
    ]
    # The unlocked fast-path lookup, then lock, then the authoritative lookup, then insert.
    assert kinds == ["lookup", "lock", "lookup", "insert"]


def test_the_advisory_lock_key_is_hashed_by_postgres(monkeypatch: pytest.MonkeyPatch) -> None:
    """Python's hash() is salted per process (PYTHONHASHSEED), so two API dynos
    would take DIFFERENT locks and the mutual exclusion would silently vanish.
    The hash must therefore be computed in SQL, from the object key itself."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    lock = conn.sql_calls("pg_advisory_xact_lock")
    assert len(lock) == 1
    assert "hashtext($2)" in lock[0][1]
    assert lock[0][2][1] == ORIGINAL_KEY  # the key itself is the lock identity


# ── failure semantics ────────────────────────────────────────────────────────


def test_storage_failure_creates_no_item(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn, _FakeR2(fail_on_put=1))

    resp = no_raise.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 500
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert signals == []


def test_mask_upload_failure_discards_the_orphaned_cutout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The cutout landed, the mask did not. The cutout is now unreferenced.
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, _ = _wire(monkeypatch, conn, _FakeR2(fail_on_put=2))

    resp = no_raise.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 500
    assert any("cutout" in key for key in r2.deleted)
    assert ORIGINAL_KEY not in r2.deleted
    assert conn.sql_calls("insert into public.wardrobe_items") == []


def test_db_failure_after_upload_cleans_the_new_objects_but_not_the_original(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)

    def _boom(sql: str, args: tuple) -> object:
        raise RuntimeError("deadlock detected")

    handlers = _base_handlers()
    handlers[2] = ("fetchrow", "insert into public.wardrobe_items", _boom)
    conn = _Conn(handlers)
    r2, signals = _wire(monkeypatch, conn)

    resp = no_raise.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 500
    # Both freshly generated objects (and the cutout thumbnail) go...
    assert len(r2.puts) == 2
    assert {p.rsplit("/", 1)[-1] for p in r2.deleted} >= {"1.png", "2.png"}
    # ...but the user's uploaded original is NEVER deleted: this is a retryable
    # failure and the app may still create the item through the cloud path.
    assert ORIGINAL_KEY not in r2.deleted
    assert signals == []


def test_ledger_failure_also_cleans_up(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)

    def _boom(sql: str, args: tuple) -> object:
        raise RuntimeError("constraint violation")

    handlers = _base_handlers()
    handlers[3] = ("fetchval", "insert into public.media_assets", _boom)
    conn = _Conn(handlers)
    r2, _ = _wire(monkeypatch, conn)

    resp = no_raise.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 500
    assert {p.rsplit("/", 1)[-1] for p in r2.deleted} >= {"1.png", "2.png"}
    assert ORIGINAL_KEY not in r2.deleted


def test_a_usage_log_failure_does_not_undo_a_committed_item(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Observability is best-effort: the item is already committed and the user
    # must not see an error for it.
    _enable(monkeypatch)

    def _boom(sql: str, args: tuple) -> object:
        raise RuntimeError("ai_usage_log unavailable")

    handlers = _base_handlers()
    handlers.insert(0, ("execute", "insert into public.ai_usage_log", _boom))
    conn = _Conn(handlers)
    _wire(monkeypatch, conn)

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())
    assert resp.status_code == 201


# ── the existing cloud path is untouched ─────────────────────────────────────


def test_normal_wardrobe_create_still_queues_birefnet(monkeypatch: pytest.MonkeyPatch) -> None:
    """The regression guard for the whole phase: POST /v1/wardrobe must keep
    creating a `queued` item and signalling the rembg worker."""
    _enable(monkeypatch)
    handlers = _base_handlers()
    handlers.append(("execute", "cutout_last_signal_at", "UPDATE 1"))
    conn = _Conn(handlers)
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe",
        json={"title": "White tee", "category": "Tops", "object_key": ORIGINAL_KEY},
        headers=_auth(),
    )

    assert resp.status_code == 201
    inserts = conn.sql_calls("insert into public.wardrobe_items")
    assert len(inserts) == 1
    assert "cutout_status" in inserts[0][1]
    assert inserts[0][2][11] == "queued"  # $12 = cutout_status
    assert [kind for kind, _ in signals] == ["rembg"]


def test_local_endpoint_did_not_change_the_editor_gate(monkeypatch: pytest.MonkeyPatch) -> None:
    """The editor has its OWN gate; enabling local ingestion must not expose it."""
    _enable(monkeypatch)
    monkeypatch.delenv("CUTOUT_EDITOR_ENABLED", raising=False)
    get_settings.cache_clear()

    resp = client.put(
        f"/v1/wardrobe/{uuid.uuid4()}/cutout-mask",
        files={"mask": ("m.png", _mask(), "image/png")},
        headers=_auth(),
    )
    assert resp.status_code == 404


# ── source-missing taxonomy (Phase 7) ────────────────────────────────────────
# Three outcomes, because the BiRefNet worker reads the SAME stored object:
#   * definitively absent / undecodable -> SOURCE_MISSING 422, TERMINAL
#   * transient storage failure         -> PROVIDER_ERROR 503, retryable
#   * bad MASK                          -> VALIDATION_ERROR 422, cloud-recoverable


def _http_error(status: int) -> httpx.HTTPStatusError:
    request = httpx.Request("GET", "https://signed.example.com/secret-key")
    response = httpx.Response(status, request=request)
    return httpx.HTTPStatusError("boom", request=request, response=response)


@pytest.mark.parametrize("status", [403, 404, 410])
def test_absent_original_is_terminal_source_missing(
    monkeypatch: pytest.MonkeyPatch, status: int
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn, download_error=_http_error(status))

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "SOURCE_MISSING"
    # Nothing created, nothing uploaded, and crucially NO queue signal: the worker
    # would fail on the same object.
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert r2.puts == [] and signals == []


@pytest.mark.parametrize("status", [500, 502, 503, 429])
def test_transient_storage_failure_is_retryable_provider_error(
    monkeypatch: pytest.MonkeyPatch, status: int
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _r2, signals = _wire(monkeypatch, conn, download_error=_http_error(status))

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert signals == []


def test_network_error_reading_the_original_is_retryable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn, download_error=httpx.ConnectTimeout("slow"))

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"


def test_undecodable_original_is_terminal_source_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The object EXISTS but its bytes are not an image. The worker would choke on
    # exactly the same bytes, so this is terminal rather than a cloud fallback.
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    r2, signals = _wire(monkeypatch, conn, original=b"not-an-image-at-all")

    resp = client.post("/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth())

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "SOURCE_MISSING"
    assert conn.sql_calls("insert into public.wardrobe_items") == []
    assert r2.puts == [] and signals == []


def test_a_bad_mask_stays_a_recoverable_validation_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The distinction that makes the taxonomy worth having: the ORIGINAL is fine,
    so the cloud path can still succeed and must not be pre-empted."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(),
        files=_files(_mask((8, 8))),  # wrong dimensions
        headers=_auth(),
    )

    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_no_storage_detail_leaks_in_any_source_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    for error in [_http_error(404), _http_error(500), httpx.ConnectTimeout("x")]:
        conn = _Conn(_base_handlers())
        _wire(monkeypatch, conn, download_error=error)
        resp = client.post(
            "/v1/wardrobe/local-cutout", data=_form(), files=_files(), headers=_auth()
        )
        body = resp.text
        assert ORIGINAL_KEY not in body
        assert "signed.example.com" not in body
        assert "secret-key" not in body


# ── pre-uploaded mask ────────────────────────────────────────────────────────
#
# The mask may be PUT to the private wardrobe sector while the user is still
# naming the piece, and referenced by key at Save. That turns Save from "start a
# multipart upload now" into a small form post, which is most of the wait users
# saw between tapping Save and the closet appearing.
#
# The key is not trusted: it is validated exactly like the original's.


def _staged_download(monkeypatch: pytest.MonkeyPatch, mask_bytes: bytes) -> None:
    """Serve the MASK on the first fetch and the ORIGINAL on the second.

    The endpoint resolves a staged mask before it resolves the original, so call
    order is what distinguishes them — the fake provider hands back an opaque
    signed URL either way.
    """
    calls = {"n": 0}

    async def _download(url: str) -> bytes:
        calls["n"] += 1
        return mask_bytes if calls["n"] == 1 else _jpeg()

    monkeypatch.setattr(mod, "download_image", _download)


def test_staged_mask_key_creates_the_item_without_an_upload_part(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)
    _staged_download(monkeypatch, _mask())

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(mask_object_key=f"{USER_ID}/wardrobe/{uuid.uuid4().hex}.png"),
        headers=_auth(),
    )
    assert resp.status_code == 201, resp.text


def test_a_mask_must_be_supplied_exactly_one_way(monkeypatch: pytest.MonkeyPatch) -> None:
    """Neither is unusable; both is ambiguous. Refuse rather than pick one."""
    _enable(monkeypatch)
    staged = f"{USER_ID}/wardrobe/{uuid.uuid4().hex}.png"

    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)
    neither = client.post("/v1/wardrobe/local-cutout", data=_form(), headers=_auth())
    assert neither.status_code == 422, neither.text

    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)
    both = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(mask_object_key=staged),
        files=_files(),
        headers=_auth(),
    )
    assert both.status_code == 422, both.text


def test_staged_mask_belonging_to_another_user_is_not_found(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A storage key is not a capability — and the answer must not confirm the
    object exists, or this becomes a probe for other people's uploads (§11)."""
    _enable(monkeypatch)
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)
    _staged_download(monkeypatch, _mask())

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(mask_object_key=f"{OTHER_USER}/wardrobe/{uuid.uuid4().hex}.png"),
        headers=_auth(),
    )
    assert resp.status_code == 404, resp.text


def test_staged_mask_is_size_capped_like_an_inline_upload(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Otherwise pre-uploading would be the way to hand the compositor an object
    no size limit ever saw."""
    _enable(monkeypatch)
    monkeypatch.setenv("BG_MASK_UPLOAD_MAX_BYTES", "64")
    get_settings.cache_clear()
    conn = _Conn(_base_handlers())
    _wire(monkeypatch, conn)
    _staged_download(monkeypatch, _mask())

    resp = client.post(
        "/v1/wardrobe/local-cutout",
        data=_form(mask_object_key=f"{USER_ID}/wardrobe/{uuid.uuid4().hex}.png"),
        headers=_auth(),
    )
    get_settings.cache_clear()
    assert resp.status_code == 422, resp.text
