import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location lookup didn't yield coordinates — lets the UI show the right
/// state (grant permission vs. open Settings vs. pick a city).
enum LocationOutcome { granted, denied, deniedForever, serviceOff, error }

/// A single coarse location fix + why it did/didn't succeed.
class LocationResult {
  const LocationResult(this.outcome, {this.latitude, this.longitude});

  final LocationOutcome outcome;
  final double? latitude;
  final double? longitude;

  bool get hasCoords => latitude != null && longitude != null;
}

/// One-shot COARSE device location for the stylist's weather (CLAUDE.md §2, §20).
/// Never continuous tracking; only the minimum precision needed. Permission is
/// requested only when the caller explicitly asks (contextual, §20) — the passive
/// path uses an already-granted permission or falls back to a saved city.
class LocationService {
  const LocationService();

  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.low, // city-level is plenty for weather
    timeLimit: Duration(seconds: 12),
  );

  /// A coarse fix WITHOUT prompting — for the background resolve. Returns coords
  /// only when location permission is already granted and the service is on;
  /// otherwise reports why (so the UI can offer the right next step).
  Future<LocationResult> passiveFix() => _fix(request: false);

  /// A coarse fix, requesting permission if needed — for the explicit
  /// "Use my location" action (contextual permission, §20).
  Future<LocationResult> requestFix() => _fix(request: true);

  /// Open the OS location (GPS) settings — when the device service is off.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Open this app's settings — when permission is permanently denied.
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<LocationResult> _fix({required bool request}) async {
    try {
      // Ask for PERMISSION first: the OS permission dialog shows even when the
      // location service (GPS) is off, so an explicit "Use my location" tap always
      // does something visible. Only after permission do we require the service on.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && request) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(LocationOutcome.denied);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceOff);
      }
      // Granted + service on. Prefer a fresh fix; fall back to the last known
      // position if a fresh one times out (no continuous listening).
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _settings,
        );
        return LocationResult(
          LocationOutcome.granted,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationResult(
            LocationOutcome.granted,
            latitude: last.latitude,
            longitude: last.longitude,
          );
        }
        return const LocationResult(LocationOutcome.error);
      }
    } catch (_) {
      return const LocationResult(LocationOutcome.error);
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);
