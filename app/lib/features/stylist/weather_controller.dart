import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/weather.dart';
import '../../data/repositories/weather_repository.dart';
import 'location_service.dart';

/// Persists the user's manually-chosen weather city (the fallback when device
/// location is denied, §20). Not sensitive, but reuses the app's secure store.
class WeatherPrefs {
  const WeatherPrefs(this._storage);

  final FlutterSecureStorage _storage;
  static const _cityKey = 'wtm_weather_city_v1';

  Future<void> saveCity(GeoPlace place) =>
      _storage.write(key: _cityKey, value: jsonEncode(place.toJson()));

  Future<void> clearCity() => _storage.delete(key: _cityKey);

  Future<GeoPlace?> city() async {
    try {
      final raw = await _storage.read(key: _cityKey);
      if (raw == null || raw.isEmpty) return null;
      return GeoPlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Missing plugin (tests) / corrupt value / read error → no saved city.
      return null;
    }
  }
}

final weatherPrefsProvider = Provider<WeatherPrefs>(
  (ref) => const WeatherPrefs(FlutterSecureStorage()),
);

/// A resolved weather reading + where/when it came from.
class WeatherInfo {
  const WeatherInfo({
    required this.snapshot,
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
    this.cityLabel,
  });

  final WeatherSnapshot snapshot;
  final double latitude;
  final double longitude;
  final DateTime fetchedAt;
  final String? cityLabel; // null → device "current location"
}

/// The stylist weather state — four honest states (never a fake reading):
/// loading, ready (a real snapshot), needs-location (no permission + no saved
/// city → prompt), unavailable (had a location but the provider failed/offline).
sealed class WeatherState {
  const WeatherState();
}

class WeatherLoading extends WeatherState {
  const WeatherLoading();
}

class WeatherReady extends WeatherState {
  const WeatherReady(this.info);
  final WeatherInfo info;
}

class WeatherNeedsLocation extends WeatherState {
  const WeatherNeedsLocation();
}

class WeatherUnavailable extends WeatherState {
  const WeatherUnavailable();
}

/// Resolves + caches the current weather for the AI stylist (CLAUDE.md §2).
/// Resolution order (§20): device location when already granted → saved city →
/// prompt. Cached ~20 min; refreshed on stylist open, expiry, manual refresh,
/// app resume when stale, and after a location change. Never continuous tracking.
class WeatherController extends Notifier<WeatherState> {
  static const _ttl = Duration(minutes: 20);

  WeatherInfo? _cached;
  Future<void>? _inflight;

  @override
  WeatherState build() {
    if (_cached != null && _isFresh(_cached!)) return WeatherReady(_cached!);
    Future.microtask(_resolve);
    return const WeatherLoading();
  }

  bool _isFresh(WeatherInfo info) =>
      DateTime.now().difference(info.fetchedAt) < _ttl;

  /// Set state only while the provider is still alive — a background resolve
  /// (kicked from build) can outlive the screen; setting state after disposal
  /// would throw. Guards every write that follows an async gap.
  void _set(WeatherState next) {
    if (ref.mounted) state = next;
  }

  /// Ensure a reasonably fresh reading (stylist open / app resume). No-op refetch
  /// when the cache is still fresh.
  Future<void> ensureFresh() async {
    if (_cached != null && _isFresh(_cached!)) {
      _set(WeatherReady(_cached!));
      return;
    }
    await _resolve();
  }

  /// Force a refetch (manual refresh / pull).
  Future<void> refresh() => _resolve(force: true);

  /// Explicit "Use my location" — requests permission (contextual, §20), then
  /// resolves from the device, overriding any saved city on success.
  Future<void> useDeviceLocation() async {
    state = const WeatherLoading();
    final fix = await ref.read(locationServiceProvider).requestFix();
    if (fix.hasCoords) {
      await ref.read(weatherPrefsProvider).clearCity();
      await _fetch(fix.latitude!, fix.longitude!, null);
    } else if (_cached != null) {
      _set(WeatherReady(_cached!));
    } else {
      _set(const WeatherNeedsLocation());
    }
  }

  /// Manual city choice (permission-denied fallback, §20).
  Future<void> setCity(GeoPlace place) async {
    state = const WeatherLoading();
    await ref.read(weatherPrefsProvider).saveCity(place);
    await _fetch(place.latitude, place.longitude, place.label);
  }

  Future<List<GeoPlace>> searchCity(String query) =>
      ref.read(weatherRepositoryProvider).search(query);

  Future<void> _resolve({bool force = false}) async {
    if (!force && _cached != null && _isFresh(_cached!)) {
      _set(WeatherReady(_cached!));
      return;
    }
    final existing = _inflight;
    if (existing != null) return existing;
    final work = _doResolve();
    _inflight = work;
    try {
      await work;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _doResolve() async {
    if (_cached == null) _set(const WeatherLoading());
    final prefs = ref.read(weatherPrefsProvider);
    // 1) device location, but ONLY if already granted (no prompt here — §20).
    final fix = await ref.read(locationServiceProvider).passiveFix();
    if (fix.hasCoords) {
      await _fetch(fix.latitude!, fix.longitude!, null);
      return;
    }
    // 2) saved city fallback.
    final city = await prefs.city();
    if (city != null) {
      await _fetch(city.latitude, city.longitude, city.label);
      return;
    }
    // 3) nothing to go on — prompt to enable location or pick a city.
    _set(_cached != null
        ? WeatherReady(_cached!)
        : const WeatherNeedsLocation());
  }

  Future<void> _fetch(double lat, double lon, String? label) async {
    try {
      final snap = await ref
          .read(weatherRepositoryProvider)
          .current(latitude: lat, longitude: lon);
      _cached = WeatherInfo(
        snapshot: snap,
        latitude: lat,
        longitude: lon,
        cityLabel: label,
        fetchedAt: DateTime.now(),
      );
      _set(WeatherReady(_cached!));
    } catch (_) {
      // Keep the last good reading if we have one; else an honest "unavailable".
      _set(_cached != null
          ? WeatherReady(_cached!)
          : const WeatherUnavailable());
    }
  }

  /// Coordinates for the stylist request, matching the SHOWN weather so the
  /// suggestion uses the same live reading (§2). Waits briefly for a first
  /// in-flight resolve; returns null quickly when weather can't be resolved (the
  /// stylist then proceeds without weather, exactly as before).
  Future<({double latitude, double longitude})?> coordsForStylist() async {
    if (_cached != null) {
      return (latitude: _cached!.latitude, longitude: _cached!.longitude);
    }
    final inflight = _inflight;
    if (inflight != null) {
      try {
        await inflight.timeout(const Duration(seconds: 4));
      } catch (_) {
        // Fall through — no coords available in time.
      }
    }
    if (_cached != null) {
      return (latitude: _cached!.latitude, longitude: _cached!.longitude);
    }
    return null;
  }
}

final weatherControllerProvider =
    NotifierProvider<WeatherController, WeatherState>(WeatherController.new);

/// Countries that use Fahrenheit — everywhere else displays Celsius.
const _fahrenheitCountries = {
  'US', 'LR', 'MM', 'BS', 'BZ', 'KY', 'FM', 'MH', 'PW',
};

/// Format a Celsius temperature for the viewer's region (°F where appropriate,
/// °C otherwise), rounded to a whole degree.
String formatTemp(double celsius, {String? countryCode}) {
  if (_fahrenheitCountries.contains(countryCode?.toUpperCase())) {
    return '${(celsius * 9 / 5 + 32).round()}°F';
  }
  return '${celsius.round()}°C';
}
