"""Seed a NON-PRODUCTION Discover catalog (DISCOVER spec §27, §35).

Ops/dev tool only. Deliberately NOT a migration: seed data in a migration ends
up in production the moment someone runs the release process, and fake
merchants in a live catalog are worse than an empty one.

What it creates:
  * 3 merchants — two approved, one disabled.
  * 21 products across dresses / tops / bottoms / outerwear, priced in BDT,
    USD and JPY, with sizes, colours and variants, both Try-On-ready and
    view-only.
  * 8 NEGATIVE records, one per suppression rule, so the RLS policy and the
    API can be proven to hide the same things rather than merely intending to.

Idempotent: every insert is keyed on (merchant, external_id) or a unique slug
and upserts, so running it twice leaves the same rows.

Usage (from backend/):
    python scripts/seed_discover_catalog.py            # uses backend/.env
    python scripts/seed_discover_catalog.py --clear    # remove seeded rows

    # point the seeded merchants at a host that actually resolves, so a human
    # can watch `Shop at Store` open a real page on a device:
    python scripts/seed_discover_catalog.py --destination-host wearthemood.com
"""

from __future__ import annotations

import argparse
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg  # noqa: E402
from dotenv import dotenv_values  # noqa: E402

from app.core.config import pick_migration_dsn  # noqa: E402
from app.services.discover.affiliate import normalize_domain  # noqa: E402

# Every seeded row carries this prefix in its external id / slug, so --clear can
# remove exactly what was seeded and nothing a human added by hand.
SEED_PREFIX = "wtm-seed-"

# Hosts that indicate a PRODUCTION database. Seeding one would put fake
# merchants in a live catalog, so it takes an explicit override.
_PROD_MARKERS = ("ghzabbceoaoertatkjyg", "prod")

NOW = datetime.now(UTC)


def _is_production(dsn: str) -> bool:
    lowered = dsn.lower()
    return any(marker in lowered for marker in _PROD_MARKERS)


MERCHANTS = [
    # (slug, name, approved, shipping_countries, feed_health)
    (f"{SEED_PREFIX}atelier", "Atelier Noir", True, ["BD", "US", "JP"], "ok"),
    (f"{SEED_PREFIX}kanso", "Kanso Tokyo", True, ["JP", "US"], "ok"),
    # NEGATIVE: unapproved. Nothing of its should ever be visible.
    (f"{SEED_PREFIX}ghost", "Ghost Supply", False, ["BD", "US"], "failed"),
]


# The domains a seeded merchant may redirect to. Kept beside the config below
# so the two cannot drift: a template whose host is not covered here produces a
# 502 on every click, which is a confusing way to discover a typo.
SEED_ALLOWED_DOMAINS = ["example.test"]


class InvalidDestinationHost(ValueError):
    """``--destination-host`` was given something that is not a bare hostname."""


def validated_host(value: str) -> str:
    """A bare, allow-listable hostname, or a refusal.

    Deliberately narrow: the override may supply a HOST and nothing else. A
    scheme, a port, a path, userinfo or a wildcard would each widen what the
    allow-list covers, and an allow-list that can be widened from the command
    line is not one (§38). Anything but ``host.example`` is rejected by name
    rather than quietly normalised into something that looked close enough.
    """
    raw = (value or "").strip()
    host = normalize_domain(raw)
    if not host or host != raw.lower() or "." not in host:
        raise InvalidDestinationHost(
            f"not a bare hostname: {value!r} (expected e.g. wearthemood.com)"
        )
    return host


def allowed_domains(destination_host: str | None = None) -> list[str]:
    """The allow-list a seeded merchant gets — the override alone, or the fixture.

    Never both. Keeping the fixture domain alongside a real one would leave a
    permanently allow-listed domain nobody owns.
    """
    return [validated_host(destination_host)] if destination_host else list(SEED_ALLOWED_DOMAINS)


def affiliate_config(slug: str, destination_host: str | None = None) -> tuple[str, str, str]:
    """``(url_template, affiliate_tag, tag_param)`` for a seeded merchant.

    A module-level function rather than an inline f-string so the exact strings
    a dev environment receives can be run through the real destination
    validator in a test, instead of only being discovered to be wrong against a
    live database.

    Default host is a SUBDOMAIN of the allow-listed domain on purpose — that is
    the shape the validator has to accept, and the one a lookalike must not.

    ``destination_host`` swaps in a host that actually resolves, for the one
    thing no fixture can prove: that tapping `Shop at Store` on a device opens a
    real page in the system browser. The ref goes in the QUERY of the root path
    so the destination answers 200 rather than a 404 that reads as a broken
    link, and so a tester can see the ref and the tag in the address bar. It
    changes WHERE a dev click lands — nothing about how it is validated.
    """
    if destination_host:
        host = validated_host(destination_host)
        return (f"https://{host}/?wtm_dev_ref={{ref}}", f"wtm-{slug}", "aff")
    return (f"https://shop.example.test/{slug}/p/{{ref}}", f"wtm-{slug}", "aff")


