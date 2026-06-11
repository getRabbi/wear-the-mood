"""WeatherProvider interface (CLAUDE.md §2) — weather context for the AI stylist.

The stylist needs "is it cold / will it rain today?" to pick an outfit. All
weather access goes through this interface; the concrete provider is chosen by
env in get_weather_provider. Open-Meteo is free and needs no key (§2); the stub
keeps the stylist runnable offline and in tests. Callers must treat weather as
enriching context, never a hard dependency — degrade gracefully if it fails.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from pydantic import BaseModel


class WeatherSnapshot(BaseModel):
    """A compact, stylist-ready view of the weather at a place + today."""

    condition: str  # human label, e.g. "Partly cloudy"
    temp_c: float  # current temperature
    feels_like_c: float | None = None
    temp_min_c: float | None = None  # today's low
    temp_max_c: float | None = None  # today's high
    precipitation_chance: int | None = None  # 0–100, today's max
    humidity: int | None = None  # 0–100
    wind_kph: float | None = None

    def summary(self) -> str:
        """One-line natural-language summary, suitable for an LLM prompt."""
        parts = [f"{self.condition}, {round(self.temp_c)}°C"]
        if self.temp_min_c is not None and self.temp_max_c is not None:
            parts.append(f"low {round(self.temp_min_c)}–high {round(self.temp_max_c)}°C")
        if self.precipitation_chance is not None:
            parts.append(f"{self.precipitation_chance}% chance of rain")
        return ", ".join(parts)


class WeatherProvider(ABC):
    name: str

    @abstractmethod
    async def current(self, *, latitude: float, longitude: float) -> WeatherSnapshot:
        """Return current + today's weather for a coordinate, or raise on failure."""
        raise NotImplementedError
