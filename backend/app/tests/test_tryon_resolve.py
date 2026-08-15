"""Recovering what a selected garment IS (spec Phases 2/5/27).

The resolver is what lets an ALREADY-SHIPPED client keep working without the
provider guessing: a bare image URL still carries its storage object key, and the
media ledger maps that back to the wardrobe item it belongs to. Only a genuinely
unrecognisable URL falls through to the recorded legacy path.
"""

from __future__ import annotations

import asyncio
import uuid

import pytest

from app.core.config import get_settings
from app.services.tryon import taxonomy as tax
from app.services.tryon.resolve import GarmentRef, item_key_for, resolve_garments

ITEM_ID = uuid.uuid4()
PRODUCT_ID = uuid.uuid4()
USER_ID = str(uuid.uuid4())

R2_URL = (
    "https://acc.r2.cloudflarestorage.com/wtm-private/"
    f"{USER_ID}/cutout/abc.png?X-Amz-Expires=3600&X-Amz-Signature=deadbeef"
)


@pytest.fixture(autouse=True)
def _private_bucket(monkeypatch: pytest.MonkeyPatch):
    # Both, because a non-prod environment resolves the STAGING bucket first and
    # the developer's own .env would otherwise decide what this test measures.
    monkeypatch.setenv("R2_PRIVATE_BUCKET", "wtm-private")
    monkeypatch.setenv("R2_PRIVATE_BUCKET_STAGING", "wtm-private")
    monkeypatch.setenv("STORAGE_WRITES", "r2")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


class _Conn:
    """Answers each of the resolver's lookups by SQL fragment."""

    def __init__(
        self,
        *,
        wardrobe: dict | None = None,
        product: dict | None = None,
        ledger: list[dict] | None = None,
        legacy: dict | None = None,
    ) -> None:
        self.wardrobe = wardrobe
        self.product = product
        self.ledger = ledger or []
        self.legacy = legacy

    async def fetch(self, sql: str, *args: object) -> list:
        flat = " ".join(sql.split())
        if "from public.media_assets" in flat:
            return self.ledger
        if "from public.wardrobe_items" in flat:
            if "image_url = any" in flat:
                return [self.legacy] if self.legacy else []
            return [self.wardrobe] if self.wardrobe else []
        if "from public.products" in flat:
            return [self.product] if self.product else []
        return []


def _wardrobe_row(**kw: object) -> dict:
    row = {
        "id": ITEM_ID,
        "title": "Linen shirt",
        "category": "Tops",
        "subcategory": None,
        "canonical_category": None,
        "classification_status": None,
        "cutout_url": None,
        "image_url": None,
    }
    row.update(kw)
    return row


def _product_row(**kw: object) -> dict:
    row = {
        "id": PRODUCT_ID,
        "title": "Wide Leg Trousers",
        "category": "Bottoms",
        "subcategory": None,
        "canonical_category": None,
        "classification_status": None,
        "tryon_image_url": "https://cdn/p.jpg",
        "image_urls": ["https://cdn/p.jpg"],
    }
    row.update(kw)
    return row


def _resolve(conn: _Conn, refs: list[GarmentRef], **kw: object) -> list:
    return asyncio.run(resolve_garments(conn, USER_ID, refs, **kw))


# ── the server reads the row, not the client's claim ─────────────────────────


def test_an_owned_item_resolves_from_its_row() -> None:
    out = _resolve(
        _Conn(wardrobe=_wardrobe_row()),
        [GarmentRef("https://x/a.jpg", wardrobe_item_id=str(ITEM_ID))],
    )
    assert out[0].canonical == tax.TOP
    assert out[0].classification_source == "category"
    assert out[0].allow_auto_fallback is False


def test_a_stored_canonical_category_wins() -> None:
    out = _resolve(
        _Conn(wardrobe=_wardrobe_row(canonical_category=tax.GLASSES, category="Tops")),
        [GarmentRef("https://x/a.jpg", wardrobe_item_id=str(ITEM_ID))],
    )
    assert out[0].canonical == tax.GLASSES


def test_a_needs_review_verdict_is_not_re_derived_from_the_title() -> None:
    """Somebody (or the backfill) already decided this row is unreadable.
    Quietly overturning that from its marketing title is exactly the guess the
    flag exists to prevent."""
    out = _resolve(
        _Conn(
            wardrobe=_wardrobe_row(
                classification_status=tax.STATUS_NEEDS_REVIEW, title="Linen Shirt"
            )
        ),
        [GarmentRef("https://x/a.jpg", wardrobe_item_id=str(ITEM_ID))],
    )
    assert out[0].canonical is None


