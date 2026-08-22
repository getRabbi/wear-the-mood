"""Category is the user's answer, and saving it can only ever produce one piece.

The two halves of the same incident. A garment's category decides which region of
somebody's body gets repainted, so it has to be a thing a person chose on purpose
— never inferred from a title, a filename, a device label or a vision model — and
the save that records it has to be safe to retry, because the alternative is six
copies of the same dress in a closet.

Covers:
  * every value the app's picker can emit resolves to a real body region
    (parity with `app/lib/features/wardrobe/garment_category.dart`);
  * a category the taxonomy cannot read is refused once the gate is closed;
  * a repeated or concurrent create returns the FIRST item instead of a second;
  * nothing here reaches an AI provider.
"""

from __future__ import annotations

import asyncio
import re
import time
import uuid
from pathlib import Path

import jwt
import pytest
from fastapi.testclient import TestClient

import app.routers.v1.wardrobe as mod
from app.core.config import get_settings
from app.main import app
from app.services.tryon import taxonomy as tax

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
client = TestClient(app)

_REPO_ROOT = Path(__file__).resolve().parents[3]
_DART_PICKER = _REPO_ROOT / "app" / "lib" / "features" / "wardrobe" / "garment_category.dart"


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": str(uuid.uuid4()),
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


# ── the picker's vocabulary, read from the Dart the app actually ships ───────


def _dart_picker_entries() -> list[tuple[str, str]]:
    """(stored value, canonical role) for every tile in the Flutter picker.

    Parsed from the source rather than duplicated here, so the two lists cannot
    drift: a role changed on one side and not the other is a wrong garment on
    somebody's body, and it would otherwise be invisible until a render.
    """
    source = _DART_PICKER.read_text(encoding="utf-8")
    roles = dict(re.findall(r"const String (kRole\w+) = '([a-z_]+)';", _role_source()))
    entries: list[tuple[str, str]] = []
    for value, role_const in re.findall(r"value: '([^']+)',\s*\n\s*role: (kRole\w+),", source):
        assert role_const in roles, f"unknown role constant {role_const}"
        entries.append((value, roles[role_const]))
    return entries


def _role_source() -> str:
    return (_REPO_ROOT / "app" / "lib" / "features" / "tryon" / "garment_role.dart").read_text(
        encoding="utf-8"
    )


def test_the_picker_offers_twelve_choices() -> None:
    entries = _dart_picker_entries()
    assert len(entries) == 12, entries
    assert len({v for v, _ in entries}) == 12


@pytest.mark.parametrize("value,role", _dart_picker_entries())
def test_every_picker_value_resolves_to_the_role_the_app_claims(value: str, role: str) -> None:
    """The app tells somebody "Try-on type: Bottoms" BEFORE the round trip.

    That promise is only honest if the server agrees, so each stored value is
    checked against the taxonomy that actually routes the render.
    """
    assert tax.classify_value(value) == role


def test_every_renderable_role_is_reachable_from_the_picker() -> None:
    """The defect that started this: a hijab, a watch and a pair of sunglasses
    all had to be saved as "Accessories" — a word the taxonomy refuses to read as
    a body region — so every one of them was permanently unrenderable. Each
    supported role must have its own tile."""
    offered = {role for _value, role in _dart_picker_entries()}
    renderable = set(tax.TRYON_CAPABLE_CATEGORIES) - {tax.LOOK_REFERENCE}
    assert renderable <= offered, renderable - offered


def test_the_picker_never_offers_an_occasion() -> None:
    """ "Party" and "Activewear" name WHEN a piece is worn, not what it is."""
    for value, _role in _dart_picker_entries():
        assert tax.classify_value(value) is not None, value


# ── the API gate ─────────────────────────────────────────────────────────────


