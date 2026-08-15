from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

# Max garments in one AI look — the worker chains a provider call per garment,
# so each one adds latency/cost; keep the stack reasonable.
MAX_GARMENTS = 6


# Try-On Body System (BUILD_PROMPT_PRO_PROMAX.md): where the body comes from.
#   own_photo    — the user's saved/uploaded body photo (default; unchanged).
#   studio_model — a curated studio model preset (Pro/Pro Max; server-resolved).
#   user_avatar  — My Style Model (FUTURE-READY only; rejected for now).
MODEL_SOURCES = ("own_photo", "studio_model", "user_avatar")


class TryOnGarmentInput(BaseModel):
    """ONE selected piece, described well enough that the server never has to
    guess what it is (spec Phases 2/4).

    The ids are what matter. `category` is a HINT and is used only for a piece we
    hold no row for — a sample-rack garment or a community look's image — because
    a client-declared category on an item we own would be a client deciding how
    its own body gets rendered, which is exactly the authority §11 keeps server
    side. Everything owned is re-read from `wardrobe_items` / `products`.
    """

    image_url: str = Field(min_length=1, max_length=2000)
    wardrobe_item_id: UUID | None = None
    source_product_id: UUID | None = None
    #: Free-text category from the client's own taxonomy (e.g. "Tops", "Jeans").
    category: str | None = Field(default=None, max_length=80)


class TryOnRequest(BaseModel):
    """Create-job payload. The person image is the user's avatar/selfie (own_photo)
    OR a studio model (studio_model, resolved server-side from preset_model_id);
    the garment source is EXACTLY ONE of:
      - garments:            the structured stack (current clients) — each piece
                             carries its identity, so the server resolves a real
                             canonical role instead of asking the provider
      - garment_image_urls:  bare URLs in tap order (SHIPPED clients, ≤1.0.21)
      - garment_image_url:   a single garment URL (legacy single-garment)
      - wardrobe_item_id:    one of the user's owned items (resolved server-side)

    The three legacy shapes are kept working exactly as they are: an installed
    app cannot be asked to update before its next render, so the server recovers
    each garment's role from storage/the catalog instead (see services/tryon/
    resolve.py) and records it when it genuinely cannot.
    """

    person_image_url: str = Field(min_length=1)
    garment_image_url: str | None = None
    garment_image_urls: list[str] | None = None
    garments: list[TryOnGarmentInput] | None = None
    wardrobe_item_id: UUID | None = None
    # Try-On Body System. own_photo keeps the unchanged behaviour. studio_model
    # requires preset_model_id and is server-resolved + Pro/Pro Max gated.
    model_source: str = "own_photo"
    preset_model_id: UUID | None = None
    # HD / Try-On Max render — costs 4 credits and is gated to Pro Max
    # (plan.hd_allowed). Default false = the unchanged standard render (1 credit).
    hd: bool = False

    # ---- shopping origin (DISCOVER §13) ----
    # Optional and absent for every closet render, so an older client's payload
    # is unchanged. Only the PRODUCT id is accepted: the merchant is derived
    # server-side from it, because a client-supplied merchant is a client-chosen
    # attribution (§38). No price, no URL, no tag — none of that is the client's
    # to state, and a price cached here would be a purchase claim nobody
    # re-verified.
    source_product_id: UUID | None = None
    source_placement: str | None = Field(default=None, max_length=32)
    source_campaign_id: str | None = Field(default=None, max_length=128)

    @model_validator(mode="after")
    def _valid_model_source(self) -> TryOnRequest:
        if self.model_source not in MODEL_SOURCES:
            raise ValueError(f"model_source must be one of {MODEL_SOURCES}.")
        if self.model_source == "studio_model" and self.preset_model_id is None:
            raise ValueError("preset_model_id is required for a studio model.")
        return self

    @model_validator(mode="after")
    def _exactly_one_garment_source(self) -> TryOnRequest:
        sources = [
            bool(self.garment_image_url),
            bool(self.wardrobe_item_id),
            bool(self.garment_image_urls),
            bool(self.garments),
        ]
        if sum(sources) != 1:
            raise ValueError(
                "Provide exactly one of garments, garment_image_url, "
                "garment_image_urls or wardrobe_item_id."
            )
        if self.garment_image_urls is not None:
            cleaned = [u for u in self.garment_image_urls if u and u.strip()]
            if not cleaned:
                raise ValueError("garment_image_urls must contain at least one image.")
            if len(cleaned) > MAX_GARMENTS:
                raise ValueError(f"At most {MAX_GARMENTS} garments per look.")
            self.garment_image_urls = cleaned
        if self.garments is not None:
            kept = [g for g in self.garments if g.image_url and g.image_url.strip()]
            if not kept:
                raise ValueError("garments must contain at least one image.")
            if len(kept) > MAX_GARMENTS:
                raise ValueError(f"At most {MAX_GARMENTS} garments per look.")
            self.garments = kept
        return self


class TryOnSource(BaseModel):
    """Where a render came from, when it came from the catalog (§13).

    Identifiers only. Everything a purchase decision needs — price, stock,
    variants, the destination itself — is re-read live through the Discover
    endpoints when the user acts, never restored from here (§35, §38).
    """

    kind: str = "affiliate_product"
    product_id: str
    merchant_id: str | None = None
    placement: str | None = None
    campaign_id: str | None = None


class TryOnSkippedGarment(BaseModel):
    """A selected piece the plan deliberately left out, and why (spec Phase 7).

    Its existence is the contract: a look never silently loses a garment, so
    anything not rendered is named here with a reason the user can act on.
    """

    item_key: str
    reason: str  # needs_review | unsupported_category
    message: str
    canonical: str | None = None


class TryOnJobResponse(BaseModel):
    job_id: str
    status: str  # internal (legacy): queued | processing | done | failed
    # External contract (§4.5): queued | preparing | processing | ready | failed.
    # Auto-derived from `status` so old clients keep reading `status` unchanged.
    state: str = ""
    result_image_url: str | None = None
    error: str | None = None
    # Absent on every closet render, which is what an older client and an older
    # job both look like — so this is additive in both directions (§37.4).
    source: TryOnSource | None = None

    # ---- look accounting (additive; absent on pre-0069 jobs) ----
    #: Renderable steps in the plan, and how many have completed. Lets the
    #: generating screen say "piece 2 of 4" instead of an unqualified spinner.
    total_steps: int | None = None
    current_step: int | None = None
    #: Pieces whose provider step succeeded. On a done job this MUST cover every
    #: planned piece — the worker refuses to mark a partial look done.
    applied_item_keys: list[str] = Field(default_factory=list)
    #: Pieces excluded before rendering, each with a reason.
    skipped: list[TryOnSkippedGarment] = Field(default_factory=list)

    @model_validator(mode="after")
    def _derive_state(self) -> TryOnJobResponse:
        if not self.state:
            from app.core.status import external_status

            self.state = external_status(self.status)
        return self


class TryOnResultItem(BaseModel):
    """One saved try-on result for the history view. `result_image_url` is a
    short-lived signed URL minted from our private storage."""

    id: str
    result_image_url: str | None = None
    # The card-sized rendition (512px WebP) for the three-across history grid.
    # Null for a result stored before thumbnails were generated and not yet
    # backfilled, and for a legacy Supabase object — the grid then falls back to
    # the full render, which is what it always did.
    thumbnail_url: str | None = None
    created_at: datetime
    # Carried into history so a shopping render reopened days later still knows
    # what it was of.
    source: TryOnSource | None = None
