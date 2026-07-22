"""Open-Meteo weather provider (CLAUDE.md §2) — free, no API key required.

Fetches current conditions + today's high/low + rain chance for a coordinate,
to give the AI stylist weather context. Network/timeout/HTTP errors raise so the
caller (the stylist) can degrade gracefully and proceed without weather.
"""

from __future__ import annotations

import httpx

from app.services.weather.base import GeoLocation, WeatherProvider, WeatherSnapshot

# WMO weather interpretation codes (WW) → human labels.
# Reference: https://open-meteo.com/en/docs
_WMO_CODES: dict[int, str] = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    56: "Light freezing drizzle",
    57: "Dense freezing drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    66: "Light freezing rain",
    67: "Heavy freezing rain",
    71: "Slight snowfall",
    73: "Moderate snowfall",
    75: "Heavy snowfall",
    77: "Snow grains",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    85: "Slight snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with slight hail",
    99: "Thunderstorm with heavy hail",
}

_CURRENT_FIELDS = ",".join(
    [
        "temperature_2m",
        "apparent_temperature",
        "relative_humidity_2m",
        "weather_code",
        "wind_speed_10m",
    ]
)
_DAILY_FIELDS = ",".join(
    [
        "temperature_2m_max",
        "temperature_2m_min",
        "precipitation_probability_max",
    ]
)


def wmo_label(code: int | None) -> str:
    """Map a WMO weather code to a human label; 'Unknown' for unmapped/None."""
    if code is None:
        return "Unknown"
    return _WMO_CODES.get(int(code), "Unknown")


def _opt_float(value: object) -> float | None:
    return float(value) if value is not None else None  # type: ignore[arg-type]


def _opt_int(value: object) -> int | None:
    return int(value) if value is not None else None  # type: ignore[arg-type]


def _parse(data: dict) -> WeatherSnapshot:
    current = data.get("current") or {}
    daily = data.get("daily") or {}

    def _first(key: str) -> object:
        seq = daily.get(key) or []
        return seq[0] if seq else None

    return WeatherSnapshot(
        condition=wmo_label(current.get("weather_code")),
        temp_c=float(current.get("temperature_2m") or 0.0),
        feels_like_c=_opt_float(current.get("apparent_temperature")),
        temp_min_c=_opt_float(_first("temperature_2m_min")),
        temp_max_c=_opt_float(_first("temperature_2m_max")),
        precipitation_chance=_opt_int(_first("precipitation_probability_max")),
        humidity=_opt_int(current.get("relative_humidity_2m")),
        wind_kph=_opt_float(current.get("wind_speed_10m")),
    )


class OpenMeteoWeatherProvider(WeatherProvider):
    name = "open_meteo"

    def __init__(
        self,
        *,
        base_url: str = "https://api.open-meteo.com",
        geocoding_base_url: str = "https://geocoding-api.open-meteo.com",
        client: httpx.AsyncClient | None = None,
        timeout_s: float = 10.0,
    ) -> None:
        self._base = base_url.rstrip("/")
        self._geo_base = geocoding_base_url.rstrip("/")
        self._client = client
        self._timeout_s = timeout_s

    async def search(self, query: str, *, count: int = 5) -> list[GeoLocation]:
        query = query.strip()
        if not query:
            return []
        client = self._client or httpx.AsyncClient(timeout=self._timeout_s)
        owns_client = self._client is None
        try:
            resp = await client.get(
                f"{self._geo_base}/v1/search",
                params={"name": query, "count": count, "language": "en", "format": "json"},
            )
            resp.raise_for_status()
            results = (resp.json() or {}).get("results") or []
            return [
                GeoLocation(
                    name=str(r.get("name") or query),
                    latitude=float(r["latitude"]),
                    longitude=float(r["longitude"]),
                    country=r.get("country"),
                    country_code=r.get("country_code"),
                    admin1=r.get("admin1"),
                )
                for r in results
                if r.get("latitude") is not None and r.get("longitude") is not None
            ]
        finally:
            if owns_client:
                await client.aclose()

    async def current(self, *, latitude: float, longitude: float) -> WeatherSnapshot:
        client = self._client or httpx.AsyncClient(timeout=self._timeout_s)
        owns_client = self._client is None
        try:
            resp = await client.get(
                f"{self._base}/v1/forecast",
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "current": _CURRENT_FIELDS,
                    "daily": _DAILY_FIELDS,
                    "timezone": "auto",
                    "forecast_days": 1,
                    "wind_speed_unit": "kmh",
                },
            )
            resp.raise_for_status()
            return _parse(resp.json())
        finally:
            if owns_client:
                await client.aclose()
