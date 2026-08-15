"""Canonical taxonomy + provider routing (spec Phases 2/3/4/16, matrix §22).

The bar these tests hold: a garment's role is decided by US, deterministically,
and a role we cannot establish is never quietly turned into one we can. Every
case here is a thing that went wrong in production or a thing that must not
start going wrong.
"""

from __future__ import annotations

import pytest

from app.services.tryon import routing
from app.services.tryon import taxonomy as tax

# ── category mapping (spec Phase 22, "Category mapping") ─────────────────────


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        # the closet's own picker values
        ("Tops", tax.TOP),
        ("T-Shirts", tax.TOP),
        ("Shirts", tax.TOP),
        ("Blouses", tax.TOP),
        ("Tunics/Kurtis", tax.TOP),
        ("Bottoms", tax.BOTTOM),
        ("Pants", tax.BOTTOM),
        ("Jeans", tax.BOTTOM),
        ("Skirts", tax.BOTTOM),
        ("Shorts", tax.BOTTOM),
        ("Dresses", tax.ONE_PIECE),
        ("Traditional", tax.ONE_PIECE),
        ("Outerwear", tax.OUTERWEAR),
        ("Winter", tax.OUTERWEAR),
        ("Shoes", tax.SHOES),
        ("Hijab", tax.HIJAB_SCARF),
        ("Scarves", tax.HIJAB_SCARF),
        ("Bags", tax.BAG),
        ("Eyewear", tax.GLASSES),
        ("Jewelry", tax.JEWELRY),
        ("Hats", tax.HAT_HEADWEAR),
        ("Belts", tax.BELT),
        # free text from merchant feeds and user-typed names
        ("shirt", tax.TOP),
        ("hoodie", tax.TOP),
        ("sweater", tax.TOP),
        ("tshirt", tax.TOP),
        ("blouse", tax.TOP),
        ("trousers", tax.BOTTOM),
        ("leggings", tax.BOTTOM),
        ("jumpsuit", tax.ONE_PIECE),
        ("abaya", tax.ONE_PIECE),
        ("sunglasses", tax.GLASSES),
        ("necklace", tax.JEWELRY),
        ("sneakers", tax.SHOES),
        ("backpack", tax.BAG),
        ("baseball cap", tax.HAT_HEADWEAR),
    ],
)
def test_known_values_map_to_their_role(value: str, expected: str) -> None:
    assert tax.classify(category=value).canonical == expected


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        # The ordered phrase table exists for exactly these: a bare noun match
        # would get every one of them wrong.
        ("Women's Linen Dress Shirt", tax.TOP),
        ("Cotton Shirt Dress", tax.ONE_PIECE),
        ("Slim Fit Dress Pants", tax.BOTTOM),
        ("Leather Dress Shoes", tax.SHOES),
        ("Ribbed Tank Top", tax.TOP),
        ("Swim Shorts", tax.BOTTOM),
        ("Wide Leg Trousers", tax.BOTTOM),
        ("Maxi Dress", tax.ONE_PIECE),
        # "top" inside another word must not match.
        ("Padded Laptop Bag", tax.BAG),
    ],
)
def test_ambiguous_titles_resolve_by_specificity(title: str, expected: str) -> None:
    assert tax.classify(title=title).canonical == expected


@pytest.mark.parametrize(
    "value",
    ["Accessories", "Activewear", "Sleepwear", "Party", "Travel", "Workwear", "", None],
)
def test_non_role_values_do_not_guess(value: str | None) -> None:
    """A bucket that says WHEN a piece is worn is not a garment role.

    This is the single most important assertion in the file: the failure mode
    being fixed is a category that resolved to *something* when it should have
    resolved to nothing.
    """
    result = tax.classify(category=value)
    assert result.canonical is None
    assert result.status == tax.STATUS_NEEDS_REVIEW


def test_category_beats_title_and_title_is_the_fallback() -> None:
    # A structured category wins...
    assert tax.classify(category="Jeans", title="Summer Shirt").canonical == tax.BOTTOM
    # ...but a lifestyle bucket falls through to the name rather than giving up,
    # which is what keeps "Activewear / Running Shorts" renderable.
    resolved = tax.classify(category="Activewear", title="Running Shorts")
    assert (resolved.canonical, resolved.source) == (tax.BOTTOM, "title")


def test_stored_canonical_wins_over_everything() -> None:
    resolved = tax.classify(canonical=tax.GLASSES, category="Tops", title="Shirt")
    assert (resolved.canonical, resolved.source) == (tax.GLASSES, "canonical_column")


