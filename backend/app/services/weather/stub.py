"""Stub weather provider — deterministic and offline.

Keeps the AI stylist runnable without network in dev/CI/tests. Returns a mild,
mostly-dry day so stub suggestions stay reasonable.
"""

from __future__ import annotations

from app.services.weather.base import GeoLocation, WeatherProvider, WeatherSnapshot


class StubWeatherProvider(WeatherProvider):
    name = "stub"

    async def current(self, *, latitude: float, longitude: float) -> WeatherSnapshot:
        return WeatherSnapshot(
            condition="Partly cloudy",
            temp_c=24.0,
            feels_like_c=24.0,
            temp_min_c=19.0,
            temp_max_c=28.0,
            precipitation_chance=10,
            humidity=55,
            wind_kph=8.0,
        )

    async def search(self, query: str, *, count: int = 5) -> list[GeoLocation]:
        # A single deterministic hit so the manual-city flow is runnable offline.
        return [
            GeoLocation(
                name=query.strip().title() or "Dhaka",
                latitude=23.78,
                longitude=90.41,
                country="Bangladesh",
                country_code="BD",
                admin1="Dhaka",
            )
        ]
