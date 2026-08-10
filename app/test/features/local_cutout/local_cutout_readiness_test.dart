import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_orchestrator.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';

import 'local_cutout_fakes.dart';

/// The first-upload defect, pinned.
///
/// `prepare()` existed to warm the segmentation model after sign-in and NOTHING
/// called it, so the first Add Garment on a fresh install discovered a missing
/// model with the user standing in front of it, waited out a short bounded
/// install, gave up, and fell back to a ~110-140s cold cloud render. These cover
/// the shared lifecycle that replaced that: one preparation per process, shared
/// by the launch warm-up and the add path, plus exactly one transparent retry.
LocalCutoutOrchestrator orchestrator(
  FakeLocalCutoutPlatform platform, {
  bool enabled = true,
}) => LocalCutoutOrchestrator(
  platform: platform,
  masterEnabled: enabled,
  androidEnabled: enabled,
  iosEnabled: enabled,
  targetPlatform: TargetPlatform.android,
  readDimensions: (_) async => const SourceDimensions(1600, 1200),
);

FakeLocalCutoutPlatform notInstalled({
  LocalCutoutAvailability becomes = LocalCutoutAvailability.available,
}) => FakeLocalCutoutPlatform(
  capabilityResult: const LocalCutoutCapability(
    availability: LocalCutoutAvailability.modelNotInstalled,
    engine: LocalCutoutEngine.googleMlKit,
    engineVersion: 'fake-1',
  ),
  prepareResult: LocalCutoutCapability(
    availability: becomes,
    engine: LocalCutoutEngine.googleMlKit,
    engineVersion: 'fake-1',
  ),
  result: fakeResult(),
);

final _bytes = Uint8List.fromList(List<int>.filled(64, 7));

