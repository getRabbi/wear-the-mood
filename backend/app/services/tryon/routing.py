"""Canonical category -> FASHN model + parameters (CLAUDE.md §2.2, §13).

Layer 3 of the taxonomy stack (see `taxonomy.py`). Kept separate from the
canonical vocabulary on purpose: the database must never learn a vendor's enum,
so replacing FASHN with a self-hosted engine later rewrites THIS file and
nothing else.

Everything here was verified against the live FASHN API on 2026-08-15 by
submitting deliberately-invalid values and reading the validation error back —
not from memory and not from this repo's older comments:

  * ``tryon-v1.6``  — ``category`` ∈ {tops, bottoms, one-pieces, auto},
                      ``mode`` ∈ {performance, balanced, quality},
                      ``garment_photo_type`` ∈ {auto, flat-lay, model}.
                      Apparel only: there is no accessory category.
  * ``tryon-max``   — ``category`` is REJECTED ("category is not allowed"),
                      ``product_images`` (plural) is REJECTED, so there is no
                      native multi-garment call: a look is chained either way.
                      Accepts a free-text ``prompt``, which is the only
                      provider-supported preservation mechanism we have, plus
                      ``generation_mode`` ∈ {fast, balanced, quality} and
                      ``resolution`` ∈ {1k, 2k, 4k}. FASHN documents it for
                      "clothing, shoes, hats, jewelry, bags and other wearable
                      fashion items", which is why accessories route here.

Cost note (§14/§19): both models bill ONE external FASHN credit per output at the
settings this file pins (v1.6 is flat-rate; tryon-max is pinned to fast·1k by the
provider's central spend cap). Routing an accessory to tryon-max therefore costs
exactly what routing it to v1.6 would have — it is simply the model that can
actually render it. The USER's credit cost is unchanged and is charged once per
look, not per step.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.services.tryon import taxonomy as tax

#: The apparel engine. Region-accurate because we pass an explicit category.
APPAREL_MODEL = "tryon-v1.6"
#: The accessory/layering engine. Prompt-steerable, no category enum.
ACCESSORY_MODEL = "tryon-max"

ENGINE_APPAREL = "apparel"
ENGINE_ACCESSORY = "accessory"

#: canonical -> the FASHN `category` enum. ONLY these three exist; anything else
#: is not an apparel category and must not be sent to the apparel model.
_FASHN_CATEGORY: dict[str, str] = {
    tax.TOP: "tops",
    tax.BOTTOM: "bottoms",
    tax.ONE_PIECE: "one-pieces",
}

#: The shared tail of every accessory prompt. This is the Phase 9 preservation
#: instruction: a later pass must ADD its item and change nothing else. Written
#: as one sentence per protected thing because the model follows explicit,
#: separable clauses far more reliably than one long compound sentence.
_PRESERVE = (
    "Add only this item. Keep the person's face, identity, hair, skin tone, body "
    "shape and pose exactly as they are. Keep every garment they are already "
    "wearing exactly as it is: do not replace, restyle, recolour or remove any "
    "existing clothing. Keep the background unchanged."
)

#: The tail for a pass that is MEANT to change the clothing (a whole-look
#: reference). It keeps the person and drops the garment-preservation clause,
#: which would otherwise instruct the model to do the opposite of the request.
_PRESERVE_PERSON_ONLY = (
    "Keep the person's face, identity, hair, skin tone, body shape and pose "
    "exactly as they are. Keep the background unchanged."
)

#: Roles whose pass replaces clothing instead of adding to it.
_REPLACES_OUTFIT = frozenset({tax.LOOK_REFERENCE})

#: canonical -> the instruction that names WHAT is being added. Paired with
#: `_PRESERVE` to build the final prompt.
_ADD_INSTRUCTION: dict[str, str] = {
    tax.LOOK_REFERENCE: (
        "Dress the person in the complete outfit worn by the person in the "
        "product image, keeping each garment's colour, pattern and shape."
    ),
    tax.OUTERWEAR: (
        "Put the outerwear from the product image on the person as an outer "
        "layer, worn open or as shown, over the clothes they already have on."
    ),
    tax.HIJAB_SCARF: (
        "Place the headscarf from the product image on the person's head, draped "
        "naturally and covering the hair as a hijab is normally worn."
    ),
    tax.HAT_HEADWEAR: "Place the headwear from the product image on the person's head.",
    tax.GLASSES: (
        "Place the eyewear from the product image on the person's face, resting "
        "correctly on the nose and ears."
    ),
    tax.SHOES: "Put the footwear from the product image on the person's feet.",
    tax.BAG: (
        "Give the person the bag from the product image, carried or worn the way "
        "that style of bag normally is."
    ),
    tax.JEWELRY: "Place the jewellery from the product image on the person.",
}


@dataclass(frozen=True)
class ProviderRoute:
    """The concrete provider call for one canonical category."""

    #: Which FASHN model_name to submit.
    model_name: str
    #: Coarse engine label, for logs/plan explanations and tests.
    engine: str
    #: FASHN `category` enum — apparel model only, never None there.
    category: str | None = None
    #: FASHN `prompt` — accessory model only.
    prompt: str | None = None


def route_for(canonical: str | None) -> ProviderRoute | None:
    """The provider route for a canonical category, or None when the provider
    cannot render it. Never falls back to `auto` and never guesses a region —
    an unroutable category is reported as skipped-with-reason (§29)."""
    if not tax.is_supported(canonical):
        return None
    assert canonical is not None  # is_supported implies a known category
    fashn_category = _FASHN_CATEGORY.get(canonical)
    if fashn_category is not None:
        return ProviderRoute(APPAREL_MODEL, ENGINE_APPAREL, category=fashn_category)
    instruction = _ADD_INSTRUCTION.get(canonical)
    if instruction is None:  # supported but unrouted would be a taxonomy bug
        return None
    preserve = _PRESERVE_PERSON_ONLY if canonical in _REPLACES_OUTFIT else _PRESERVE
    return ProviderRoute(ACCESSORY_MODEL, ENGINE_ACCESSORY, prompt=f"{instruction} {preserve}")


# ── garment photo type (apparel model only) ──────────────────────────────────
#
# FASHN accepts `garment_photo_type` ∈ {auto, flat-lay, model} and uses it to
# decide how to read the reference image. We send a real value only where we
# genuinely KNOW it, which is exactly one case: a wardrobe cutout is a
# background-removed garment on its own, i.e. a flat-lay by construction. A
# user's raw closet photo, a catalog image or a community photo could be either,
# so those stay `auto` — inventing metadata is what this whole fix exists to stop.

PHOTO_TYPE_AUTO = "auto"
PHOTO_TYPE_FLAT_LAY = "flat-lay"


def garment_photo_type(*, is_cutout: bool) -> str:
    return PHOTO_TYPE_FLAT_LAY if is_cutout else PHOTO_TYPE_AUTO
