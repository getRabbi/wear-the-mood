"""Weather (CLAUDE.md §2) — real current conditions for the AI stylist UI.

Open-Meteo is free and keyless, so the provider key never touches the client
(§11); the app sends a coordinate (device location) or a city name (the manual
fallback when location permission is denied, §20) and the backend resolves it.
Weather is enriching context, never a hard dependency — a provider failure
returns a typed PROVIDER_ERROR so the app can show "weather unavailable" rather
than an invented value.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Query

from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.services.weather import GeoLocation, WeatherSnapshot, get_weather_provider

log = logging.getLogger("fashionos.weather")

router = APIRouter(tags=["weather"])


@router.get("/weather/current", response_model=WeatherSnapshot)
async def current_weather(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    _user: CurrentUser = Depends(get_current_user),
) -> WeatherSnapshot:
    """Current + today's weather for a coordinate. 503 (typed) on a provider/network
    failure so the client degrades to a real "unavailable" state (never fake weather)."""
    try:
        return await get_weather_provider().current(latitude=latitude, longitude=longitude)
    except Exception as exc:  # network / HTTP / parse — degrade, never 500
        log.warning("weather lookup failed (%s,%s): %s", latitude, longitude, exc)
        raise ApiError(
            ErrorCode.PROVIDER_ERROR,
            "Weather is unavailable right now.",
            503,
        ) from exc


@router.get("/weather/geocode", response_model=list[GeoLocation])
async def geocode_city(
    q: str = Query(..., min_length=1, max_length=120),
    _user: CurrentUser = Depends(get_current_user),
) -> list[GeoLocation]:
    """Resolve a city name to candidate coordinates (manual-city fallback, §20)."""
    try:
        return await get_weather_provider().search(q)
    except Exception as exc:
        log.warning("geocode failed for %r: %s", q, exc)
        raise ApiError(
            ErrorCode.PROVIDER_ERROR,
            "City search is unavailable right now.",
            503,
        ) from exc
