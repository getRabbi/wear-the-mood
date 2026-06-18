import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/flags/feature_flags.dart';
import 'package:app/data/repositories/feature_flags_repository.dart';

/// A fake that returns a fixed enabled-set (or throws) without any network.
class _FakeFlagsRepo implements FeatureFlagsRepository {
  _FakeFlagsRepo(this._enabled, {this.fail = false});

  final Set<String> _enabled;
  final bool fail;

  @override
  Future<Set<String>> getEnabled() async {
    if (fail) throw Exception('network');
    return _enabled;
  }
}

ProviderContainer _container(FeatureFlagsRepository repo) {
  final c = ProviderContainer(
    overrides: [featureFlagsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('an enabled flag reads true; unknown flags read false', () async {
    final c = _container(_FakeFlagsRepo({FeatureFlags.postEdit}));
    await c.read(enabledFeatureFlagsProvider.future);

    expect(c.read(featureEnabledProvider(FeatureFlags.postEdit)), isTrue);
    expect(c.read(featureEnabledProvider(FeatureFlags.giveaway)), isFalse);
  });

  test('flags are OFF while still loading (off by default)', () {
    final c = _container(_FakeFlagsRepo({FeatureFlags.postEdit}));
    // No await — the future hasn't resolved yet.
    expect(c.read(featureEnabledProvider(FeatureFlags.postEdit)), isFalse);
  });

  test('flags are OFF when the backend call fails', () async {
    final c = _container(_FakeFlagsRepo(const {}, fail: true));
    // Keep the provider alive and let the failing async settle into AsyncError.
    final sub = c.listen(enabledFeatureFlagsProvider, (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(enabledFeatureFlagsProvider).hasError, isTrue);
    expect(c.read(featureEnabledProvider(FeatureFlags.postEdit)), isFalse);
  });
}