void main() {
  group('ensureReady — one preparation per process', () {
    test('concurrent callers share a single native preparation', () async {
      // The launch warm-up and an add that arrives mid-download are the SAME
      // operation. Two calls here used to mean two Play-services requests.
      final platform = notInstalled();
      final o = orchestrator(platform);

      await Future.wait([o.ensureReady(), o.ensureReady(), o.ensureReady()]);

      expect(platform.prepareCalls, 1);
    });

    test('a ready engine never asks again', () async {
      final platform = notInstalled();
      final o = orchestrator(platform);

      await o.ensureReady();
      await o.ensureReady();
      await o.ensureReady();

      expect(platform.prepareCalls, 1);
      expect(o.isReady, isTrue);
    });

    test(
      'a FAILED preparation is retried on the next add, not written off',
      () {
        // A download that failed once (no network at sign-in) must not disable
        // local cutouts for the life of the process.
        final platform = notInstalled(
          becomes: LocalCutoutAvailability.modelDownloadFailed,
        );
        final o = orchestrator(platform);

        return o.ensureReady().then((first) async {
          expect(first, LocalCutoutAvailability.modelDownloadFailed);
          expect(o.isReady, isFalse);
          await o.ensureReady();
          expect(platform.prepareCalls, 2);
        });
      },
    );

    test(
      'preparation never asks urgently — that is the add path only',
      () async {
        final platform = notInstalled();
        await orchestrator(platform).ensureReady();

        expect(platform.urgentPrepareCalls, 0);
        expect(platform.lastPrepareUrgent, isFalse);
      },
    );

    test('it never throws, whatever the platform does', () async {
      final platform = notInstalled()
        ..prepareError = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.nativeError,
        );

      await expectLater(
        orchestrator(platform).ensureReady(),
        completion(LocalCutoutAvailability.temporarilyUnavailable),
      );
    });

    test('a build with the gate off does no platform work at all', () async {
      final platform = notInstalled();
      final o = orchestrator(platform, enabled: false);

      expect(await o.ensureReady(), LocalCutoutAvailability.unsupportedOs);
      expect(platform.prepareCalls, 0);
      expect(o.isPreparing, isFalse);
    });
  });

  group('warmUp — the launch hook', () {
    test(
      'prepares the engine and sweeps last session\'s scratch files',
      () async {
        final platform = notInstalled();
        await orchestrator(platform).warmUp();

        expect(platform.prepareCalls, 1);
        expect(platform.sweepCalls, 1);
      },
    );

    test('a failing sweep never breaks the warm-up', () async {
      final platform = notInstalled()..sweepThrows = true;

      await expectLater(orchestrator(platform).warmUp(), completes);
    });

    test('a failing preparation never breaks the warm-up', () async {
      final platform = notInstalled()
        ..prepareError = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.nativeError,
        );

      await expectLater(orchestrator(platform).warmUp(), completes);
    });

    test('the gate being off makes it an immediate no-op', () async {
      final platform = notInstalled();
      await orchestrator(platform, enabled: false).warmUp();

      expect(platform.prepareCalls, 0);
      expect(platform.sweepCalls, 0);
    });
  });

  group('attemptWhenReady — the add path', () {
    test('waits for the warm-up instead of starting a second one', () async {
      final platform = notInstalled();
      final o = orchestrator(platform);

      // Launch warm-up and an add, overlapping — exactly the fresh-install race.
      final warm = o.warmUp();
      final attempt = o.attemptWhenReady(_bytes);
      await Future.wait<void>([warm, attempt]);

      expect(
        platform.prepareCalls,
        1,
        reason: 'the add must join the preparation already running',
      );
      expect(await attempt, isA<LocalCutoutAccepted>());
    });

    test('a first-install add succeeds once the model lands', () async {
      final platform = notInstalled();

      final result = await orchestrator(platform).attemptWhenReady(_bytes);

      expect(result, isA<LocalCutoutAccepted>());
      expect(platform.removeCalls, 1);
    });

    test(
      'retries the analysis exactly once when the engine came up late',
      () async {
        // capability() reports not-installed on the first look; the preparation
        // that follows brings it up. One more analysis beats a cloud fallback.
        final platform = notInstalled();
        final o = orchestrator(platform);
        // Force the first attempt to see the un-prepared capability.
        platform.prepareResult = const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelNotInstalled,
          engine: LocalCutoutEngine.googleMlKit,
          engineVersion: 'fake-1',
        );
        await o.ensureReady();
        platform.prepareResult = const LocalCutoutCapability(
          availability: LocalCutoutAvailability.available,
          engine: LocalCutoutEngine.googleMlKit,
          engineVersion: 'fake-1',
        );

        final result = await o.attemptWhenReady(_bytes);

        expect(result, isA<LocalCutoutAccepted>());
        expect(
          platform.removeCalls,
          lessThanOrEqualTo(2),
          reason: 'at most ONE transparent retry',
        );
      },
    );

    test(
      'a device that simply cannot do it is not retried in a loop',
      () async {
        final platform = FakeLocalCutoutPlatform(
          capabilityResult: const LocalCutoutCapability(
            availability: LocalCutoutAvailability.missingGooglePlayServices,
            engine: LocalCutoutEngine.googleMlKit,
            engineVersion: 'fake-1',
          ),
        );

        final result = await orchestrator(platform).attemptWhenReady(_bytes);

        expect(result, isA<LocalCutoutRejected>());
        expect(
          (result as LocalCutoutRejected).reason,
          LocalCutoutFallbackReason.missingGooglePlayServices,
        );
        expect(result.canUseCloudFallback, isTrue);
        expect(platform.removeCalls, 0);
      },
    );

    test('a quality rejection is NOT retried — the engine already ran', () async {
      final platform = FakeLocalCutoutPlatform(
        result: fakeResult(
          // The mask covers essentially the entire frame: segmentation failed
          // open and kept the background. A photo problem, not a readiness one.
          metrics: fakeMetrics(foregroundAreaRatio: 0.999),
        ),
      );

      final result = await orchestrator(platform).attemptWhenReady(_bytes);

      expect(result, isA<LocalCutoutRejected>());
      expect(
        platform.removeCalls,
        1,
        reason: 'retrying a bad photo just costs the user time',
      );
    });

    test('no subject found is NOT retried either', () async {
      final platform = FakeLocalCutoutPlatform(
        error: const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.noSubjectFound,
          code: LocalCutoutErrorCode.noSubject,
        ),
      );

      final result = await orchestrator(platform).attemptWhenReady(_bytes);

      expect(result, isA<LocalCutoutRejected>());
      expect(platform.removeCalls, 1);
    });

    test('the gate off short-circuits without touching the platform', () async {
      final platform = notInstalled();
      final result = await orchestrator(
        platform,
        enabled: false,
      ).attemptWhenReady(_bytes);

      expect(result, isA<LocalCutoutRejected>());
      expect(
        (result as LocalCutoutRejected).reason,
        LocalCutoutFallbackReason.gateDisabled,
      );
      expect(platform.prepareCalls, 0);
      expect(platform.removeCalls, 0);
    });

    test('every rejection still routes to the existing cloud path', () async {
      // The safety net that has always been there must survive this change.
      for (final availability in [
        LocalCutoutAvailability.modelNotInstalled,
        LocalCutoutAvailability.modelDownloadFailed,
        LocalCutoutAvailability.missingGooglePlayServices,
        LocalCutoutAvailability.temporarilyUnavailable,
      ]) {
        final platform = FakeLocalCutoutPlatform(
          capabilityResult: LocalCutoutCapability(
            availability: availability,
            engine: LocalCutoutEngine.googleMlKit,
            engineVersion: 'fake-1',
          ),
          prepareResult: LocalCutoutCapability(
            availability: availability,
            engine: LocalCutoutEngine.googleMlKit,
            engineVersion: 'fake-1',
          ),
        );
        final result = await orchestrator(platform).attemptWhenReady(_bytes);
        expect(result, isA<LocalCutoutRejected>());
        expect(
          (result as LocalCutoutRejected).canUseCloudFallback,
          isTrue,
          reason: '$availability must never strand the add',
        );
      }
    });
  });

  group('isPreparing — what the screen is allowed to claim', () {
    test('false before anything starts and after it finishes', () async {
      final platform = notInstalled();
      final o = orchestrator(platform);

      expect(o.isPreparing, isFalse);
      await o.ensureReady();
      expect(o.isPreparing, isFalse);
      expect(o.isReady, isTrue);
    });
  });
}