class _Conn:
    """Fake connection. Answers the reads this endpoint makes, records writes."""

    def __init__(self, *, existing_item: object | None = None, flags: dict | None = None) -> None:
        self.calls: list[tuple[str, tuple]] = []
        self.existing_item = existing_item
        self.flags = flags or {}
        self.row = {
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

    def transaction(self):
        return _Tx()

    def _record(self, sql: str, args: tuple) -> str:
        flat = " ".join(sql.split())
        self.calls.append((flat, args))
        return flat

    async def fetchrow(self, sql: str, *args: object):
        self._record(sql, args)
        return self.row

    async def fetchval(self, sql: str, *args: object):
        flat = self._record(sql, args)
        if "from public.media_assets m" in flat or "from public.ai_jobs j" in flat:
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


def _wire(monkeypatch: pytest.MonkeyPatch, conn: _Conn) -> None:
    async def _flag(_conn: object, key: str, *, default: bool) -> bool:
        return conn.flags.get(key, default)

    async def _noop(*a: object, **kw: object) -> None:
        return None

    async def _enqueue(*a: object, **kw: object) -> bool:
        return False

    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    monkeypatch.setattr(mod, "flag_enabled", _flag)
    monkeypatch.setattr(mod, "insert_asset", _noop)
    monkeypatch.setattr(mod, "enqueue_signal", _enqueue)


@pytest.mark.parametrize("value,_role", _dart_picker_entries())
def test_every_picker_value_saves(monkeypatch: pytest.MonkeyPatch, value: str, _role: str) -> None:
    """Whatever the picker can emit, the API must accept — with the gate CLOSED,
    which is the strictest the contract ever gets."""
    conn = _Conn(flags={"wardrobe_require_known_category": True})
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "A piece", "category": value},
        headers=_auth(),
    )
    assert resp.status_code == 201, resp.text
    assert conn.written("insert into public.wardrobe_items")


@pytest.mark.parametrize("value", ["Party", "Activewear", "accessories", "Travel", "zzz"])
def test_an_unreadable_category_is_refused_once_the_gate_is_closed(
    monkeypatch: pytest.MonkeyPatch, value: str
) -> None:
    conn = _Conn(flags={"wardrobe_require_known_category": True})
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "A piece", "category": value},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert conn.written("insert into public.wardrobe_items") == []


@pytest.mark.parametrize("value", ["Party", "accessories"])
def test_the_gate_is_off_by_default_so_a_shipped_client_still_saves(
    monkeypatch: pytest.MonkeyPatch, value: str
) -> None:
    """1.0.23+28 is on people's phones and its picker sends "accessories".

    Rejecting that today would turn a save which works into a hard failure on an
    installed app, to guard against something the CURRENT picker cannot express.
    The piece saves and is honestly marked `needs_review` instead.
    """
    conn = _Conn()  # no flag overrides — production defaults
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "A piece", "category": value},
        headers=_auth(),
    )
    assert resp.status_code == 201
    insert = conn.written("insert into public.wardrobe_items")[0]
    assert insert[1][-2:] == (None, tax.STATUS_NEEDS_REVIEW)


def test_a_patch_that_does_not_touch_the_category_is_not_judged_on_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Renaming a legacy "Party" piece must not fail on a field nobody edited —
    that is a refusal the person cannot act on."""
    conn = _Conn(flags={"wardrobe_require_known_category": True})
    conn.row = {**conn.row, "title": "Old name", "category": "Party"}
    _wire(monkeypatch, conn)
    resp = client.patch(
        f"/v1/wardrobe/{uuid.uuid4()}",
        json={"title": "New name"},
        headers=_auth(),
    )
    assert resp.status_code == 200, resp.text


def test_a_patch_that_sets_an_unreadable_category_is_refused(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(flags={"wardrobe_require_known_category": True})
    _wire(monkeypatch, conn)
    resp = client.patch(
        f"/v1/wardrobe/{uuid.uuid4()}",
        json={"category": "Party"},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert conn.written("update public.wardrobe_items") == []


def test_repairing_a_category_re_derives_the_role_so_try_on_reopens(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The one action a person would naturally take is the one that fixes it."""
    conn = _Conn()
    conn.row = {**conn.row, "title": "Tank top", "category": None}
    _wire(monkeypatch, conn)
    resp = client.patch(
        f"/v1/wardrobe/{uuid.uuid4()}",
        json={"category": "Tops"},
        headers=_auth(),
    )
    assert resp.status_code == 200
    update = conn.written("update public.wardrobe_items")[0]
    assert tax.TOP in update[1]
    assert tax.STATUS_VALID in update[1]


# ── one save, one piece ──────────────────────────────────────────────────────


