"""Weather service — stub + Open-Meteo (mocked HTTP, no network, no key)."""

from __future__ import annotations

import asyncio

import httpx
import pytest

from app.core.config import get_settings
from app.services.weather import get_weather_provider
from app.services.weather.open_meteo import OpenMeteoWeatherProvider, wmo_label
from app.services.weather.stub import StubWeatherProvider


@pytest.fixture(autouse=True)
def _clear_cache():
    get_weather_provider.cache_clear()
    get_settings.cache_clear()
    yield
    get_weather_provider.cache_clear()
    get_settings.cache_clear()


_FORECAST = {
    "current": {
        "temperature_2m": 28.5,
        "apparent_temperature": 31.2,
        "relative_humidity_2m": 70,
        "weather_code": 2,
        "wind_speed_10m": 12.0,
    },
    "daily": {
        "temperature_2m_max": [31.0],
        "temperature_2m_min": [25.0],
        "precipitation_probability_max": [40],
    },
}


def _provider(handler) -> OpenMeteoWeatherProvider:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OpenMeteoWeatherProvider(client=client)


def test_open_meteo_parses_forecast() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/forecast"
        assert request.url.params["latitude"] == "23.78"
        return httpx.Response(200, json=_FORECAST)

    snap = asyncio.run(_provider(handler).current(latitude=23.78, longitude=90.41))
    assert snap.condition == "Partly cloudy"
    assert snap.temp_c == 28.5
    assert snap.feels_like_c == 31.2
    assert snap.temp_min_c == 25.0
    assert snap.temp_max_c == 31.0
    assert snap.precipitation_chance == 40
    assert snap.humidity == 70
    assert snap.wind_kph == 12.0


def test_open_meteo_tolerates_missing_daily() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"current": {"temperature_2m": 20.0, "weather_code": 0}})

    snap = asyncio.run(_provider(handler).current(latitude=0, longitude=0))
    assert snap.temp_c == 20.0
    assert snap.condition == "Clear sky"
    assert snap.temp_max_c is None
    assert snap.precipitation_chance is None


def test_open_meteo_raises_on_http_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": True})

    with pytest.raises(httpx.HTTPStatusError):
        asyncio.run(_provider(handler).current(latitude=0, longitude=0))


def test_wmo_label_maps_known_unknown_and_none() -> None:
    assert wmo_label(0) == "Clear sky"
    assert wmo_label(95) == "Thunderstorm"
    assert wmo_label(123) == "Unknown"
    assert wmo_label(None) == "Unknown"


def test_stub_is_deterministic_and_offline() -> None:
    snap = asyncio.run(StubWeatherProvider().current(latitude=1, longitude=2))
    assert snap.condition == "Partly cloudy"
    assert snap.temp_c == 24.0


def test_summary_reads_naturally() -> None:
    snap = asyncio.run(StubWeatherProvider().current(latitude=0, longitude=0))
    text = snap.summary()
    assert "Partly cloudy" in text
    assert "°C" in text
    assert "rain" in text


# ── routing ──────────────────────────────────────────────────────────────────


def test_defaults_to_open_meteo(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("WEATHER_PROVIDER", raising=False)
    get_settings.cache_clear()
    get_weather_provider.cache_clear()
    assert get_weather_provider().name == "open_meteo"


def test_routes_to_stub_when_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("WEATHER_PROVIDER", "stub")
    get_settings.cache_clear()
    get_weather_provider.cache_clear()
    assert get_weather_provider().name == "stub"
