from functools import lru_cache

from app.core.config import get_settings
from app.services.weather.base import GeoLocation, WeatherProvider, WeatherSnapshot
from app.services.weather.stub import StubWeatherProvider

__all__ = [
    "GeoLocation",
    "WeatherProvider",
    "WeatherSnapshot",
    "get_weather_provider",
]


@lru_cache
def get_weather_provider() -> WeatherProvider:
    """Resolve the active weather provider (CLAUDE.md §2). Open-Meteo is free and
    keyless, so it is the default; WEATHER_PROVIDER=stub forces the offline,
    deterministic provider (dev/CI/tests, or when the network is unavailable)."""
    settings = get_settings()
    if settings.weather_provider.lower() == "stub":
        return StubWeatherProvider()
    from app.services.weather.open_meteo import OpenMeteoWeatherProvider

    return OpenMeteoWeatherProvider(
        base_url=settings.open_meteo_base_url,
        geocoding_base_url=settings.open_meteo_geocoding_base_url,
    )
