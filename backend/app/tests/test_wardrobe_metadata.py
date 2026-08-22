"""Mandatory name + category, and the legacy backfill (spec Phases 1/5/26).

Where the whole fix starts. A closet item with neither a name nor a category
cannot be rendered by anything, because nothing downstream can say what it is —
so the API refuses to create one, an edit has to complete an old one, and the
backfill classifies what it can and honestly flags what it cannot.
"""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

import app.routers.v1.wardrobe as mod
from app.core.config import get_settings
from app.main import app
from app.services.tryon import backfill
from app.services.tryon import taxonomy as tax

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
client = TestClient(app)


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


class _Conn:
    """Fake connection: records writes, answers the handful of reads used here."""

    def __init__(self, existing: dict | None = None) -> None:
        self.calls: list[tuple[str, tuple]] = []
        self.existing = existing
        self.row = {
            "id": uuid.uuid4(),
            "title": "x",
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

    async def fetchrow(self, sql: str, *args: object):
        self.calls.append((" ".join(sql.split()), args))
        if "select title, category, subcategory" in " ".join(sql.split()):
            return self.existing
        return self.row

    async def fetchval(self, sql: str, *args: object):
        self.calls.append((" ".join(sql.split()), args))
        return None

    async def fetch(self, sql: str, *args: object):
        return []

    async def execute(self, sql: str, *args: object):
        self.calls.append((" ".join(sql.split()), args))
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
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    async def _flag(*a: object, default: bool = False, **kw: object) -> bool:
        # Answer each flag's OWN default rather than True for everything.
        # Blanket-True quietly enabled `wardrobe_require_known_category`, which
        # ships OFF, and made these tests assert a contract production does not
        # run yet. `test_unknown_category_*` below turns it on explicitly.
        return default

    async def _noop(*a: object, **kw: object) -> None:
        return None

    async def _enqueue(*a: object, **kw: object) -> bool:
        return False

    monkeypatch.setattr(mod, "flag_enabled", _flag)
    monkeypatch.setattr(mod, "insert_asset", _noop)
    monkeypatch.setattr(mod, "enqueue_signal", _enqueue)


# ── create (spec Phase 22, "Data validation") ────────────────────────────────


@pytest.mark.parametrize(
    "payload",
    [
        {"image_url": "https://x/a.jpg"},  # neither
        {"image_url": "https://x/a.jpg", "category": "Tops"},  # no name
        {"image_url": "https://x/a.jpg", "title": "Linen shirt"},  # no category
        {"image_url": "https://x/a.jpg", "title": "  ", "category": " "},  # blank
    ],
)
def test_create_without_name_and_category_is_rejected(
    monkeypatch: pytest.MonkeyPatch, payload: dict
) -> None:
    conn = _Conn()
    _wire(monkeypatch, conn)
    resp = client.post("/v1/wardrobe", json=payload, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
    assert conn.written("insert into public.wardrobe_items") == []


def test_create_with_both_is_accepted_and_stores_the_canonical_role(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn()
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "Linen shirt", "category": "Tops"},
        headers=_auth(),
    )
    assert resp.status_code == 201
    insert = conn.written("insert into public.wardrobe_items")[0]
    assert insert[1][-2:] == (tax.TOP, tax.STATUS_VALID)


def test_a_category_we_cannot_read_is_stored_as_needs_review_not_guessed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The user gave us a real category; we simply cannot turn "Party" into a
    body region. The item saves and is fully usable — it is only try-on that
    declines to invent a role (§29)."""
    conn = _Conn()
    _wire(monkeypatch, conn)
    resp = client.post(
        "/v1/wardrobe",
        json={"image_url": "https://x/a.jpg", "title": "That one thing", "category": "Party"},
        headers=_auth(),
    )
    assert resp.status_code == 201
    insert = conn.written("insert into public.wardrobe_items")[0]
    assert insert[1][-2:] == (None, tax.STATUS_NEEDS_REVIEW)


def test_the_gate_is_killable_without_a_deploy(monkeypatch: pytest.MonkeyPatch) -> None:
    """`wardrobe_require_metadata` is an incident switch, not a feature toggle:
    an app build older than this change surfaces the 422 in its own failure
    sheet, and if that hurts in the wild it can be turned off instantly."""
    conn = _Conn()
    _wire(monkeypatch, conn)

    async def _off(*a: object, **kw: object) -> bool:
        return False

    monkeypatch.setattr(mod, "flag_enabled", _off)
    resp = client.post("/v1/wardrobe", json={"image_url": "https://x/a.jpg"}, headers=_auth())
    assert resp.status_code == 201


# ── edit completes an old piece (spec Phase 26) ──────────────────────────────


def test_editing_a_legacy_piece_requires_the_missing_fields(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _Conn(existing={"title": None, "category": None, "subcategory": None})
    _wire(monkeypatch, conn)
    resp = client.patch(f"/v1/wardrobe/{uuid.uuid4()}", json={"color": "Blue"}, headers=_auth())
    assert resp.status_code == 422
    assert conn.written("update public.wardrobe_items") == []


def test_supplying_the_missing_category_reclassifies_the_row(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The one action a user would naturally take is the one that makes the piece
    renderable again."""
    conn = _Conn(existing={"title": "Old jeans", "category": None, "subcategory": None})
    _wire(monkeypatch, conn)
    resp = client.patch(f"/v1/wardrobe/{uuid.uuid4()}", json={"category": "Jeans"}, headers=_auth())
    assert resp.status_code == 200
    update = conn.written("update public.wardrobe_items")[0]
    assert "canonical_category" in update[0]
    assert tax.BOTTOM in update[1]
    assert tax.STATUS_VALID in update[1]


def test_an_edit_cannot_blank_out_a_name(monkeypatch: pytest.MonkeyPatch) -> None:
    conn = _Conn(existing={"title": "Linen shirt", "category": "Tops", "subcategory": None})
    _wire(monkeypatch, conn)
    resp = client.patch(f"/v1/wardrobe/{uuid.uuid4()}", json={"title": "   "}, headers=_auth())
    assert resp.status_code == 422


# ── backfill (spec Phase 5) ──────────────────────────────────────────────────


class _BackfillConn:
    """Serves a fixed set of unclassified rows; records the updates."""

    def __init__(self, rows: list[dict]) -> None:
        self.rows = rows
        self.updates: list[tuple[str, tuple]] = []

    def transaction(self):
        return _Tx()

    async def fetchval(self, sql: str, *args: object) -> int:
        return len(self.rows) if "count(*) from" in sql else 0

    async def fetch(self, sql: str, *args: object) -> list:
        # Mirrors the real `limit $1 offset $2`: `report` pages with a growing
        # offset and writes nothing, while `apply` always reads at offset 0
        # because each batch it writes stops matching the WHERE clause.
        limit = int(args[0]) if args else len(self.rows)
        offset = int(args[1]) if len(args) > 1 else 0
        pending = [r for r in self.rows if r.get("canonical_category") is None]
        return pending[offset : offset + limit]

    async def execute(self, sql: str, *args: object) -> str:
        self.updates.append((" ".join(sql.split()), args))
        touched = set(args[-1])
        for row in self.rows:
            if str(row["id"]) in touched:
                # Mark it done so the next fetch returns the remaining rows.
                row["canonical_category"] = args[0] if "canonical_category = $1" in sql else ""
        return "UPDATE 1"


def _row(title: str | None, category: str | None) -> dict:
    return {
        "id": uuid.uuid4(),
        "title": title,
        "category": category,
        "subcategory": None,
        "canonical_category": None,
        "classification_status": None,
    }


def test_the_dry_run_separates_backfillable_from_unreadable_from_empty() -> None:
    rows = [
        _row("Women's Linen Shirt", None),  # readable from the name
        _row(None, "Jeans"),  # readable from the category
        _row("That thing", "Party"),  # has metadata we cannot read
        _row(None, None),  # nothing at all to work from
    ]
    report = asyncio.run(backfill.report(_BackfillConn(rows), "wardrobe_items"))
    assert report.backfillable == 2
    assert report.needs_review == 1
    assert report.unresolvable == 1
    assert report.by_category == {tax.TOP: 1, tax.BOTTOM: 1}
    assert "wardrobe_items" in report.render()


def test_the_dry_run_writes_nothing() -> None:
    conn = _BackfillConn([_row("Maxi Dress", None)])
    asyncio.run(backfill.report(conn, "products"))
    assert conn.updates == []


def test_apply_classifies_what_it_can_and_flags_the_rest() -> None:
    rows = [_row("Wide Leg Trousers", None), _row(None, None)]
    conn = _BackfillConn(rows)
    counts = asyncio.run(backfill.apply(conn, "wardrobe_items"))
    assert counts == {"classified": 1, "needs_review": 1}
    sets = [u[0] for u in conn.updates]
    assert any("canonical_category = $1" in s for s in sets)
    assert any("classification_status = 'needs_review'" in s for s in sets)
    # It never invents a role for the empty row.
    assert not any("canonical_category = 'top'" in s for s in sets)


def test_apply_rejects_an_unknown_table() -> None:
    """The table name is interpolated into SQL, so the allow-list is load-bearing."""
    with pytest.raises(ValueError):
        asyncio.run(backfill.apply(_BackfillConn([]), "users; drop table products"))
