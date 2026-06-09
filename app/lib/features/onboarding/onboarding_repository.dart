import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists whether the user has finished onboarding (CLAUDE.md §17). Stored in
/// secure storage so it survives reinstall-less restarts; it's just a flag, not
/// a secret, but reuses the storage the app already depends on.
class OnboardingRepository {
  OnboardingRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'onboarding_complete';

  Future<bool> isComplete() async => (await _storage.read(key: _key)) == 'true';

  Future<void> markComplete() => _storage.write(key: _key, value: 'true');
}
