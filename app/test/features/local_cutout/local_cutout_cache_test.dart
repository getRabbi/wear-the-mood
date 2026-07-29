import 'package:app/features/wardrobe/local_cutout/local_cutout_cache.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_cutout_fakes.dart';

/// Temp-file ownership via the operation-ID contract (local BG §4, §8.4; R10b).
///
/// The property under test is as much about what Dart CANNOT do as what it can:
/// there is no code path here that deletes a filesystem path, so a hostile or
/// malformed value arriving over the channel has nothing to act on. Dart sends an
/// identifier; native validates it and resolves it inside its own cache root.
void main() {
  group('disposeOperation', () {
    test('asks the platform to clean up by operation id', () async {
      final platform = FakeLocalCutoutPlatform();
      final cache = LocalCutoutCache(platform);

      expect(await cache.disposeOperation('a1b2c3'), isTrue);
      expect(platform.cleaned, ['a1b2c3']);
    });

    test('is idempotent — cleaning twice is still a success', () async {
      final platform = FakeLocalCutoutPlatform();
      final cache = LocalCutoutCache(platform);

      expect(await cache.disposeOperation('op'), isTrue);
      expect(await cache.disposeOperation('op'), isTrue);
      expect(platform.cleaned, ['op', 'op']);
    });

    test('null and blank ids are no-ops that never reach the platform', () async {
      final platform = FakeLocalCutoutPlatform();
      final cache = LocalCutoutCache(platform);

      expect(await cache.disposeOperation(null), isFalse);
      expect(await cache.disposeOperation(''), isFalse);
      expect(await cache.disposeOperation('   '), isFalse);
      expect(platform.cleaned, isEmpty);
    });

    test('a platform failure is swallowed, not thrown', () async {
      // Cleanup runs on teardown paths — dispose, cancel, error handling — where
      // an exception would replace a graceful fallback with a crash.
      final platform = FakeLocalCutoutPlatform()..cleanupThrows = true;
      final cache = LocalCutoutCache(platform);

      expect(await cache.disposeOperation('op'), isFalse);
    });

    test('the id is passed through verbatim — Dart does not interpret it', () async {
      // Validation is native's job, against its own root. Dart neither sanitises
      // nor resolves, because Dart has no root to resolve against.
      final platform = FakeLocalCutoutPlatform();
      final cache = LocalCutoutCache(platform);

      await cache.disposeOperation('../../etc/passwd');
      expect(platform.cleaned.single, '../../etc/passwd');
    });
  });

  group('sweepStale', () {
    test('forwards the max age and returns the count', () async {
      final platform = FakeLocalCutoutPlatform()..sweepResult = 3;
      final cache = LocalCutoutCache(platform);

      expect(await cache.sweepStale(maxAge: const Duration(hours: 2)), 3);
      expect(platform.sweptMaxAge, const Duration(hours: 2));
    });

    test('defaults to the documented six hours', () async {
      final platform = FakeLocalCutoutPlatform();
      await LocalCutoutCache(platform).sweepStale();

      expect(LocalCutoutCache.defaultMaxAge, const Duration(hours: 6));
      expect(platform.sweptMaxAge, const Duration(hours: 6));
    });

    test('a platform failure sweeps zero rather than throwing', () async {
      final platform = FakeLocalCutoutPlatform()..sweepThrows = true;
      expect(await LocalCutoutCache(platform).sweepStale(), 0);
    });
  });

  group('the result contract exposes no deletable directory', () {
    test('a decoded result carries an operation id and two file paths only', () {
      final result = LocalCutoutResult.fromMap(<Object?, Object?>{
        'engine': 'google_mlkit',
        'engineVersion': '16.0.0-beta1',
        'operationId': 'a1b2c3',
        // Native may send extra keys; Dart must not grow a deletable path.
        'operationDirectory': '/cache/wtm-local-cutout/a1b2c3',
        'maskFilePath': '/cache/wtm-local-cutout/a1b2c3/mask.png',
        'cutoutFilePath': '/cache/wtm-local-cutout/a1b2c3/cutout.png',
        'latencyMs': 900,
        'metrics': <Object?, Object?>{
          'width': 1600,
          'height': 1200,
          'subjectCount': 1,
          'foregroundAreaRatio': 0.4,
          'borderForegroundRatio': 0.02,
          'uncertainPixelRatio': 0.06,
          'meanForegroundConfidence': 0.9,
        },
      })!;

      expect(result.operationId, 'a1b2c3');
      expect(result.maskFilePath, endsWith('mask.png'));
      expect(result.cutoutFilePath, endsWith('cutout.png'));
      // The cache API takes an id; there is no path-shaped entry point at all.
      expect(
        LocalCutoutCache(FakeLocalCutoutPlatform()).disposeOperation(result.operationId),
        isA<Future<bool>>(),
      );
    });
  });
}
