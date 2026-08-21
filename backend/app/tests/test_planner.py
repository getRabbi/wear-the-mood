"""Mood Planner v2 direction building (spec §14).

The load-bearing property: a mood plan is FREE. Nothing in this module may reach
a provider, reserve a credit or touch the credit ledger — the whole point is a
daily reason to open WTM that costs nothing to serve.
"""

from __future__ import annotations

from app.services.planner import MOODS, build_direction


class _Row(dict):
    """A stand-in for an asyncpg.Record — dict access plus `.keys()`."""


def _item(**over) -> _Row:
    base = {
        "id": "item-1",
        "title": "Shirt",
        "category": "Tops",
        "subcategory": "shirt",
        "color": "black",
        "canonical_category": "top",
    }
    base.update(over)
    return _Row(base)


def test_every_mood_produces_a_direction() -> None:
    for mood in MOODS:
        direction = build_direction(mood=mood, occasion=None, wardrobe=[])
        assert direction.headline
        assert direction.lines


def test_an_empty_closet_says_so_rather_than_inventing_pieces() -> None:
    direction = build_direction(mood="calm", occasion=None, wardrobe=[])
    assert direction.generic is True
    assert direction.item_ids == []
    assert any("closet is still light" in line for line in direction.lines)


def test_a_real_closet_names_real_pieces() -> None:
    wardrobe = [
        _item(id="top-1", canonical_category="top", color="cream"),
        _item(id="bottom-1", canonical_category="bottom", color="beige", subcategory="trousers"),
        _item(id="shoe-1", canonical_category="shoes", color="white", subcategory="sneakers"),
    ]
    direction = build_direction(mood="calm", occasion=None, wardrobe=wardrobe)
    assert direction.generic is False
    assert set(direction.item_ids) == {"top-1", "bottom-1", "shoe-1"}


def test_one_piece_per_layer() -> None:
    """Two shirts must not both be named — a direction picks, it does not list."""
    wardrobe = [
        _item(id="top-1", canonical_category="top"),
        _item(id="top-2", canonical_category="top"),
    ]
    direction = build_direction(mood="confident", occasion=None, wardrobe=wardrobe)
    assert direction.item_ids == ["top-1"]


def test_the_mood_palette_wins_over_arrival_order() -> None:
    """A 'calm' plan should reach for the cream shirt, not the red one."""
    wardrobe = [
        _item(id="red", canonical_category="top", color="red"),
        _item(id="cream", canonical_category="top", color="cream"),
    ]
    direction = build_direction(mood="calm", occasion=None, wardrobe=wardrobe)
    assert direction.item_ids == ["cream"]


def test_style_memory_only_breaks_ties() -> None:
    """Preferred colours reorder candidates; they never override the mood."""
    wardrobe = [
        _item(id="red", canonical_category="top", color="red"),
        _item(id="cream", canonical_category="top", color="cream"),
    ]
    # 'red' is preferred, but 'cream' is in the calm palette, so calm still wins.
    direction = build_direction(
        mood="calm", occasion=None, wardrobe=wardrobe, preferred_colors=["red"]
    )
    assert direction.item_ids == ["cream"]

    # Within the SAME palette bucket, the preference decides.
    same_bucket = [
        _item(id="grey", canonical_category="top", color="grey"),
        _item(id="sand", canonical_category="top", color="sand"),
    ]
    direction = build_direction(
        mood="calm", occasion=None, wardrobe=same_bucket, preferred_colors=["sand"]
    )
    assert direction.item_ids == ["sand"]


def test_the_occasion_adds_a_note() -> None:
    with_occasion = build_direction(mood="bold", occasion="wedding", wardrobe=[])
    without = build_direction(mood="bold", occasion=None, wardrobe=[])
    assert len(with_occasion.lines) == len(without.lines) + 1


def test_an_unknown_occasion_is_ignored_not_echoed() -> None:
    direction = build_direction(mood="bold", occasion="moon_landing", wardrobe=[])
    assert all("moon_landing" not in line for line in direction.lines)


def test_the_same_inputs_give_the_same_plan() -> None:
    """Deterministic: re-opening a plan must not silently re-roll it."""
    wardrobe = [_item(id=f"i{i}", canonical_category="top", color="black") for i in range(5)]
    first = build_direction(mood="rebel", occasion="night_out", wardrobe=wardrobe)
    second = build_direction(mood="rebel", occasion="night_out", wardrobe=wardrobe)
    assert first.as_json() == second.as_json()


def test_free_text_categories_still_resolve() -> None:
    """A closet tagged before 0069's canonical vocabulary must still work."""
    wardrobe = [
        _Row(
            {
                "id": "legacy-1",
                "title": "Blue jeans",
                "category": "Jeans",
                "subcategory": None,
                "color": "denim",
            }
        )
    ]
    direction = build_direction(mood="rebel", occasion=None, wardrobe=wardrobe)
    assert direction.item_ids == ["legacy-1"]


def test_an_unrecognised_category_is_left_unnamed() -> None:
    """Better silent than mis-described."""
    wardrobe = [_item(id="mystery", canonical_category="teapot", category="Teapot")]
    direction = build_direction(mood="calm", occasion=None, wardrobe=wardrobe)
    assert direction.item_ids == []
    assert direction.generic is True
