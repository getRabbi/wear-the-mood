"""Canonical garment taxonomy and try-on roles (CLAUDE.md §5, §7).

THE ONE PLACE a garment's try-on role is decided. Flutter, the products catalog,
the wardrobe and the FASHN provider all used to carry their own free-text idea of
what a "category" was, and the gap between them is what let a shirt be rendered
as a full outfit: nothing downstream knew what the piece actually was, so the
provider was asked to guess (`category="auto"`).

Three layers, deliberately separate:

  1. **Canonical category** — Wear The Mood's own vocabulary ([CANONICAL]).
     Stored on the row. Provider-independent, so swapping FASHN for Leffa later
     changes layer 3 and nothing else.
  2. **Try-on role** — what the canonical category means for a rendered body:
     which region it occupies, when it must be applied, what it conflicts with.
  3. **Provider route** — the concrete model + parameters (services/tryon/routing.py).

Resolution is DETERMINISTIC and never guesses. A string it does not recognise
resolves to ``None``, which the planner turns into `needs_review` — the item stays
visible everywhere in the app and is simply not eligible for try-on until somebody
says what it is. That is the whole point: a wrong guess renders the wrong garment
on someone's body, an honest "unknown" only asks a question.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum

# ── layer 1: the canonical vocabulary ────────────────────────────────────────

TOP = "top"
BOTTOM = "bottom"
ONE_PIECE = "one_piece"
OUTERWEAR = "outerwear"
HIJAB_SCARF = "hijab_scarf"
GLASSES = "glasses"
HAT_HEADWEAR = "hat_headwear"
SHOES = "shoes"
BAG = "bag"
JEWELRY = "jewelry"
BELT = "belt"
OTHER = "other"
#: A photo of a COMPLETE outfit on someone, used as a reference rather than as a
#: single garment — what "Try this look" on a community post hands us. It is not
#: a closet category and no user can pick it; only that handoff sets it. It
#: exists because the alternative was sending a whole-outfit photograph to an
#: apparel model as if it were one garment, which is the same guess this whole
#: taxonomy is here to remove.
LOOK_REFERENCE = "look_reference"

#: Every canonical category. Stored in `wardrobe_items.canonical_category` and
#: `products.canonical_category`; mirrored in the Flutter client for UX only.
CANONICAL_CATEGORIES: tuple[str, ...] = (
    TOP,
    BOTTOM,
    ONE_PIECE,
    OUTERWEAR,
    HIJAB_SCARF,
    GLASSES,
    HAT_HEADWEAR,
    SHOES,
    BAG,
    JEWELRY,
    BELT,
    OTHER,
    LOOK_REFERENCE,
)

#: Classification outcomes stored alongside the category.
STATUS_VALID = "valid"
STATUS_NEEDS_REVIEW = "needs_review"


class TryOnSupport(StrEnum):
    """How well the ACTIVE provider renders this category.

    Verified against the live FASHN API (2026-08), not assumed. `UNSUPPORTED` is
    a statement about the provider, never about the product: an unsupported piece
    keeps all of its data, stays visible, and is reported as skipped-with-reason
    rather than quietly dropped from a look (§29).
    """

    SUPPORTED = "supported"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class RoleSpec:
    """What a canonical category means to the renderer."""

    canonical: str
    #: Ascending application order. Apparel first, accessories last — a garment
    #: pass repaints a whole body region and would wipe an accessory applied
    #: before it. Verified by the chaining regression tests.
    order: int
    #: Categories that cannot appear in the same look (both directions).
    excludes: frozenset[str]
    support: TryOnSupport
    #: Human-readable region, used in user-facing plan explanations.
    region: str


_SPECS: dict[str, RoleSpec] = {
    # First, and incompatible with every apparel role: it IS the outfit, so
    # layering a separate top over it would be two answers to the same question.
    LOOK_REFERENCE: RoleSpec(
        LOOK_REFERENCE,
        5,
        frozenset({TOP, BOTTOM, ONE_PIECE, OUTERWEAR}),
        TryOnSupport.SUPPORTED,
        "whole outfit",
    ),
    ONE_PIECE: RoleSpec(
        ONE_PIECE, 10, frozenset({TOP, BOTTOM}), TryOnSupport.SUPPORTED, "full body"
    ),
    BOTTOM: RoleSpec(BOTTOM, 20, frozenset({ONE_PIECE}), TryOnSupport.SUPPORTED, "lower body"),
    TOP: RoleSpec(TOP, 30, frozenset({ONE_PIECE}), TryOnSupport.SUPPORTED, "upper body"),
    OUTERWEAR: RoleSpec(OUTERWEAR, 40, frozenset(), TryOnSupport.SUPPORTED, "outer layer"),
    SHOES: RoleSpec(SHOES, 50, frozenset(), TryOnSupport.SUPPORTED, "feet"),
    BAG: RoleSpec(BAG, 60, frozenset(), TryOnSupport.SUPPORTED, "carried"),
    HIJAB_SCARF: RoleSpec(HIJAB_SCARF, 70, frozenset(), TryOnSupport.SUPPORTED, "head"),
    HAT_HEADWEAR: RoleSpec(HAT_HEADWEAR, 80, frozenset(), TryOnSupport.SUPPORTED, "head"),
    GLASSES: RoleSpec(GLASSES, 90, frozenset(), TryOnSupport.SUPPORTED, "face"),
    JEWELRY: RoleSpec(JEWELRY, 95, frozenset(), TryOnSupport.SUPPORTED, "accessory"),
    # FASHN documents try-on for "clothing, shoes, hats, jewelry, bags"; belts are
    # not among them and rendered poorly in QA, so we say so instead of pretending.
    BELT: RoleSpec(BELT, 96, frozenset(), TryOnSupport.UNSUPPORTED, "waist"),
    OTHER: RoleSpec(OTHER, 99, frozenset(), TryOnSupport.UNSUPPORTED, "unspecified"),
}


def role_spec(canonical: str | None) -> RoleSpec | None:
    return _SPECS.get(canonical or "")


def is_supported(canonical: str | None) -> bool:
    spec = role_spec(canonical)
    return spec is not None and spec.support is TryOnSupport.SUPPORTED


def render_order(canonical: str | None) -> int:
    spec = role_spec(canonical)
    return spec.order if spec else 99


#: Canonical categories a look can actually be rendered from, for SQL/eligibility.
TRYON_CAPABLE_CATEGORIES: tuple[str, ...] = tuple(
    c for c in CANONICAL_CATEGORIES if is_supported(c)
)


# ── normalization: free text -> canonical ────────────────────────────────────

_WORD_RE = re.compile(r"[^a-z0-9]+")


def _norm(value: str | None) -> str:
    """Lowercase, punctuation-stripped, single-spaced. `"T-Shirts"` -> `"t shirts"`."""
    if not value:
        return ""
    return _WORD_RE.sub(" ", value.lower()).strip()


#: EXACT matches for vocabularies we control end to end — the Flutter closet
#: taxonomy (`wardrobe_categories.dart`) and our own canonical values. Exact
#: beats phrase matching so "Dresses" can never be read as a "dress shirt".
_EXACT: dict[str, str] = {
    # canonical values round-trip unchanged
    **{c.replace("_", " "): c for c in CANONICAL_CATEGORIES},
    **{c: c for c in CANONICAL_CATEGORIES},
    # Flutter closet taxonomy — tops
    "tops": TOP,
    "t shirts": TOP,
    "tshirts": TOP,
    "shirts": TOP,
    "blouses": TOP,
    "tunics kurtis": TOP,
    # bottoms
    "bottoms": BOTTOM,
    "pants": BOTTOM,
    "jeans": BOTTOM,
    "skirts": BOTTOM,
    "shorts": BOTTOM,
    # one-piece
    "dresses": ONE_PIECE,
    # The closet groups "Traditional" under One-piece (abaya/kurta sets), which is
    # an explicit product decision, not an inference — so it is honoured here.
    "traditional": ONE_PIECE,
    # outerwear
    "outerwear": OUTERWEAR,
    "winter": OUTERWEAR,
    # footwear / modest / accessories
    "shoes": SHOES,
    "hijab": HIJAB_SCARF,
    "scarves": HIJAB_SCARF,
    "bags": BAG,
    "eyewear": GLASSES,
    "jewelry": JEWELRY,
    "jewellery": JEWELRY,
    "belts": BELT,
    "hats": HAT_HEADWEAR,
}

#: Lifestyle / occasion buckets that name WHEN a piece is worn, not WHAT it is.
#: Listed explicitly so they resolve to "unknown" rather than falling through to
#: a phrase match on some unrelated word in the title.
_NOT_A_ROLE: frozenset[str] = frozenset(
    {
        "accessories",
        "accessory",
        "activewear",
        "sleepwear",
        "swimwear",
        "workwear",
        "party",
        "travel",
        "uncategorized",
        "uncategorised",
        "misc",
        "general",
        "new",
        "sale",
        "clothing",
        "apparel",
        "fashion",
        "women",
        "womens",
        "men",
        "mens",
        "unisex",
        "kids",
    }
)

#: Ordered phrase table. FIRST match wins, so multi-word and ambiguity-resolving
#: entries come before the bare nouns they contain ("dress shirt" before "dress",
#: "swim shorts" before "shorts"). Matched on word boundaries against the
#: normalized string, so "laptop bag" cannot match "top".
_PHRASES: tuple[tuple[str, str], ...] = (
    # --- disambiguators that must outrank a shorter noun below ---
    ("dress shirt", TOP),
    ("dress shirts", TOP),
    ("shirt dress", ONE_PIECE),
    ("shirtdress", ONE_PIECE),
    ("sun dress", ONE_PIECE),
    ("sundress", ONE_PIECE),
    ("dress pants", BOTTOM),
    ("dress trousers", BOTTOM),
    ("dress shoes", SHOES),
    ("tank top", TOP),
    ("crop top", TOP),
    ("tube top", TOP),
    ("halter top", TOP),
    ("wrap top", TOP),
    ("bikini top", TOP),
    ("swim shorts", BOTTOM),
    ("swim trunks", BOTTOM),
    ("bomber jacket", OUTERWEAR),
    ("denim jacket", OUTERWEAR),
    ("leather jacket", OUTERWEAR),
    ("jacket", OUTERWEAR),
    ("shoulder bag", BAG),
    ("bucket hat", HAT_HEADWEAR),
    ("bucket bag", BAG),
    # --- one-piece ---
    ("jumpsuit", ONE_PIECE),
    ("playsuit", ONE_PIECE),
    ("romper", ONE_PIECE),
    ("overall", ONE_PIECE),
    ("dungaree", ONE_PIECE),
    ("abaya", ONE_PIECE),
    ("jilbab", ONE_PIECE),
    ("kaftan", ONE_PIECE),
    ("caftan", ONE_PIECE),
    ("kurta set", ONE_PIECE),
    ("salwar", ONE_PIECE),
    ("shalwar", ONE_PIECE),
    ("saree", ONE_PIECE),
    ("sari", ONE_PIECE),
    ("lehenga", ONE_PIECE),
    ("anarkali", ONE_PIECE),
    ("gown", ONE_PIECE),
    ("frock", ONE_PIECE),
    ("dress", ONE_PIECE),
    ("one piece", ONE_PIECE),
    ("onepiece", ONE_PIECE),
    # --- outerwear ---
    ("overcoat", OUTERWEAR),
    ("trench coat", OUTERWEAR),
    ("trench", OUTERWEAR),
    ("raincoat", OUTERWEAR),
    ("parka", OUTERWEAR),
    ("puffer", OUTERWEAR),
    ("anorak", OUTERWEAR),
    ("windbreaker", OUTERWEAR),
    ("blazer", OUTERWEAR),
    ("coat", OUTERWEAR),
    ("outer", OUTERWEAR),
    ("shrug", OUTERWEAR),
    ("waistcoat", OUTERWEAR),
    # --- tops ---
    ("t shirt", TOP),
    ("tshirt", TOP),
    ("tee shirt", TOP),
    ("polo", TOP),
    ("henley", TOP),
    ("blouse", TOP),
    ("camisole", TOP),
    ("bodysuit", TOP),
    ("hoodie", TOP),
    ("sweatshirt", TOP),
    ("sweater", TOP),
    ("pullover", TOP),
    ("jumper", TOP),
    ("cardigan", TOP),
    ("knitwear", TOP),
    ("kurti", TOP),
    ("tunic", TOP),
    ("shirt", TOP),
    ("top", TOP),
    ("tee", TOP),
    ("vest", TOP),
    # --- bottoms ---
    ("trouser", BOTTOM),
    ("chino", BOTTOM),
    ("jogger", BOTTOM),
    ("sweatpant", BOTTOM),
    ("legging", BOTTOM),
    ("jegging", BOTTOM),
    ("culotte", BOTTOM),
    ("palazzo", BOTTOM),
    ("capri", BOTTOM),
    ("denim", BOTTOM),
    ("jean", BOTTOM),
    ("skirt", BOTTOM),
    ("short", BOTTOM),
    ("pant", BOTTOM),
    ("bottom", BOTTOM),
    # --- head ---
    ("hijab", HIJAB_SCARF),
    ("khimar", HIJAB_SCARF),
    ("shayla", HIJAB_SCARF),
    ("niqab", HIJAB_SCARF),
    ("dupatta", HIJAB_SCARF),
    ("headscarf", HIJAB_SCARF),
    ("head scarf", HIJAB_SCARF),
    ("scarf", HIJAB_SCARF),
    ("shawl", HIJAB_SCARF),
    ("stole", HIJAB_SCARF),
    ("turban", HAT_HEADWEAR),
    ("beanie", HAT_HEADWEAR),
    ("headband", HAT_HEADWEAR),
    ("baseball cap", HAT_HEADWEAR),
    ("cap", HAT_HEADWEAR),
    ("hat", HAT_HEADWEAR),
    # --- face ---
    ("sunglass", GLASSES),
    ("eyeglass", GLASSES),
    ("eyewear", GLASSES),
    ("spectacle", GLASSES),
    ("glasses", GLASSES),
    ("shades", GLASSES),
    # --- feet ---
    ("sneaker", SHOES),
    ("trainer", SHOES),
    ("loafer", SHOES),
    ("sandal", SHOES),
    ("heel", SHOES),
    ("boot", SHOES),
    ("flip flop", SHOES),
    ("slipper", SHOES),
    ("mule", SHOES),
    ("oxford", SHOES),
    ("shoe", SHOES),
    ("footwear", SHOES),
    # --- carried ---
    ("handbag", BAG),
    ("backpack", BAG),
    ("satchel", BAG),
    ("clutch", BAG),
    ("tote", BAG),
    ("purse", BAG),
    ("crossbody", BAG),
    ("bag", BAG),
    # --- jewelry ---
    ("necklace", JEWELRY),
    ("earring", JEWELRY),
    ("bracelet", JEWELRY),
    ("bangle", JEWELRY),
    ("anklet", JEWELRY),
    ("brooch", JEWELRY),
    ("pendant", JEWELRY),
    ("ring", JEWELRY),
    ("watch", JEWELRY),
    ("jewel", JEWELRY),
    # --- waist ---
    ("belt", BELT),
)


def _singular(word: str) -> str:
    """Conservative English de-pluralisation, so the phrase table can stay singular.

    Deliberately blunt and deliberately small. It only has to turn the plurals
    that actually appear in catalogue titles and closet categories back into the
    nouns the table lists — "sunglasses"->"sunglass", "dresses"->"dress",
    "trousers"->"trouser" — and it must never mangle a word that is already
    singular ("dress" ends in a double s and is left alone).
    """
    if len(word) > 4 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 4 and word.endswith(("ses", "xes", "ches", "shes")):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def _phrase_match(text: str) -> str | None:
    """First phrase whose words appear consecutively in `text`, else None.

    Matched on word boundaries against both the text as written and a
    de-pluralised copy of it, so "laptop bag" can never satisfy "top" while
    "Wide Leg Trousers" still satisfies "trouser".
    """
    if not text:
        return None
    candidates = {f" {text} "}
    singular = " ".join(_singular(w) for w in text.split())
    candidates.add(f" {singular} ")
    for phrase, canonical in _PHRASES:
        needle = f" {phrase} "
        if any(needle in candidate for candidate in candidates):
            return canonical
    return None


@dataclass(frozen=True)
class Classification:
    """The resolved role plus WHERE it came from, so the decision is auditable."""

    canonical: str | None
    #: "canonical_column" | "category" | "subcategory" | "title" | None
    source: str | None

    @property
    def status(self) -> str:
        return STATUS_VALID if self.canonical else STATUS_NEEDS_REVIEW

    @property
    def resolved(self) -> bool:
        return self.canonical is not None


_UNRESOLVED = Classification(None, None)


def classify_value(value: str | None) -> str | None:
    """Canonical category for ONE free-text value, or None when unrecognised."""
    text = _norm(value)
    if not text:
        return None
    if text in _EXACT:
        return _EXACT[text]
    if text in _NOT_A_ROLE:
        return None
    return _phrase_match(text)


def classify(
    *,
    canonical: str | None = None,
    category: str | None = None,
    subcategory: str | None = None,
    title: str | None = None,
) -> Classification:
    """Resolve a garment's canonical category from the most trustworthy field
    available, in priority order (Phase 5 backfill priority):

      1. an already-stored canonical value,
      2. the structured category,
      3. the structured subcategory,
      4. the product/item title.

    Titles are last because they are marketing copy: "Summer Dress Shirt" is a
    shirt, and only the ordered phrase table makes that reliable. Anything the
    table does not recognise returns unresolved — never a default.
    """
    stored = _norm(canonical)
    if stored in _SPECS:
        return Classification(stored, "canonical_column")

    for value, source in ((category, "category"), (subcategory, "subcategory"), (title, "title")):
        hit = classify_value(value)
        if hit:
            return Classification(hit, source)
    return _UNRESOLVED
