"""Monetization config API models (spec §39).

The snapshot the app fetches so an experiment number can change without a
binary release. Everything here is DESCRIPTIVE — the server still enforces every
cost, gate and entitlement itself (§11). A client that ignored this response
entirely would get the same charges and the same refusals; it would just show
worse copy.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class RenderCosts(BaseModel):
    """App credits per render quality. Mirrors what the server WILL charge."""

    standard: int
    hd: int
    enhance: int


class PlanPresentation(BaseModel):
    """One purchasable plan as the server describes it.

    `price_usd` is the catalog price for reference and reconciliation ONLY. The
    app must display the STORE's localized price string (§7.2) — never this
    number — because the store is the authority on what the user actually pays.
    """

    tier: str
    kind: str
    price_usd: float
    monthly_credits: int
    hd_allowed: bool
    priority: bool
    play_product_id: str | None = None
    app_product_id: str | None = None


class PaywallPolicy(BaseModel):
    """When WTM is allowed to interrupt (§10)."""

    cooldown_hours: int
    post_purchase_cooldown_hours: int
    timing_variant: str
    #: False when a cooldown is currently in force. A surface the user opens
    #: themselves ignores this entirely.
    may_interrupt: bool = True
    block_reason: str | None = None
    retry_after_hours: int | None = None


class MonetizationConfig(BaseModel):
    """The whole policy snapshot for the calling user."""

    #: Bumped when the shape changes so an old client can tell.
    version: int = 1
    render_costs: RenderCosts
    #: Lifetime free standard renders for this user, as the server will enforce.
    free_render_limit: int
    free_render_remaining: int
    tier: str
    hd_allowed: bool
    plans: list[PlanPresentation] = Field(default_factory=list)
    paywall: PaywallPolicy
    trial_enabled: bool = False
    trial_credit_cap: int | None = None
    rollover_enabled: bool = False
    #: {experiment: variant}. Empty for everyone not in an experiment.
    experiments: dict[str, str] = Field(default_factory=dict)
    #: Which v2 surfaces are live for this user, so the app does not need a
    #: second round-trip to /v1/flags to compose a paywall.
    paywall_v2: bool = False
    render_gate_v2: bool = False


class MonetizationEventIn(BaseModel):
    """A monetization surface was shown, dismissed, acted on, or converted."""

    surface: str = Field(max_length=40)
    action: str = Field(pattern="^(viewed|dismissed|cta_tapped|purchased)$")
    #: True ONLY when WTM raised this surface on its own. A user-initiated
    #: paywall must send false, or it would start a cooldown against itself.
    interruptive: bool = False
    context: dict[str, str] | None = None
