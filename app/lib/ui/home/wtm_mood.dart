import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Today's-mood persistence (UI_IMPLEMENTATION.md §3.1: "mood slider persists
/// to profile and re-seeds Today's Look + AI Stylist context").
///
/// P2 persists the value on-device (secure storage, like onboarding state)
/// and exposes it app-wide; Today's Look re-seeds from it immediately and the
/// Stylist reads the same provider. Server-side profile sync rides with the
/// stylist-context wiring in P5 — the backend is untouched here (§0.1).
class WtmMoodRepository {
  const WtmMoodRepository(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'wtm_mood_v1';

  Future<double?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      final value = raw == null ? null : double.tryParse(raw);
      return value?.clamp(0.0, 1.0);
    } catch (e) {
      // Storage unavailable (fresh install edge cases, tests) — board default.
      debugPrint('WtmMoodRepository.read failed: $e');
      return null;
    }
  }

  Future<void> write(double value) async {
    try {
      await _storage.write(key: _key, value: value.toStringAsFixed(4));
    } catch (e) {
      debugPrint('WtmMoodRepository.write failed: $e');
    }
  }
}

final wtmMoodRepositoryProvider = Provider<WtmMoodRepository>((ref) {
  return const WtmMoodRepository(FlutterSecureStorage());
});

/// The mood value, 0 (Calm) → 1 (Rebel). Seeds at the board's resting 0.36
/// (Confident) until the persisted value loads.
final wtmMoodProvider = NotifierProvider<WtmMoodNotifier, double>(
  WtmMoodNotifier.new,
);

class WtmMoodNotifier extends Notifier<double> {
  /// Board knob resting position (36% — Confident).
  static const defaultMood = 0.36;

  @override
  double build() {
    _restore();
    return defaultMood;
  }

  Future<void> _restore() async {
    final saved = await ref.read(wtmMoodRepositoryProvider).read();
    if (saved != null) state = saved;
  }

  /// Live drag — updates listeners without touching storage.
  void preview(double value) => state = value.clamp(0.0, 1.0);

  /// Drag released — persist.
  Future<void> commit(double value) {
    state = value.clamp(0.0, 1.0);
    return ref.read(wtmMoodRepositoryProvider).write(state);
  }
}

/// The four mood zones (board labels under the slider).
enum WtmMoodZone {
  calm,
  confident,
  bold,
  rebel;

  static WtmMoodZone of(double value) => switch (value) {
        < 0.25 => calm,
        < 0.5 => confident,
        < 0.75 => bold,
        _ => rebel,
      };
}