def _product(
    ext: str,
    merchant: str,
    title: str,
    category: str,
    price_minor: int,
    currency: str,
    *,
    original: int | None = None,
    sizes: list[str] | None = None,
    colors: list[str] | None = None,
    countries: list[str] | None = None,
    try_on: str = "unsupported",
    stock: str = "in_stock",
    rights: str = "licensed",
    images: list[str] | None = None,
    active: bool = True,
    synced_days_ago: int = 0,
    starts_in_days: int | None = None,
    ends_in_days: int | None = None,
) -> dict:
    return {
        "external_id": f"{SEED_PREFIX}{ext}",
        "merchant_slug": merchant,
        "title": title,
        "category": category,
        "price_minor": price_minor,
        "currency": currency,
        "original_price_minor": original,
        "sizes": sizes or ["S", "M", "L"],
        "colors": colors or ["black"],
        "country_availability": countries if countries is not None else ["BD", "US", "JP"],
        "try_on_status": try_on,
        "stock_status": stock,
        "image_rights_status": rights,
        "image_urls": images if images is not None else [f"https://cdn.example.test/{ext}.jpg"],
        "active": active,
        "last_synced_at": NOW - timedelta(days=synced_days_ago),
        "starts_at": None if starts_in_days is None else NOW + timedelta(days=starts_in_days),
        "ends_at": None if ends_in_days is None else NOW + timedelta(days=ends_in_days),
    }


A = f"{SEED_PREFIX}atelier"
K = f"{SEED_PREFIX}kanso"
G = f"{SEED_PREFIX}ghost"

PRODUCTS: list[dict] = [
    # ── dresses ──────────────────────────────────────────────────────────────
    _product(
        "d1",
        A,
        "Black silk slip dress",
        "dresses",
        349900,
        "BDT",
        original=499900,
        try_on="ready",
        colors=["black"],
    ),
    _product(
        "d2", A, "Ivory column dress", "dresses", 289900, "BDT", try_on="ready", colors=["white"]
    ),
    _product(
        "d3",
        K,
        "Wrap midi dress",
        "dresses",
        18900,
        "JPY",
        try_on="pending",
        colors=["navy"],
        countries=["JP", "US"],
    ),
    _product(
        "d4", A, "Emerald evening gown", "dresses", 12900, "USD", original=19900, colors=["green"]
    ),
    _product("d5", K, "Linen sundress", "dresses", 9800, "JPY", colors=["white", "blue"]),
    # ── tops ─────────────────────────────────────────────────────────────────
    _product("t1", A, "Noir silk blouse", "tops", 89900, "BDT", try_on="ready"),
    _product("t2", A, "Cotton poplin shirt", "tops", 4900, "USD", colors=["white"]),
    _product("t3", K, "Ribbed knit top", "tops", 6800, "JPY", colors=["black", "neutral"]),
    _product("t4", A, "Cropped cardigan", "tops", 69900, "BDT", original=89900, colors=["neutral"]),
    _product("t5", K, "Boat-neck tee", "tops", 3200, "JPY", colors=["white"]),
    # ── bottoms ──────────────────────────────────────────────────────────────
    _product(
        "b1",
        A,
        "Wide-leg trousers",
        "bottoms",
        129900,
        "BDT",
        try_on="ready",
        sizes=["XS", "S", "M", "L", "XL"],
    ),
    _product("b2", A, "Straight-leg denim", "bottoms", 7900, "USD", colors=["blue"]),
    _product("b3", K, "Pleated midi skirt", "bottoms", 11900, "JPY", colors=["black"]),
    _product("b4", A, "Tailored shorts", "bottoms", 59900, "BDT", colors=["neutral"]),
    # ── outerwear ────────────────────────────────────────────────────────────
    _product(
        "o1",
        A,
        "Wool trench coat",
        "outerwear",
        499900,
        "BDT",
        original=649900,
        try_on="ready",
        colors=["neutral"],
    ),
    _product("o2", K, "Quilted liner jacket", "outerwear", 24900, "JPY", colors=["green"]),
    _product("o3", A, "Cropped leather jacket", "outerwear", 21900, "USD", colors=["black"]),
    _product(
        "o4", K, "Oversized blazer", "outerwear", 19800, "JPY", colors=["navy"], sizes=["S", "M"]
    ),
    _product("o5", A, "Belted wrap coat", "outerwear", 389900, "BDT", colors=["red"]),
    _product(
        "o6", A, "Padded gilet", "outerwear", 8900, "USD", colors=["black"], stock="low_stock"
    ),
    _product("o7", K, "Shearling coat", "outerwear", 42900, "JPY", colors=["neutral"]),
    # ── NEGATIVE records — one per suppression rule (§19.1, §35) ────────────
    # Inactive.
    _product("neg-inactive", A, "NEG inactive", "tops", 1000, "USD", active=False),
    # Price/stock not confirmed inside the staleness window.
    _product("neg-stale", A, "NEG stale price", "tops", 1000, "USD", synced_days_ago=30),
    # Imagery rights not cleared.
    _product("neg-rights", A, "NEG unlicensed image", "tops", 1000, "USD", rights="unknown"),
    # Out of stock.
    _product("neg-oos", A, "NEG out of stock", "tops", 1000, "USD", stock="out_of_stock"),
    # No image at all.
    _product("neg-noimage", A, "NEG missing image", "tops", 1000, "USD", images=[]),
    # Not available in any country this app serves.
    _product("neg-country", A, "NEG unsupported country", "tops", 1000, "USD", countries=["AQ"]),
    # Belongs to an unapproved merchant.
    _product("neg-merchant", G, "NEG disabled merchant", "tops", 1000, "USD"),
    # Scheduled window that has not opened / has already closed.
    _product(
        "neg-window",
        A,
        "NEG invalid window",
        "tops",
        1000,
        "USD",
        starts_in_days=30,
        ends_in_days=60,
    ),
]

