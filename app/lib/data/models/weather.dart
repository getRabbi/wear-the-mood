import 'package:freezed_annotation/freezed_annotation.dart';

part 'weather.freezed.dart';
part 'weather.g.dart';

/// Current + today's weather for a coordinate (CLAUDE.md §2), from
/// `GET /v1/weather/current`. Temperatures are Celsius (the provider's unit); the
/// UI converts to the viewer's regional unit for display.
@freezed
abstract class WeatherSnapshot with _$WeatherSnapshot {
  const factory WeatherSnapshot({
    required String condition, // human label, e.g. "Partly cloudy"
    @JsonKey(name: 'temp_c') required double tempC,
    @JsonKey(name: 'feels_like_c') double? feelsLikeC,
    @JsonKey(name: 'temp_min_c') double? tempMinC,
    @JsonKey(name: 'temp_max_c') double? tempMaxC,
    @JsonKey(name: 'precipitation_chance') int? precipitationChance, // 0–100
    int? humidity, // 0–100
    @JsonKey(name: 'wind_kph') double? windKph,
  }) = _WeatherSnapshot;

  const WeatherSnapshot._();

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      _$WeatherSnapshotFromJson(json);
}

/// A place resolved from a city-name search (`GET /v1/weather/geocode`) — the
/// manual-city fallback when device location is denied (§20).
@freezed
abstract class GeoPlace with _$GeoPlace {
  const factory GeoPlace({
    required String name,
    required double latitude,
    required double longitude,
    String? country,
    @JsonKey(name: 'country_code') String? countryCode,
    String? admin1, // state / region — disambiguates same-named cities
  }) = _GeoPlace;

  const GeoPlace._();

  factory GeoPlace.fromJson(Map<String, dynamic> json) =>
      _$GeoPlaceFromJson(json);

  /// A compact "City, Region" or "City, Country" label for the picker/chip.
  String get label {
    final parts = [name, if ((admin1 ?? '').isNotEmpty) admin1! else country];
    return parts.where((p) => (p ?? '').isNotEmpty).join(', ');
  }
}
