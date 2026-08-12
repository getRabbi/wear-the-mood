"""DELETE /v1/tryon/results/{id} — removing one generation for good.

Completed try-ons have always been persisted (`tryon_results`) and there was no
way to remove one: the app could list history and nothing else. This is that
endpoint, and these are the three things it must never get wrong.

  * **Ownership is in the DELETE.** The user id comes from the verified JWT and
    is part of the statement, so somebody else's result is a 404 rather than an
    authorization decision made after the row has already been read.
  * **Only the RESULT is erased.** A try-on has three images and two of them
    belong to other rows — the user's body photo (`tryon_photos`, reused by
    every future render) and the garment (a wardrobe cutout or a catalog photo).
    Erasing either would take a source image away from renders that had nothing
    to do with this one.
  * **Media failure never resurrects the row.** Object storage is best-effort;
    an orphaned object is sweepable, a result the user was told was deleted
    coming back is not.
"""

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.errors import ApiError
from app.main import app
from app.models.common import ErrorCode
from app.tests.test_giveaway_chat import _Conn, _Pool

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_ID = "11111111-1111-4111-8111-111111111111"

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
            "sub": USER_ID,
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


def _install(monkeypatch: pytest.MonkeyPatch, conn: _Conn, media: list | None = None):
    """Point the router at a fake pool, and record what media erasure was asked for."""
    import app.routers.v1.tryon as tryon_mod

    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))

    async def _record(_conn, owner_kind, owner_id, refs):
        if media is not None:
            media.append((owner_kind, owner_id, refs))
        return len(refs)

    monkeypatch.setattr(tryon_mod, "delete_content_media", _record)
    return tryon_mod


def test_delete_requires_a_token() -> None:
    resp = client.delete(f"/v1/tryon/results/{uuid.uuid4()}")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_a_malformed_id_is_a_404_not_a_500() -> None:
    resp = client.delete("/v1/tryon/results/not-a-uuid", headers=_auth())
    assert resp.status_code == 422


def test_deleting_a_result_removes_the_row_and_its_image(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    result_id = str(uuid.uuid4())
    conn = _Conn(
        [
            (
                "fetchrow",
                "delete from public.tryon_results",
                {"id": result_id, "result_image_url": "u1/r1.jpg"},
            )
        ]
    )
    media: list = []
    _install(monkeypatch, conn, media)

    resp = client.delete(f"/v1/tryon/results/{result_id}", headers=_auth())
    assert resp.status_code == 204
    assert resp.content == b""

    # The row went, scoped to the caller.
    method, sql, args = conn.calls[0]
    assert method == "fetchrow"
    assert "delete from public.tryon_results" in sql
    assert "where id = $1::uuid and user_id = $2::uuid" in sql
    assert args == (result_id, USER_ID)

    # And exactly one image: this result's own render.
    assert media == [("tryon_result", result_id, [("result", "u1/r1.jpg")])]


def test_it_never_touches_the_body_photo_or_the_garment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The one that would be a data-loss bug rather than a cosmetic one.

    Both source images are shared: the body photo is reused by every future
    render and the garment belongs to a wardrobe item or a catalog product.
    """
    result_id = str(uuid.uuid4())
    conn = _Conn(
        [
            (
                "fetchrow",
                "delete from public.tryon_results",
                {"id": result_id, "result_image_url": "u1/r1.jpg"},
            )
        ]
    )
    media: list = []
    _install(monkeypatch, conn, media)

    client.delete(f"/v1/tryon/results/{result_id}", headers=_auth())

    (_, _, refs) = media[0]
    assert [role for role, _ in refs] == ["result"]
    # Nothing in the statement reaches for the job's own images either.
    all_sql = " ".join(sql for _, sql, _ in conn.calls)
    for column in ("person_image_url", "garment_image_url", "tryon_photos"):
        assert column not in all_sql
    assert "delete from public.tryon_jobs" not in all_sql


def test_somebody_elses_result_is_a_404(monkeypatch: pytest.MonkeyPatch) -> None:
    # The scoped DELETE simply matches nothing, so there is no row to leak and
    # no separate ownership check that could be forgotten.
    conn = _Conn([("fetchrow", "delete from public.tryon_results", None)])
    media: list = []
    _install(monkeypatch, conn, media)

    resp = client.delete(f"/v1/tryon/results/{uuid.uuid4()}", headers=_auth())
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"
    assert media == [], "nothing may be erased for a row that was not ours"


def test_a_media_failure_does_not_resurrect_the_row(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`delete_content_media` is best-effort by construction and never raises.

    An orphaned object can be swept later; a result the user has been told is
    gone coming back cannot be undone.
    """
    import app.routers.v1.tryon as tryon_mod

    result_id = str(uuid.uuid4())
    conn = _Conn(
        [
            (
                "fetchrow",
                "delete from public.tryon_results",
                {"id": result_id, "result_image_url": None},
            )
        ]
    )
    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))

    calls: list = []

    async def _swallow(_conn, owner_kind, owner_id, refs):
        # Mirrors the real helper: it logs and returns rather than raising.
        calls.append(owner_id)
        return 0

    monkeypatch.setattr(tryon_mod, "delete_content_media", _swallow)

    resp = client.delete(f"/v1/tryon/results/{result_id}", headers=_auth())
    assert resp.status_code == 204
    assert calls == [result_id]


