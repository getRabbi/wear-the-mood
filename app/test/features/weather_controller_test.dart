import 'package:app/data/models/weather.dart';
import 'package:app/data/repositories/weather_repository.dart';
import 'package:app/features/stylist/location_service.dart';
import 'package:app/features/stylist/weather_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake device location — scripted outcome, no geolocator/platform channels.
class _FakeLocation extends LocationService {
  const _FakeLocation(this._result);
  final LocationResult _result;
  @override
  Future<LocationResult> passiveFix() async => _result;
  @override
  Future<LocationResult> requestFix() async => _result;
}

/// Fake weather backend — a scripted snapshot, or throws to simulate an outage.
class _FakeWeatherRepo extends WeatherRepository {
  _FakeWeatherRepo({this.snapshot, this.fail = false}) : super(Dio());
  final WeatherSnapshot? snapshot;
  final bool fail;
  int currentCalls = 0;
  ({double lat, double lon})? lastCoords;

  @override
  Future<WeatherSnapshot> current({
    required double latitude,
    required double longitude,
  }) async {
    currentCalls++;
    lastCoords = (lat: latitude, lon: longitude);
    if (fail || snapshot == null) throw Exception('provider down');
    return snapshot!;
  }
}

/// In-memory saved-city store — no secure-storage plugin in tests.
class _FakePrefs extends WeatherPrefs {
  _FakePrefs([this.saved]) : super(const FlutterSecureStorage());
  GeoPlace? saved;
  @override
  Future<GeoPlace?> city() async => saved;
  @override
  Future<void> saveCity(GeoPlace place) async => saved = place;
  @override
  Future<void> clearCity() async => saved = null;
}

const _snap = WeatherSnapshot(condition: 'Clear sky', tempC: 30.0, feelsLikeC: 33.0);

ProviderContainer _container({
  required LocationResult location,
  _FakeWeatherRepo? repo,
  _FakePrefs? prefs,
}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(_FakeLocation(location)),
      weatherRepositoryProvider.overrideWithValue(
        repo ?? _FakeWeatherRepo(snapshot: _snap),
      ),
      weatherPrefsProvider.overrideWithValue(prefs ?? _FakePrefs()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const granted = LocationResult(
    LocationOutcome.granted,
    latitude: 23.8,
    longitude: 90.4,
  );
  const denied = LocationResult(LocationOutcome.denied);

  test('device location granted → ready with the fetched reading', () async {
    final repo = _FakeWeatherRepo(snapshot: _snap);
    final c = _container(location: granted, repo: repo);
    await c.read(weatherControllerProvider.notifier).refresh();
    final state = c.read(weatherControllerProvider);
    expect(state, isA<WeatherReady>());
    expect((state as WeatherReady).info.snapshot.tempC, 30.0);
    expect(state.info.cityLabel, isNull); // device → "current location"
    expect(repo.lastCoords, (lat: 23.8, lon: 90.4));
  });

  test('denied + no saved city → needs-location (never fake weather)', () async {
    final c = _container(location: denied);
    await c.read(weatherControllerProvider.notifier).refresh();
    expect(c.read(weatherControllerProvider), isA<WeatherNeedsLocation>());
  });

  test('denied + saved city → ready from the saved city', () async {
    const city = GeoPlace(
      name: 'Dhaka',
      latitude: 23.7,
      longitude: 90.4,
      country: 'Bangladesh',
    );
    final c = _container(location: denied, prefs: _FakePrefs(city));
    await c.read(weatherControllerProvider.notifier).refresh();
    final state = c.read(weatherControllerProvider);
    expect(state, isA<WeatherReady>());
    expect((state as WeatherReady).info.cityLabel, contains('Dhaka'));
  });

  test('provider outage with no prior reading → unavailable', () async {
    final c = _container(location: granted, repo: _FakeWeatherRepo(fail: true));
    await c.read(weatherControllerProvider.notifier).refresh();
    expect(c.read(weatherControllerProvider), isA<WeatherUnavailable>());
  });

  test('setCity persists + resolves to that city', () async {
    final prefs = _FakePrefs();
    final c = _container(location: denied, prefs: prefs);
    const paris = GeoPlace(name: 'Paris', latitude: 48.85, longitude: 2.35);
    await c.read(weatherControllerProvider.notifier).setCity(paris);
    expect(c.read(weatherControllerProvider), isA<WeatherReady>());
    expect(prefs.saved?.name, 'Paris');
  });

  test('coordsForStylist returns the shown reading coordinates', () async {
    final c = _container(location: granted);
    await c.read(weatherControllerProvider.notifier).refresh();
    final coords =
        await c.read(weatherControllerProvider.notifier).coordsForStylist();
    expect(coords, isNotNull);
    expect(coords!.latitude, 23.8);
  });

  test('coordsForStylist is null when weather cannot be resolved', () async {
    final c = _container(location: denied);
    await c.read(weatherControllerProvider.notifier).refresh();
    expect(
      await c.read(weatherControllerProvider.notifier).coordsForStylist(),
      isNull,
    );
  });

  test('formatTemp respects the region unit', () {
    expect(formatTemp(30.0), '30°C');
    expect(formatTemp(30.0, countryCode: 'BD'), '30°C');
    expect(formatTemp(30.0, countryCode: 'US'), '86°F');
  });
}