# (product external id, variant suffix, colour, size, stock, available)
VARIANTS = [
    ("d1", "black-s", "black", "S", "in_stock", True),
    ("d1", "black-m", "black", "M", "low_stock", True),
    ("d1", "black-l", "black", "L", "out_of_stock", False),
    ("b1", "neutral-m", "neutral", "M", "in_stock", True),
    ("b1", "neutral-l", "neutral", "L", "in_stock", True),
    ("o1", "camel-m", "neutral", "M", "in_stock", True),
]


def seed(conn: psycopg.Connection, destination_host: str | None = None) -> None:
    domains = allowed_domains(destination_host)
    with conn.cursor() as cur:
        for slug, name, approved, shipping, health in MERCHANTS:
            cur.execute(
                """
                insert into public.merchants
                  (slug, name, approved, supported_countries, shipping_countries,
                   feed_health, allowed_domains, last_synced_at)
                values (%s, %s, %s, %s, %s, %s, %s, now())
                on conflict (slug) do update set
                  name = excluded.name,
                  approved = excluded.approved,
                  supported_countries = excluded.supported_countries,
                  shipping_countries = excluded.shipping_countries,
                  feed_health = excluded.feed_health,
                  allowed_domains = excluded.allowed_domains,
                  updated_at = now()
                """,
                (slug, name, approved, shipping, shipping, health, domains),
            )

            # Phase 4: the redirect configuration, which lives OUTSIDE the
            # read-public merchants table. Without a row here every click 502s
            # by design, so a dev environment cannot exercise the outbound flow
            # at all — and the one case worth being able to test is the one
            # where a merchant is deliberately unconfigured, which the ghost
            # merchant already provides.
            if approved:
                cur.execute(
                    """
                    insert into public.merchant_affiliate_config
                      (merchant_id, url_template, affiliate_tag, tag_param, status)
                    select m.id, %s, %s, %s, 'ok'
                      from public.merchants m where m.slug = %s
                    on conflict (merchant_id) do update set
                      url_template = excluded.url_template,
                      affiliate_tag = excluded.affiliate_tag,
                      tag_param = excluded.tag_param,
                      status = excluded.status,
                      updated_at = now()
                    """,
                    (*affiliate_config(slug, destination_host), slug),
                )

        for p in PRODUCTS:
            cur.execute(
                """
                insert into public.products
                  (merchant_id, external_id, title, category, price_minor,
                   original_price_minor, currency, sizes, colors, image_urls,
                   country_availability, try_on_status, stock_status,
                   image_rights_status, active, last_synced_at, starts_at, ends_at,
                   affiliate_ref)
                select m.id, %(external_id)s, %(title)s, %(category)s, %(price_minor)s,
                       %(original_price_minor)s, %(currency)s, %(sizes)s, %(colors)s,
                       %(image_urls)s, %(country_availability)s, %(try_on_status)s,
                       %(stock_status)s, %(image_rights_status)s, %(active)s,
                       %(last_synced_at)s, %(starts_at)s, %(ends_at)s,
                       %(external_id)s
                  from public.merchants m where m.slug = %(merchant_slug)s
                on conflict (merchant_id, external_id) do update set
                  title = excluded.title,
                  category = excluded.category,
                  price_minor = excluded.price_minor,
                  original_price_minor = excluded.original_price_minor,
                  currency = excluded.currency,
                  sizes = excluded.sizes,
                  colors = excluded.colors,
                  image_urls = excluded.image_urls,
                  country_availability = excluded.country_availability,
                  try_on_status = excluded.try_on_status,
                  stock_status = excluded.stock_status,
                  image_rights_status = excluded.image_rights_status,
                  active = excluded.active,
                  last_synced_at = excluded.last_synced_at,
                  starts_at = excluded.starts_at,
                  ends_at = excluded.ends_at,
                  updated_at = now()
                """,
                p,
            )

        for ext, suffix, color, size, stock, available in VARIANTS:
            cur.execute(
                """
                insert into public.product_variants
                  (product_id, external_variant_id, color, size, stock_status, available)
                select p.id, %s, %s, %s, %s, %s
                  from public.products p
                 where p.external_id = %s
                on conflict (product_id, external_variant_id) do update set
                  color = excluded.color,
                  size = excluded.size,
                  stock_status = excluded.stock_status,
                  available = excluded.available,
                  updated_at = now()
                """,
                (
                    f"{SEED_PREFIX}{suffix}",
                    color,
                    size,
                    stock,
                    available,
                    f"{SEED_PREFIX}{ext}",
                ),
            )
    conn.commit()


