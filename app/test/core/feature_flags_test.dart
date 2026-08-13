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

  // ---- Discover defaults ON until the backend says otherwise ----
  // Discover is the design, not a staged rollout: with the ordinary OFF
  // default, every cold launch drew tab 1 as Social and swapped it once the
  // flags request landed. These four pin BOTH halves of the contract — the
  // optimistic default, and the kill-switch that must still be able to beat it.

  group('Discover defaults on until the backend answers', () {
    test('Discover is ON while the flags request is still in flight', () {
      final c = _container(_FakeFlagsRepo(const {}));
      // No await — deliberately reading during AsyncLoading.
      expect(c.read(featureEnabledProvider(FeatureFlags.discover)), isTrue);
      expect(
        c.read(featureEnabledProvider(FeatureFlags.discoverStories)),
        isTrue,
      );
    });

    test('Discover is ON when the flags request fails', () async {
      final c = _container(_FakeFlagsRepo(const {}, fail: true));
      final sub = c.listen(enabledFeatureFlagsProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(enabledFeatureFlagsProvider).hasError, isTrue);
      expect(c.read(featureEnabledProvider(FeatureFlags.discover)), isTrue);
    });

    test(
      'a definitive answer WITHOUT Discover turns it off (kill-switch)',
      () async {
        final c = _container(_FakeFlagsRepo({FeatureFlags.postEdit}));
        await c.read(enabledFeatureFlagsProvider.future);

        // The backend has answered and did not list Discover. That is ops pulling
        // the lever, and it has to beat the optimistic default — otherwise the
        // rollback documented in DISCOVER §30 would not exist.
        expect(c.read(featureEnabledProvider(FeatureFlags.discover)), isFalse);
        expect(
          c.read(featureEnabledProvider(FeatureFlags.discoverStories)),
          isFalse,
        );
      },
    );

    test('a definitive answer WITH Discover keeps it on', () async {
      final c = _container(_FakeFlagsRepo({FeatureFlags.discover}));
      await c.read(enabledFeatureFlagsProvider.future);

      expect(c.read(featureEnabledProvider(FeatureFlags.discover)), isTrue);
      // Not listed, and the backend has answered — so off, even though it
      // shares the optimistic default with `discover`.
      expect(
        c.read(featureEnabledProvider(FeatureFlags.discoverStories)),
        isFalse,
      );
    });
  });
}
