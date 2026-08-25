"""The PUBLIC read surface for iOS Guest Mode (App Review 5.1.1(v)).

Two things are proved, and the second matters more than the first:

1. The public routes exist and do not demand a bearer token.
2. **Nothing else changed.** Every protected route still answers 401 without
   one, and no route outside `/v1/public/*` became reachable. The rejection this
   work answers was "you cannot see anything without an account"; the wrong fix
   would be "now you can see everything without one".
"""

from __future__ import annotations

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

client = TestClient(app)

# Routes that must never require authentication.
PUBLIC_PATHS = {
    "/v1/public/flags",
    "/v1/public/discover/products",
    "/v1/public/discover/facets",
    "/v1/public/discover/products/{product_id}",
    "/v1/public/discover/products/{product_id}/similar",
    "/v1/public/discover/products/{product_id}/click",
    "/v1/public/news",
    "/v1/public/news/{news_id}",
    "/v1/public/giveaways",
    "/v1/public/giveaways/{giveaway_id}",
}


def _routes() -> list[APIRoute]:
    return [r for r in app.routes if isinstance(r, APIRoute)]


def _requires_auth(route: APIRoute) -> bool:
    """Whether `get_current_user` appears anywhere in the route dependency tree.

    Walked recursively rather than checked one level deep: a dependency that
    itself depends on auth still makes the route protected, and a one-level
    check would report it as open.
    """

    def walk(dependant: object) -> bool:
        call = getattr(dependant, "call", None)
        if getattr(call, "__name__", "") == "get_current_user":
            return True
        return any(walk(sub) for sub in getattr(dependant, "dependencies", []))

    return walk(route.dependant)


def test_every_public_route_is_registered() -> None:
    registered = {r.path for r in _routes()}
    missing = PUBLIC_PATHS - registered
    assert not missing, f"public routes missing from the app: {sorted(missing)}"


# Routes under /v1 that were ALREADY unauthenticated before Guest Mode, each
# for a reason that is not "anyone may read this":
#
#   /v1/health            — liveness. Returns no data.
#   /v1/billing/webhook   — called by RevenueCat, not by a person. Authenticated
#                           by signature verification inside the handler; a
#                           bearer token would be meaningless here.
#   /v1/referrals/click   — the public referral landing, rate-limited per IP and
#                           trading only in opaque single-use tokens (§24).
#
# Pinned so the test below can say "these and ONLY these", which is the useful
# assertion — a loosened filter would let the next accidental opening through.
PRE_EXISTING_UNAUTHENTICATED = {
    "/v1/health",
    "/v1/billing/webhook",
    "/v1/referrals/click",
}


def test_no_route_outside_the_public_prefix_became_public() -> None:
    """The blast radius of this change is exactly `/v1/public/*`.

    Any OTHER route that stopped requiring `get_current_user` would be a
    protected endpoint quietly opened, which is the failure mode worth a test of
    its own.
    """
    leaked = [
        r.path
        for r in _routes()
        if r.path.startswith("/v1/")
        and not r.path.startswith("/v1/public/")
        and r.path not in PRE_EXISTING_UNAUTHENTICATED
        and not _requires_auth(r)
    ]
    assert not leaked, f"these /v1 routes no longer require auth: {sorted(leaked)}"


def test_the_pinned_unauthenticated_routes_still_exist() -> None:
    """Keeps the allowlist above honest.

    A pinned path that no longer exists is a stale exemption, and a stale
    exemption is a hole waiting for a future route to be named the same thing.
    """
    registered = {r.path for r in _routes()}
    assert PRE_EXISTING_UNAUTHENTICATED <= registered