def test_a_client_category_hint_cannot_override_an_owned_item() -> None:
    """What gets rendered on someone's body is not a client's decision (§11)."""
    out = _resolve(
        _Conn(wardrobe=_wardrobe_row(category="Jeans")),
        [GarmentRef("https://x/a.jpg", wardrobe_item_id=str(ITEM_ID), category_hint="Eyewear")],
    )
    assert out[0].canonical == tax.BOTTOM


def test_a_hint_is_used_only_where_we_hold_no_row() -> None:
    """Sample-rack garments and community images have no row of ours, and the
    hint is the same one that drew the piece into the picker."""
    out = _resolve(
        _Conn(),
        [GarmentRef("https://cdn.samples/x.png", category_hint="Dresses")],
    )
    assert out[0].canonical == tax.ONE_PIECE
    assert out[0].classification_source == "client_hint"


# ── recovering an already-shipped client's bare URL ──────────────────────────


def test_a_signed_r2_url_is_traced_back_to_its_wardrobe_item() -> None:
    """The compatibility path that avoids breaking installed apps."""
    conn = _Conn(
        wardrobe=_wardrobe_row(category="Jeans"),
        ledger=[
            {
                "object_key": f"{USER_ID}/cutout/abc.png",
                "thumbnail_key": None,
                "owner_id": ITEM_ID,
                "role": "cutout",
            }
        ],
    )
    out = _resolve(conn, [GarmentRef(R2_URL, legacy=True)])
    assert out[0].canonical == tax.BOTTOM
    assert out[0].wardrobe_item_id == str(ITEM_ID)
    # A recovered cutout is a flat-lay by construction, which is a fact rather
    # than a guess about the photograph.
    assert out[0].is_cutout is True
    # Recovered means no fallback is needed.
    assert out[0].allow_auto_fallback is False


def test_a_pre_r2_supabase_url_is_traced_back_through_the_row() -> None:
    url = "https://proj.supabase.co/storage/v1/object/public/wardrobe/old.png"
    conn = _Conn(legacy=_wardrobe_row(category="Dresses", image_url=url))
    out = _resolve(conn, [GarmentRef(url, legacy=True)])
    assert out[0].canonical == tax.ONE_PIECE
    assert out[0].wardrobe_item_id == str(ITEM_ID)


def test_a_catalog_image_url_is_traced_back_to_its_product() -> None:
    conn = _Conn(product=_product_row())
    out = _resolve(conn, [GarmentRef("https://cdn/p.jpg", legacy=True)])
    assert out[0].canonical == tax.BOTTOM
    assert out[0].product_id == str(PRODUCT_ID)


def test_an_unrecognisable_legacy_url_keeps_the_escape_hatch() -> None:
    out = _resolve(_Conn(), [GarmentRef("https://elsewhere/x.jpg", legacy=True)])
    assert out[0].canonical is None
    assert out[0].allow_auto_fallback is True


def test_strict_mode_closes_the_escape_hatch_for_everyone() -> None:
    out = _resolve(_Conn(), [GarmentRef("https://elsewhere/x.jpg", legacy=True)], strict=True)
    assert out[0].allow_auto_fallback is False


def test_a_structured_request_never_gets_the_escape_hatch() -> None:
    """A current client CAN say what a piece is, so an unresolved one is a real
    question, not a compatibility problem."""
    out = _resolve(_Conn(), [GarmentRef("https://elsewhere/x.jpg")])
    assert out[0].allow_auto_fallback is False


# ── accounting identity ──────────────────────────────────────────────────────


def test_item_keys_prefer_real_ids() -> None:
    assert item_key_for(wardrobe_item_id="w1", product_id=None, image_url="u") == "w:w1"
    assert item_key_for(wardrobe_item_id=None, product_id="p1", image_url="u") == "p:p1"


def test_an_item_key_survives_re_signing_and_carries_no_signature() -> None:
    """Keys are compared across submit -> plan -> worker -> result, and a URL is
    re-signed on every read."""
    a = item_key_for(wardrobe_item_id=None, product_id=None, image_url=R2_URL)
    b = item_key_for(
        wardrobe_item_id=None,
        product_id=None,
        image_url=R2_URL.replace("deadbeef", "cafebabe"),
    )
    assert a == b
    assert "deadbeef" not in a and "http" not in a
