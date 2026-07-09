"""TryOnProvider interface (CLAUDE.md §2.1, §2.2).

All try-on generation goes through this interface — never call a vendor SDK from
a router or widget. The concrete provider is chosen by env in get_tryon_provider
(FASHN.ai at launch; self-hosted Leffa later). Implementations must retry/timeout
and surface a clean error so the worker can mark the job failed without charging.
"""

from __future__ import annotations

from abc import ABC, abstractmethod


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


class TryOnProvider(ABC):
    name: str

    @abstractmethod
    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        """Return the URL of the generated try-on image for ONE garment, or raise
        on failure.

        The interface stays single-garment because our provider (FASHN) applies
        one garment per call. MULTI-GARMENT looks are composed in the worker by
        CHAINING this method — each render's output becomes the next render's
        person image, in the client-provided render order (dress/base → top →
        bottom → outerwear → shoes/bag/accessory). See
        ``app.workers.tryon_worker.process_job``. A provider that natively accepts
        a bundle could override this strategy later.
        """
        raise NotImplementedError
