"""TryOnProvider interface (CLAUDE.md §2.1, §2.2).

All try-on generation goes through this interface — never call a vendor SDK from
a router or widget. The concrete provider is chosen by env in get_tryon_provider
(FASHN.ai at launch; self-hosted Leffa later). Implementations must retry/timeout
and surface a clean error so the worker can mark the job failed without charging.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


class TryOnError(RuntimeError):
    """Base for try-on provider failures. Subclasses RuntimeError so existing
    ``except RuntimeError`` paths keep working."""


class TryOnInputError(TryOnError):
    """Permanent, user-actionable failure (bad pose, NSFW, unusable image). Carries
    a clean, user-facing message; retrying will NOT help, so the worker fails the
    job immediately with this message (CLAUDE.md §13)."""


class TryOnTransientError(TryOnError):
    """Temporary failure (network blip, provider 5xx/overload/timeout, empty or
    generic terminal failure). Safe to retry with backoff (CLAUDE.md §7) — these
    are the intermittent "works on retry" failures."""


class TryOnCapacityError(TryOnTransientError):
    """The provider refused the request outright — HTTP 429: rate limit or the
    provider account is OUT OF API CREDITS. Retried like any transient failure
    (a rate-limit burst can clear), but when retries exhaust the worker stores a
    capacity-specific user message instead of the generic one, so an empty FASHN
    balance surfaces as "studio unavailable", not a mystery glitch (§13/§14)."""


@dataclass(frozen=True)
class RenderResult:
    """One completed provider step.

    Carries the provider's own prediction id alongside the image so a step can be
    traced back to the run that produced it (§24). Without it, a job id gets you
    as far as "step 3 failed" and no further — the correlation to the provider's
    side of the call lived only in a log line, which is not evidence once it has
    aged out of retention.
    """

    image_url: str
    #: The provider's run/prediction id. None for providers that have no concept
    #: of one (the stub), never a secret and never a signed URL.
    prediction_id: str | None = None


@dataclass(frozen=True)
class RenderRequest:
    """ONE provider call, fully resolved by the planner (§7, spec Phase 3/6).

    Carries the DECISION, not a hint: `model_name`, `category` and `prompt` are
    already chosen from Wear The Mood's canonical taxonomy, so a provider
    implementation only has to submit them. Nothing here asks the provider to
    work out what the garment is — that is exactly the failure mode this type
    exists to make impossible.
    """

    person_image: str
    """The body for THIS step: inline base64 for the first step, and the previous
    step's output URL for every step after it (the chain)."""

    garment_image: str
    model_name: str
    #: Apparel model only — one of the provider's explicit region categories.
    category: str | None = None
    #: Accessory model only — the provider-supported preservation instruction.
    prompt: str | None = None
    #: Apparel model only — `auto` unless we genuinely know the photo's kind.
    garment_photo_type: str = "auto"
    #: Last step of the look. Only the final image is kept, so intermediates can
    #: be rendered in whatever format chains fastest.
    is_final: bool = False


class TryOnProvider(ABC):
    name: str

    @abstractmethod
    async def render(self, request: RenderRequest) -> RenderResult:
        """Run ONE fully-specified step and return its result, or raise.

        The interface stays single-step because no provider we can use renders a
        whole look at once: FASHN's `tryon-max` explicitly rejects a
        `product_images` array (verified 2026-08-15), and `tryon-v1.6` takes one
        `garment_image`. MULTI-GARMENT looks are therefore composed by CHAINING —
        each render's output becomes the next render's person image, in the order
        the planner fixed (one-piece/bottom/top → outerwear → accessories). See
        ``app.services.tryon.planner`` and ``app.workers.tryon_worker``. A provider
        that ever does accept a bundle overrides this method and nothing else.
        """
        raise NotImplementedError

    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        """Legacy single-garment convenience wrapper.

        Kept so existing callers and tests keep compiling; it takes the provider's
        own detection because it has nothing better to go on. Nothing in the
        production path uses it — the worker builds a `RenderRequest` from the
        stored plan.
        """
        result = await self.render(
            RenderRequest(
                person_image=person_image_url,
                garment_image=garment_image_url,
                model_name="",
                category="auto",
                is_final=True,
            )
        )
        return result.image_url
