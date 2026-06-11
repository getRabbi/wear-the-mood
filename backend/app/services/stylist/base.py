"""StylistProvider interface (CLAUDE.md §2.1) — the daily "what do I wear?" habit.

The stylist picks an outfit from the user's OWN wardrobe given today's weather and
any occasion/note. All LLM calls go through this interface (never a vendor SDK in
a router). Claude Sonnet is the primary provider (§2.1); the stub keeps the loop
runnable with no key, and also backs the router's graceful fallback when the LLM
fails. Token usage rides back on the result for cost logging (§14).
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from pydantic import BaseModel, Field

from app.services.weather import WeatherSnapshot


class WardrobeBrief(BaseModel):
    """A compact view of one owned item — what the stylist reasons over."""

    id: str
    title: str | None = None
    category: str | None = None
    subcategory: str | None = None
    color: str | None = None
    pattern: str | None = None
    tags: list[str] = Field(default_factory=list)

    def label(self) -> str:
        """One human line for an LLM prompt, prefixed with the item id."""
        bits = [self.color, self.pattern, self.subcategory or self.title]
        desc = " ".join(b for b in bits if b) or "item"
        line = f"[{self.id}] {desc}"
        if self.category:
            line += f" ({self.category})"
        if self.tags:
            line += f" — {', '.join(self.tags[:5])}"
        return line


class StylistContext(BaseModel):
    occasion: str | None = None
    note: str | None = None


class StylistSuggestion(BaseModel):
    """The stylist's pick: item ids from the wardrobe + a short why."""

    item_ids: list[str] = Field(default_factory=list)
    title: str = "Today's look"
    rationale: str = ""
    input_tokens: int | None = None
    output_tokens: int | None = None


class StylistProvider(ABC):
    name: str

    @abstractmethod
    async def suggest(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: StylistContext,
    ) -> StylistSuggestion:
        """Choose an outfit from [wardrobe], or raise on failure."""
        raise NotImplementedError