# ── provider routing (spec Phases 3/4/16) ────────────────────────────────────


@pytest.mark.parametrize(
    ("canonical", "fashn_category"),
    [(tax.TOP, "tops"), (tax.BOTTOM, "bottoms"), (tax.ONE_PIECE, "one-pieces")],
)
def test_apparel_roles_route_to_explicit_categories(canonical: str, fashn_category: str) -> None:
    """Never `auto`. A top is rendered as a top because we said so."""
    route = routing.route_for(canonical)
    assert route is not None
    assert route.model_name == routing.APPAREL_MODEL
    assert route.category == fashn_category
    assert route.prompt is None


@pytest.mark.parametrize(
    "canonical",
    [
        tax.GLASSES,
        tax.HIJAB_SCARF,
        tax.HAT_HEADWEAR,
        tax.SHOES,
        tax.BAG,
        tax.JEWELRY,
        tax.OUTERWEAR,
    ],
)
def test_accessories_route_to_the_accessory_model_with_preservation(canonical: str) -> None:
    """Accessories must NOT reach the apparel model.

    tryon-v1.6 only knows tops/bottoms/one-pieces, so a pair of glasses sent
    there is classified as one of those and repaints a body region — which is
    how a four-piece look came back as one shirt.
    """
    route = routing.route_for(canonical)
    assert route is not None
    assert route.model_name == routing.ACCESSORY_MODEL
    assert route.category is None  # tryon-max rejects `category` outright
    assert route.prompt  # the only provider-supported preservation mechanism
    assert "do not replace" in route.prompt.lower()
    assert "pose" in route.prompt.lower()


def test_look_reference_replaces_clothing_instead_of_preserving_it() -> None:
    """The one role whose whole job is to change the outfit.

    Giving it the shared "keep every garment they are already wearing" tail
    would instruct the model to do the opposite of the request.
    """
    route = routing.route_for(tax.LOOK_REFERENCE)
    assert route is not None and route.prompt
    assert "complete outfit" in route.prompt.lower()
    assert "do not replace" not in route.prompt.lower()
    assert "pose" in route.prompt.lower()  # the person is still preserved


@pytest.mark.parametrize("canonical", [tax.BELT, tax.OTHER, None, "nonsense"])
def test_unsupported_roles_have_no_route(canonical: str | None) -> None:
    """Honest unsupported beats pretend-supported (spec Phase 16)."""
    assert routing.route_for(canonical) is None


def test_photo_type_is_only_claimed_when_it_is_known() -> None:
    # A wardrobe cutout IS a flat-lay by construction; anything else is a guess.
    assert routing.garment_photo_type(is_cutout=True) == routing.PHOTO_TYPE_FLAT_LAY
    assert routing.garment_photo_type(is_cutout=False) == routing.PHOTO_TYPE_AUTO


def test_every_supported_role_is_routable() -> None:
    """Guards the seam between the two tables: a role marked SUPPORTED with no
    route would be silently unrenderable, which is the failure this file exists
    to make impossible."""
    for canonical in tax.TRYON_CAPABLE_CATEGORIES:
        assert routing.route_for(canonical) is not None, canonical


def test_accessories_are_ordered_after_apparel() -> None:
    """Order is a correctness property, not a preference: an apparel pass
    repaints a whole body region and would erase an accessory applied first."""
    apparel = max(tax.render_order(c) for c in (tax.ONE_PIECE, tax.BOTTOM, tax.TOP, tax.OUTERWEAR))
    accessories = min(
        tax.render_order(c)
        for c in (tax.SHOES, tax.BAG, tax.HIJAB_SCARF, tax.HAT_HEADWEAR, tax.GLASSES)
    )
    assert apparel < accessories


def test_sql_mirror_of_capable_categories_matches_python() -> None:
    """0070's `tryon_capable_category()` hard-codes this list. If the two drift,
    a product becomes ineligible in SQL while the planner still routes it."""
    from pathlib import Path

    sql = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "0070_tryon_category_gate.sql"
    ).read_text(encoding="utf-8")
    listed = {c for c in tax.CANONICAL_CATEGORIES if f"'{c}'" in sql}
    # look_reference is deliberately absent from the SQL gate: it is not a
    # catalogue product category, only a community-handoff role.
    assert listed == set(tax.TRYON_CAPABLE_CATEGORIES) - {tax.LOOK_REFERENCE}