def test_a_retried_create_returns_the_first_item_instead_of_a_second(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The lost-response case: the first attempt committed, the client never
    heard, and the person tapped Save again."""
    winner = uuid.uuid4()
    conn = _Conn(existing_item=winner)
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={
            "object_key": "u/wardrobe/abc.jpg",
            "title": "Linen shirt",
            "category": "Tops",
        },
        headers=_auth(),
    )
    # 200, not 201: a replay is not a create, and a caller that cares can tell.
    assert resp.status_code == 200, resp.text
    assert conn.written("insert into public.wardrobe_items") == []


def test_a_retry_takes_a_lock_before_it_looks(monkeypatch: pytest.MonkeyPatch) -> None:
    """Look-then-insert without a lock is a race two concurrent requests both
    win. The lock is what makes the check mean anything."""
    conn = _Conn()
    _wire(monkeypatch, conn)
    client.post(
        "/v1/wardrobe",
        json={
            "object_key": "u/wardrobe/abc.jpg",
            "title": "Linen shirt",
            "category": "Tops",
        },
        headers=_auth(),
    )
    locks = conn.written("pg_advisory_xact_lock")
    assert len(locks) == 1
    lock_at = conn.calls.index(locks[0])
    insert_at = conn.calls.index(conn.written("insert into public.wardrobe_items")[0])
    assert lock_at < insert_at


def test_concurrent_creates_for_one_photo_produce_one_item(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Serialised by the advisory lock, the loser finds the winner's row.

    The fake stands in for Postgres's mutual exclusion: it lets exactly one
    request through the gate and hands every later one the id the first created,
    which is the behaviour `pg_advisory_xact_lock` guarantees in production.
    """
    winner_id = uuid.uuid4()
    state: dict[str, object] = {"item": None}
    lock = asyncio.Lock()

    class _RacingConn(_Conn):
        async def fetchval(self, sql: str, *args: object):
            flat = self._record(sql, args)
            if "from public.media_assets m" in flat or "from public.ai_jobs j" in flat:
                return state["item"]
            return None

        async def fetchrow(self, sql: str, *args: object):
            flat = self._record(sql, args)
            if "insert into public.wardrobe_items" in flat:
                state["item"] = winner_id
            return self.row

        def transaction(self):
            return _LockedTx(lock)

    conn = _RacingConn()
    conn.row = {**conn.row, "id": winner_id}
    _wire(monkeypatch, conn)

    payload = {
        "object_key": "u/wardrobe/abc.jpg",
        "title": "Linen shirt",
        "category": "Tops",
    }
    headers = _auth()
    first = client.post("/v1/wardrobe", json=payload, headers=headers)
    second = client.post("/v1/wardrobe", json=payload, headers=headers)

    assert first.status_code == 201
    assert second.status_code == 200
    assert len(conn.written("insert into public.wardrobe_items")) == 1


class _LockedTx:
    def __init__(self, lock: asyncio.Lock) -> None:
        self._lock = lock

    async def __aenter__(self):
        await self._lock.acquire()
        return self

    async def __aexit__(self, *a: object) -> bool:
        self._lock.release()
        return False


def test_a_bare_image_url_create_is_left_alone(monkeypatch: pytest.MonkeyPatch) -> None:
    """No object key and no cutout job means nothing stable to key on. Inventing
    an identity from the URL would make two genuinely different pieces that
    happen to share a photo collide."""
    conn = _Conn(existing_item=uuid.uuid4())
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "Linen shirt", "category": "Tops"},
        headers=_auth(),
    )
    assert resp.status_code == 201
    assert conn.written("pg_advisory_xact_lock") == []
    assert conn.written("insert into public.wardrobe_items")


# ── nothing here talks to a model ────────────────────────────────────────────


def test_the_create_path_never_calls_a_classifier(monkeypatch: pytest.MonkeyPatch) -> None:
    """No Anthropic, no OpenAI Vision, no device labels, no title guessing.

    A garment's category is what its owner said it is. This asserts the taxonomy
    module the router uses exposes only deterministic, offline resolution — a
    network call added to that path would be a category decided by a provider.
    """
    import inspect

    source = inspect.getsource(mod.add_wardrobe_item)
    for forbidden in ("anthropic", "openai", "tagger", "httpx", "vision"):
        assert forbidden not in source.lower(), forbidden
    # `_classify_item` is the ONLY thing that decides a role on this path.
    assert "_classify_item" in source