def clear(conn: psycopg.Connection) -> None:
    """Remove exactly the seeded rows. Cascades handle products and variants."""
    with conn.cursor() as cur:
        cur.execute("delete from public.merchants where slug like %s", (f"{SEED_PREFIX}%",))
        cur.execute("delete from public.products where external_id like %s", (f"{SEED_PREFIX}%",))
    conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed a non-production Discover catalog.")
    parser.add_argument("--clear", action="store_true", help="remove seeded rows and exit")
    parser.add_argument(
        "--i-know-this-is-production",
        action="store_true",
        help="REQUIRED to run against a database that looks like production",
    )
    parser.add_argument(
        "--destination-host",
        default=None,
        metavar="HOST",
        help=(
            "bare hostname the seeded merchants redirect to, e.g. wearthemood.com. "
            "Default is the non-resolvable example.test fixture."
        ),
    )
    args = parser.parse_args()

    try:
        destination_host = validated_host(args.destination_host) if args.destination_host else None
    except InvalidDestinationHost as exc:
        print(f"REFUSING: {exc}")
        return 2

    env = dotenv_values(Path(__file__).resolve().parent.parent / ".env")
    dsn, _ = pick_migration_dsn(env)
    if not dsn:
        print("No CONNECTION_STRING_DIRECT/CONNECTION_STRING in backend/.env")
        return 1

    # The guard. Fake merchants in a live catalog are a product incident, not a
    # tidy-up job, so this refuses by default and says exactly why.
    if _is_production(dsn) and not args.i_know_this_is_production:
        print(
            "REFUSING: this DSN looks like PRODUCTION.\n"
            "Seed data must never reach a live catalog. If you are certain, re-run\n"
            "with --i-know-this-is-production."
        )
        return 2

    with psycopg.connect(dsn) as conn:
        if args.clear:
            clear(conn)
            print(f"cleared rows matching {SEED_PREFIX}*")
            return 0
        seed(conn, destination_host)
        with conn.cursor() as cur:
            cur.execute(
                "select count(*) from public.products where external_id like %s",
                (f"{SEED_PREFIX}%",),
            )
            total = cur.fetchone()[0]
            cur.execute(
                """
                select count(*) from public.products p
                  join public.merchants m on m.id = p.merchant_id
                 where p.external_id like %s
                   and public.product_is_servable(p) and m.approved
                """,
                (f"{SEED_PREFIX}%",),
            )
            servable = cur.fetchone()[0]
    print(f"seeded {total} products, {servable} servable, {total - servable} suppressed")
    print(f"redirect destination host: {destination_host or 'shop.example.test (fixture)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
