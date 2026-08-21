"""Mood Planner v2 — styling direction with no render (spec §14).

The point of this module is what it does NOT do: it never calls FASHN, never
calls an LLM, never reserves a credit and never touches the credit ledger. A
mood plan costs zero, which is precisely why it can be the daily habit that an
image generator can never be.

The direction is DETERMINISTIC — mood and occasion map to guidance, and the
wardrobe supplies real pieces to hang it on. Three reasons that beats a model
call here:

  * it works with no provider key, no credits and no network to a third party;
  * the same mood on the same day gives the same answer, so re-opening the plan
    does not silently re-roll it under the user;
  * it cannot hallucinate a garment the user does not own.

Rendering stays a separate, explicit, paid act — the user taps "See it on me".
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import asyncpg

#: The app's four mood zones (ui/home/wtm_mood.dart). Kept as the vocabulary
#: here so the client never has to translate before it can ask.
MOODS = ("calm", "confident", "bold", "rebel")

#: Optional context. `None` is valid — the user may just have picked a feeling.
OCCASIONS = ("everyday", "work", "date", "brunch", "wedding", "night_out")


@dataclass(frozen=True)
class MoodProfile:
    headline: str
    #: The energy the outfit should carry.
    energy: str
    #: Palette words, matched loosely against wardrobe colours.
    palette: tuple[str, ...]
    #: Shape/silhouette direction.
    silhouette: str


_MOOD_PROFILES: dict[str, MoodProfile] = {
    "calm": MoodProfile(
        headline="Quiet and easy",
        energy="soft, unhurried, nothing shouting",
        palette=("cream", "beige", "sand", "grey", "white", "stone", "taupe"),
        silhouette="relaxed shapes with one clean line",
    ),
    "confident": MoodProfile(
        headline="Put together",
        energy="composed, deliberate, quietly certain",
        palette=("black", "navy", "charcoal", "white", "camel", "brown"),
        silhouette="structured on top, simple below",
    ),
    "bold": MoodProfile(
        headline="Turn it up",
        energy="one piece doing the talking",
        palette=("red", "cobalt", "emerald", "orange", "yellow", "pink"),
        silhouette="one statement piece, everything else quiet",
    ),
    "rebel": MoodProfile(
        headline="Break the rules",
        energy="unbothered, a little off-script",
        palette=("black", "denim", "olive", "grey", "leather", "khaki"),
        silhouette="oversized against something fitted",
    ),
}

_OCCASION_NOTES: dict[str, str] = {
    "everyday": "Keep it easy — you should forget you are wearing it by noon.",
    "work": "Keep one polished anchor: a jacket, a clean shoe or a sharp trouser.",
    "date": "Pick one thing you feel unmistakably good in and build around it.",
    "brunch": "Daylight-friendly: lighter fabrics, comfortable shoes, one nice detail.",
    "wedding": "Dress for the room, not the photos — and check the shoes for standing.",
    "night_out": "Darker base, one high-contrast piece, nothing you have to hold.",
}

#: Wardrobe categories worth naming in a direction, in the order a look is built.
_LAYER_ORDER = ("one_piece", "top", "bottom", "outerwear", "shoes", "bag")


@dataclass
class MoodDirection:
    mood: str
    occasion: str | None
    headline: str
    lines: list[str] = field(default_factory=list)
    #: Wardrobe item ids this direction referenced, in build order.
    item_ids: list[str] = field(default_factory=list)
    #: True when the wardrobe was too thin to name real pieces — the direction
    #: is still given, but it must not pretend to have picked from a closet.
    generic: bool = False

    def as_json(self) -> dict[str, Any]:
        return {
            "mood": self.mood,
            "occasion": self.occasion,
            "headline": self.headline,
            "lines": self.lines,
            "item_ids": self.item_ids,
            "generic": self.generic,
        }


def _matches_palette(color: str | None, palette: tuple[str, ...]) -> bool:
    if not color:
        return False
    lowered = color.lower()
    return any(word in lowered for word in palette)


def _describe(row: asyncpg.Record) -> str:
    bits = [row["color"], row["subcategory"] or row["title"] or row["category"]]
    return " ".join(str(b) for b in bits if b) or "a piece from your closet"


def build_direction(
    *,
    mood: str,
    occasion: str | None,
    wardrobe: list[asyncpg.Record],
    preferred_colors: list[str] | None = None,
) -> MoodDirection:
    """Compose the direction. Pure and deterministic given its inputs.

    `preferred_colors` comes from Style Memory when the user has one; it only
    ever REORDERS candidates, never invents a piece or overrides the mood. A
    user with no Style Memory gets an equally complete plan.
    """
    profile = _MOOD_PROFILES.get(mood) or _MOOD_PROFILES["confident"]
    liked = [c.lower() for c in (preferred_colors or [])]

    def rank(row: asyncpg.Record) -> tuple[int, int, str]:
        color = (row["color"] or "").lower()
        return (
            0 if _matches_palette(color, profile.palette) else 1,
            0 if any(c in color for c in liked) else 1,
            str(row["id"]),
        )

    by_layer: dict[str, asyncpg.Record] = {}
    for row in sorted(wardrobe, key=rank):
        layer = _layer_of(row)
        if layer and layer not in by_layer:
            by_layer[layer] = row

    lines = [f"Aim for {profile.energy}.", f"Shape: {profile.silhouette}."]
    if occasion and occasion in _OCCASION_NOTES:
        lines.append(_OCCASION_NOTES[occasion])

    picked = [by_layer[layer] for layer in _LAYER_ORDER if layer in by_layer]
    if picked:
        named = ", then ".join(_describe(r) for r in picked[:3])
        lines.append(f"From your closet: start with {named}.")
    else:
        lines.append("Your closet is still light — add a few pieces and this gets specific.")

    return MoodDirection(
        mood=mood,
        occasion=occasion,
        headline=profile.headline,
        lines=lines,
        item_ids=[str(r["id"]) for r in picked],
        generic=not picked,
    )


def _layer_of(row: asyncpg.Record) -> str | None:
    """Map a wardrobe row onto a build layer using the columns that exist on it.

    Prefers `canonical_category` where the row has one (0069's machine-readable
    vocabulary); otherwise falls back to the free-text category the user or the
    tagger wrote. Deliberately forgiving: an unrecognised category yields None
    and the piece is simply not named, which is better than mis-describing it.
    """
    canonical = None
    if "canonical_category" in row.keys():
        canonical = row["canonical_category"]
    raw = str(canonical or row["category"] or "").lower()
    if not raw:
        return None
    if any(k in raw for k in ("dress", "one_piece", "jumpsuit", "abaya", "gown")):
        return "one_piece"
    if any(k in raw for k in ("coat", "jacket", "outerwear", "blazer", "cardigan")):
        return "outerwear"
    if any(k in raw for k in ("shoe", "sneaker", "boot", "heel", "sandal")):
        return "shoes"
    if any(k in raw for k in ("bag", "purse", "tote", "clutch", "backpack")):
        return "bag"
    if any(k in raw for k in ("trouser", "pant", "jean", "skirt", "short", "bottom")):
        return "bottom"
    if any(k in raw for k in ("top", "shirt", "tee", "blouse", "sweater", "knit", "hoodie")):
        return "top"
    return None