def test_public_routes_do_not_require_auth() -> None:
    for route in _routes():
        if route.path in PUBLIC_PATHS:
            assert not _requires_auth(route), f"{route.path} must stay public"


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/v1/flags"),
        ("GET", "/v1/discover/products"),
        ("GET", "/v1/discover/saved"),
        ("GET", "/v1/news"),
        ("GET", "/v1/giveaways"),
        ("GET", "/v1/giveaways/mine"),
        ("GET", "/v1/credits"),
        ("GET", "/v1/me"),
        ("POST", "/v1/tryon"),
        ("POST", "/v1/wardrobe"),
        ("POST", "/v1/media/upload-url"),
        ("PUT", "/v1/discover/saved/11111111-2222-3333-4444-555555555555"),
        ("POST", "/v1/social/posts"),
    ],
)
def test_the_private_mirror_still_demands_a_token(method: str, path: str) -> None:
    """The originals are untouched.

    Auth runs before any DB access and before body validation, so these hold
    without a live database and without well-formed payloads.
    """
    resp = client.request(method, path)
    assert resp.status_code == 401, f"{method} {path} answered {resp.status_code}"
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_a_public_route_reaches_the_handler_without_a_token() -> None:
    """No 401 — it gets far enough to need a database.

    With no CONNECTION_STRING the handler fails inside `get_pool()`, which is
    itself the proof that authentication did not stop it first. Server
    exceptions are surfaced as a 500 rather than re-raised so the assertion is
    about the STATUS, which is the thing under test.
    """
    with TestClient(app, raise_server_exceptions=False) as raw:
        resp = raw.get("/v1/public/flags")
    assert resp.status_code != 401
    assert resp.status_code != 403


def test_public_giveaway_response_redacts_the_owner() -> None:
    """The public view is NARROWER than the signed-in one.

    The authenticated route returns `owner_id` and `owner_name`; a display name
    attached to a coarse area, readable by anyone with the URL and no account,
    is a different exposure entirely. Asserted against the builder directly so
    it holds without a database.
    """
    from datetime import UTC, datetime

    from app.routers.v1.public import _public_giveaway

    row = {
        "id": "11111111-2222-3333-4444-555555555555",
        "title": "Linen shirt",
        "description": "Barely worn",
        "size": "M",
        "category": "tops",
        "condition": "good",
        "area_label": "Dhanmondi",
        "status": "available",
        "claim_count": 3,
        "created_at": datetime.now(UTC),
    }
    out = _public_giveaway(row, ["https://cdn.test/a.jpg"], ["https://cdn.test/t.jpg"])

    assert out.owner_id == ""
    assert out.owner_name is None
    # Nothing about a caller, because there is no caller.
    assert out.is_mine is False
    assert out.my_claim_status is None
    assert out.my_claim_id is None
    assert out.chat_id is None
    assert out.chat_status is None
    # The listing itself still shows.
    assert out.title == "Linen shirt"
    assert out.images == ["https://cdn.test/a.jpg"]


