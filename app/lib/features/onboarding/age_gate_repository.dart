import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the mandatory 16+ age-gate confirmation (CLAUDE.md §10). Stores ONLY
/// a confirmation flag + timestamp + version — never a date of birth. Reuses the
/// secure storage the app already depends on; no backend.
class AgeGateRepository {
  AgeGateRepository(this._storage);

  final FlutterSecureStorage _storage;

  /// Bump if the minimum age or wording materially changes, to re-prompt users.
  static const currentVersion = '1';

  static const _acceptedKey = 'age_gate_accepted';
  static const _acceptedAtKey = 'age_gate_accepted_at';
  static const _versionKey = 'age_gate_version';

  /// Accepted only when the stored flag is true AND it was for the current
  /// version (a version bump re-prompts).
  Future<bool> isAccepted() async {
    final accepted = (await _storage.read(key: _acceptedKey)) == 'true';
    if (!accepted) return false;
    final version = await _storage.read(key: _versionKey);
    return version == currentVersion;
  }

  Future<void> markAccepted() async {
    await _storage.write(key: _acceptedKey, value: 'true');
    await _storage.write(
      key: _acceptedAtKey,
      value: DateTime.now().toUtc().toIso8601String(),
    );
    await _storage.write(key: _versionKey, value: currentVersion);
  }
}
