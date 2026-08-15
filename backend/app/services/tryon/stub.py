from __future__ import annotations

from app.services.tryon.base import RenderRequest, RenderResult, TryOnProvider


class StubTryOnProvider(TryOnProvider):
    """Placeholder provider used until FASHN.ai is wired (CLAUDE.md §2.2). Echoes
    the person image back as the 'result' so the job lifecycle can be exercised
    end-to-end without a paid API.

    It echoes the PERSON image rather than the garment on purpose: chaining a
    look through the stub then produces the original body photo, which is the
    only honest stand-in for "nothing was rendered"."""

    name = "stub"

    async def render(self, request: RenderRequest) -> RenderResult:
        return RenderResult(request.person_image)