# ── the shopping origin is re-checked server-side ───────────────────────────


def test_a_try_on_naming_an_unready_product_is_refused(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Rollback has to be real.

    A card cached on a device before its merchant was de-licensed still carries
    a TRY ON pill. Without this check the request would go through, the image
    would reach the provider, and the only casualty would be the back-link —
    which is precisely backwards.
    """
    import app.routers.v1.tryon as tryon_mod
    from app.models.tryon import TryOnRequest

    product_id = uuid.uuid4()
    conn = _Conn(
        [
            (
                "fetchrow",
                "from public.products p",
                {"id": product_id, "merchant_id": uuid.uuid4(), "tryon_ready": False},
            )
        ]
    )
    body = TryOnRequest(
        person_image_url="https://cdn.test/me.jpg",
        garment_image_url="https://cdn.test/dress.jpg",
        source_product_id=product_id,
    )

    with pytest.raises(ApiError) as caught:
        asyncio.run(tryon_mod._resolve_shopping_source(conn, body))
    assert caught.value.code == ErrorCode.VALIDATION_ERROR

    # And the gate it consulted is the canonical one, not a re-derivation.
    assert "public.product_tryon_ready(p)" in conn.calls[0][1]


def test_a_try_on_naming_a_ready_product_is_allowed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.models.tryon import TryOnRequest

    product_id, merchant_id = uuid.uuid4(), uuid.uuid4()
    conn = _Conn(
        [
            (
                "fetchrow",
                "from public.products p",
                {"id": product_id, "merchant_id": merchant_id, "tryon_ready": True},
            )
        ]
    )
    resolved = asyncio.run(
        tryon_mod._resolve_shopping_source(
            conn,
            TryOnRequest(
                person_image_url="https://cdn.test/me.jpg",
                garment_image_url="https://cdn.test/dress.jpg",
                source_product_id=product_id,
            ),
        )
    )
    assert resolved == (str(product_id), str(merchant_id), "affiliate_product")


def test_a_withdrawn_product_still_only_costs_the_back_link() -> None:
    """Unchanged behaviour, and deliberately different from the rights case: a
    product that no longer exists is a broken link, not an image we must not
    send. Losing the render over it would be the worse trade."""
    import app.routers.v1.tryon as tryon_mod
    from app.models.tryon import TryOnRequest

    conn = _Conn([("fetchrow", "from public.products p", None)])
    assert (
        asyncio.run(
            tryon_mod._resolve_shopping_source(
                conn,
                TryOnRequest(
                    person_image_url="https://cdn.test/me.jpg",
                    garment_image_url="https://cdn.test/dress.jpg",
                    source_product_id=uuid.uuid4(),
                ),
            )
        )
        is None
    )


def test_a_closet_render_asks_the_catalog_nothing() -> None:
    import app.routers.v1.tryon as tryon_mod
    from app.models.tryon import TryOnRequest

    conn = _Conn([])
    assert (
        asyncio.run(
            tryon_mod._resolve_shopping_source(
                conn,
                TryOnRequest(
                    person_image_url="https://cdn.test/me.jpg",
                    garment_image_url="https://cdn.test/dress.jpg",
                ),
            )
        )
        is None
    )
    assert conn.calls == []