def test_public_sql_is_valid_live() -> None:
    """Prepares each public statement against the real schema.

    Skipped without a database. It catches the failure mode a shape test cannot:
    a column that does not exist, which would 500 the guest experience on the
    reviewer's first tap.
    """
    settings = get_settings()
    if not settings.connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    import asyncio

    import asyncpg

    from app.routers.v1.public import _PUBLIC_GIVEAWAY_SELECT

    async def run() -> None:
        conn = await asyncpg.connect(
            dsn=settings.connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            await conn.prepare("select key, enabled from public.feature_flags")
            await conn.prepare(
                _PUBLIC_GIVEAWAY_SELECT
                + " where g.id = $1::uuid and g.deleted_at is null"
                + " and g.hidden_at is null"
            )
        finally:
            await conn.close()

    asyncio.run(run())


# ── security invariants, asserted against the source itself ──────────────────
#
# The route tests above prove what the public surface DOES. These prove what it
# CANNOT do — which is the more useful guarantee, because it keeps holding when
# somebody adds a route to this file next year without reading it first.


def _public_source() -> str:
    import inspect

    from app.routers.v1 import public as public_mod

    return inspect.getsource(public_mod)


# Tables that describe a PERSON. None of them may be named anywhere in the
# public router: not in a join, not in a subquery, not in an exists().
PRIVATE_TABLES = [
    "saved_products",
    "shopping_preferences",
    "product_interactions",
    "wardrobe_items",
    "affiliate_clicks",
    "credits",
    "credit_ledger",
    "profiles",
    "consents",
    "tryon_jobs",
    "tryon_results",
    "notifications",
    "push_tokens",
    "posts",
    "comments",
    "likes",
    "follows",
    "blocks",
    "giveaway_pickup_chats",
    "giveaway_chat_messages",
    "idempotency_keys",
    "ai_usage_log",
    "taste_signals",
    "style_memory",
]


@pytest.mark.parametrize("table", PRIVATE_TABLES)
def test_the_public_router_never_names_a_private_table(table: str) -> None:
    source = _public_source()
    assert f"public.{table}" not in source, (
        f"the public router must never read public.{table} — it describes a person"
    )


def test_the_public_router_writes_nothing() -> None:
    """Read-only, structurally.

    Every route in this file is a SELECT. The one POST resolves a merchant
    destination and records nothing, which is exactly why no write verb may
    appear anywhere in the module.
    """
    source = _public_source().lower()
    for verb in ("insert into", "update public.", "delete from", "conn.execute("):
        assert verb not in source, f"the public router must not contain `{verb}`"


def test_the_public_router_starts_no_transaction() -> None:
    """A transaction in a read-only module is a write waiting to happen."""
    assert "conn.transaction(" not in _public_source()


def test_the_public_giveaway_query_selects_no_owner_column() -> None:
    """Redaction at the SOURCE, not just in the builder.

    `_public_giveaway` sets owner_id/owner_name to empty values, but the
    stronger guarantee is that the query never fetches them — so there is
    nothing to leak even if the builder were changed carelessly.
    """
    from app.routers.v1.public import _PUBLIC_GIVEAWAY_SELECT

    sql = " ".join(_PUBLIC_GIVEAWAY_SELECT.split()).lower()
    assert "owner_id" not in sql
    assert "display_name" not in sql
    assert "join public.profiles" not in sql


def test_every_public_route_is_a_get_except_the_click() -> None:
    """The one POST is the affiliate destination, and nothing else."""
    posts = {
        r.path
        for r in _routes()
        if r.path.startswith("/v1/public/") and "POST" in (r.methods or set())
    }
    assert posts == {"/v1/public/discover/products/{product_id}/click"}

    # And no public route accepts a mutating verb at all.
    for route in _routes():
        if not route.path.startswith("/v1/public/"):
            continue
        assert not ({"PUT", "PATCH", "DELETE"} & (route.methods or set())), (
            f"{route.path} exposes a mutating verb"
        )


def test_no_public_response_model_carries_an_identity_field() -> None:
    """Schema-level: the shapes a guest can receive have no PII field at all.

    Walks the actual OpenAPI schema for every public route, following `$ref`s,
    and fails on any property whose NAME is one we would never want an
    anonymous caller to receive.
    """
    spec = app.openapi()
    schemas = spec.get("components", {}).get("schemas", {})

    forbidden = {
        "email",
        "user_id",
        "owner_email",
        "phone",
        "access_token",
        "refresh_token",
        "password",
        "affiliate_ref",
        "affiliate_tag",
        "credits",
        "credit_balance",
        "body_photo_url",
        "person_image_url",
    }

    seen: set[str] = set()

    def walk(node: object) -> None:
        if isinstance(node, dict):
            ref = node.get("$ref")
            if isinstance(ref, str) and ref.startswith("#/components/schemas/"):
                name = ref.rsplit("/", 1)[-1]
                if name not in seen:
                    seen.add(name)
                    walk(schemas.get(name, {}))
                return
            for key, value in node.items():
                if key == "properties" and isinstance(value, dict):
                    leaked = forbidden & set(value)
                    assert not leaked, f"a public response exposes {sorted(leaked)}"
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    for path, item in spec.get("paths", {}).items():
        if path.startswith("/v1/public/"):
            walk(item)

    # The walk must actually have visited something, or this passes vacuously.
    assert seen, "no public response schemas were inspected"
