import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_orchestrator.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_quality_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_cutout_fakes.dart';

/// The local-vs-cloud decision (local BG §9.1, §11.2).
///
/// This is the class that decides what a user actually experiences, so every route
/// through it is pinned: which conditions go local, which fall back to the existing
/// BiRefNet flow, and the one condition that must NOT fall back because the cloud
/// worker would fail too.
void main() {
  final bytes = Uint8List.fromList(List.filled(64, 7));
  const source = SourceDimensions(1600, 1200);

  LocalCutoutOrchestrator build({
    required FakeLocalCutoutPlatform platform,
    bool master = true,
    bool android = true,
    bool ios = true,
    bool diagnostics = false,
    TargetPlatform target = TargetPlatform.android,
    SourceDimensions? dimensions = source,
    Object? dimensionsThrow,
    LocalCutoutQualityPolicy policy = kDefaultLocalCutoutQualityPolicy,
    Duration timeout = const Duration(seconds: 20),
  }) => LocalCutoutOrchestrator(
    platform: platform,
    policy: policy,
    timeout: timeout,
    masterEnabled: master,
    androidEnabled: android,
    iosEnabled: ios,
    diagnosticsEnabled: diagnostics,
    targetPlatform: target,
    readDimensions: (_) async {
      if (dimensionsThrow != null) throw dimensionsThrow;
      return dimensions;
    },
  );

  /// A result whose metrics agree with the source, so the policy accepts it.
  LocalCutoutResult goodResult({
    LocalCutoutEngine engine = LocalCutoutEngine.googleMlKit,
    LocalCutoutMetrics? metrics,
  }) => fakeResult(
    engine: engine,
    operationId: 'aabbccdd',
    metrics: metrics ?? fakeMetrics(width: source.width, height: source.height),
  );

  Future<LocalCutoutFallbackReason?> reasonOf(Future<LocalCutoutAttempt> future) async {
    final attempt = await future;
    return attempt is LocalCutoutRejected ? attempt.reason : null;
  }

  group('feature gates', () {
    test('master gate off never touches the platform', () async {
      final platform = FakeLocalCutoutPlatform();
      final orchestrator = build(platform: platform, master: false);

      expect(orchestrator.isEnabledForThisBuild, isFalse);
      expect(
        await reasonOf(orchestrator.attempt(bytes)),
        LocalCutoutFallbackReason.gateDisabled,
      );
      expect(platform.capabilityCalls, 0);
      expect(platform.removeCalls, 0);
    });

    test('the Android arm gates Android independently of iOS', () async {
      final platform = FakeLocalCutoutPlatform();
      final orchestrator = build(
        platform: platform,
        android: false,
        ios: true,
        target: TargetPlatform.android,
      );

      expect(orchestrator.isEnabledForThisBuild, isFalse);
      expect(
        await reasonOf(orchestrator.attempt(bytes)),
        LocalCutoutFallbackReason.gateDisabled,
      );
    });

    test('the iOS arm gates iOS independently of Android', () async {
      final orchestrator = build(
        platform: FakeLocalCutoutPlatform(),
        android: true,
        ios: false,
        target: TargetPlatform.iOS,
      );
      expect(orchestrator.isEnabledForThisBuild, isFalse);
    });

    test('an unsupported host platform is never enabled', () async {
      for (final target in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        final orchestrator = build(
          platform: FakeLocalCutoutPlatform(),
          target: target,
        );
        expect(orchestrator.isEnabledForThisBuild, isFalse, reason: '$target');
      }
    });

    test('both arms on for the running platform enables the flow', () {
      expect(
        build(
          platform: FakeLocalCutoutPlatform(),
          target: TargetPlatform.iOS,
        ).isEnabledForThisBuild,
        isTrue,
      );
    });
  });

  group('device capability routes to the cloud', () {
    Future<void> expectFallback(
      LocalCutoutAvailability availability,
      LocalCutoutFallbackReason expected, {
      TargetPlatform target = TargetPlatform.android,
    }) async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: LocalCutoutCapability(
          availability: availability,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      // `prepare` must not rescue a permanent condition.
      platform.prepareResult = LocalCutoutCapability(
        availability: availability,
        engine: LocalCutoutEngine.googleMlKit,
      );
      final orchestrator = build(platform: platform, target: target);

      expect(await reasonOf(orchestrator.attempt(bytes)), expected);
      expect(platform.removeCalls, 0, reason: 'no engine call when unavailable');
    }

    test('iOS below 17 falls back', () async {
      await expectFallback(
        LocalCutoutAvailability.unsupportedOs,
        LocalCutoutFallbackReason.unsupportedOs,
        target: TargetPlatform.iOS,
      );
    });

    test('missing Google Play services falls back', () async {
      await expectFallback(
        LocalCutoutAvailability.missingGooglePlayServices,
        LocalCutoutFallbackReason.missingGooglePlayServices,
      );
    });

    test('a model that never installs falls back', () async {
      await expectFallback(
        LocalCutoutAvailability.modelNotInstalled,
        LocalCutoutFallbackReason.modelNotInstalled,
      );
    });

    test('a failed model download falls back', () async {
      await expectFallback(
        LocalCutoutAvailability.modelDownloadFailed,
        LocalCutoutFallbackReason.modelDownloadFailed,
      );
    });

    test('a not-yet-installed model gets ONE bounded prepare, then proceeds', () async {
      // The common Android first-run case: metadata has not landed yet, so ask
      // Play services once rather than sending the user to the 90 s path forever.
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelNotInstalled,
          engine: LocalCutoutEngine.googleMlKit,
        ),
        prepareResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.available,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      platform.result = goodResult();
      final orchestrator = build(platform: platform);

      final attempt = await orchestrator.attempt(bytes);

      expect(attempt, isA<LocalCutoutAccepted>());
      expect(platform.prepareCalls, 1);
      expect(platform.removeCalls, 1);
    });

    test('a missing native channel is transient, not permanent', () async {
      // An engine-less build must not be reported as a broken device.
      final platform = FakeLocalCutoutPlatform();
      platform.capabilityError = const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.channelUnavailable,
      );
      expect(
        await reasonOf(build(platform: platform).attempt(bytes)),
        LocalCutoutFallbackReason.temporarilyUnavailable,
      );
    });
  });

  group('native failures route to the cloud', () {
    Future<void> expectNativeFallback(
      LocalCutoutFallbackReason thrown,
      LocalCutoutFallbackReason expected,
    ) async {
      final platform = FakeLocalCutoutPlatform()
        ..error = LocalCutoutPlatformException(thrown);
      expect(await reasonOf(build(platform: platform).attempt(bytes)), expected);
    }

    test('a local timeout falls back', () async {
      await expectNativeFallback(
        LocalCutoutFallbackReason.timeout,
        LocalCutoutFallbackReason.timeout,
      );
    });

    test('no subject found falls back', () async {
      await expectNativeFallback(
        LocalCutoutFallbackReason.noSubjectFound,
        LocalCutoutFallbackReason.noSubjectFound,
      );
    });

    test('a busy engine falls back as temporarily unavailable', () async {
      await expectNativeFallback(
        LocalCutoutFallbackReason.temporarilyUnavailable,
        LocalCutoutFallbackReason.temporarilyUnavailable,
      );
    });

    test('an untyped native throw still yields a typed reason', () async {
      final platform = FakeLocalCutoutPlatform()..error = null;
      platform.result = null; // makes the fake throw invalidOutput
      expect(
        await reasonOf(build(platform: platform).attempt(bytes)),
        LocalCutoutFallbackReason.invalidOutput,
      );
    });

    test('a channel that never replies is bounded by the orchestrator', () async {
      // A native side that returns SUCCESSFULLY but far too late. The orchestrator's
      // own backstop (native bound + grace) must fire, otherwise a wedged channel
      // would hold Add Garment open indefinitely.
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult()
        ..removeDelay = const Duration(seconds: 2);
      final orchestrator = LocalCutoutOrchestrator(
        platform: platform,
        timeout: const Duration(milliseconds: 5),
        channelGrace: const Duration(milliseconds: 10),
        masterEnabled: true,
        androidEnabled: true,
        iosEnabled: true,
        targetPlatform: TargetPlatform.android,
        readDimensions: (_) async => source,
      );

      expect(
        await reasonOf(orchestrator.attempt(bytes)),
        LocalCutoutFallbackReason.timeout,
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('source bytes', () {
    test('empty bytes are TERMINAL, never a cloud fallback', () async {
      // The cloud worker needs the same original; queuing would guarantee failure.
      final attempt = await build(
        platform: FakeLocalCutoutPlatform(),
      ).attempt(Uint8List(0));

      expect(attempt, isA<LocalCutoutRejected>());
      final rejected = attempt as LocalCutoutRejected;
      expect(rejected.reason, LocalCutoutFallbackReason.sourceMissing);
      expect(rejected.canUseCloudFallback, isFalse);
    });

    test('every other reason CAN use the cloud fallback', () {
      for (final reason in LocalCutoutFallbackReason.values) {
        expect(
          reason.canUseCloudFallback,
          reason != LocalCutoutFallbackReason.sourceMissing,
          reason: reason.name,
        );
      }
    });

    test('undecodable source dimensions fall back without an engine call', () async {
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      expect(
        await reasonOf(
          build(platform: platform, dimensions: null).attempt(bytes),
        ),
        LocalCutoutFallbackReason.invalidOutput,
      );
      expect(platform.removeCalls, 0);
    });

    test('a throwing dimension reader falls back rather than crashing', () async {
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      expect(
        await reasonOf(
          build(
            platform: platform,
            dimensionsThrow: StateError('boom'),
          ).attempt(bytes),
        ),
        LocalCutoutFallbackReason.invalidOutput,
      );
    });

    test('the engine receives the EXACT bytes it was given', () async {
      // Same bytes to the engine and to the upload is the only way the mask and
      // the stored original can be guaranteed to agree (§8.1).
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      await build(platform: platform).attempt(bytes);
      expect(platform.lastImageBytes, same(bytes));
    });
  });

  group('quality policy', () {
    test('a hard rejection falls back AND discards the scratch files', () async {
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult(
          // Mask dimensions disagreeing with the source is a hard structural fail.
          metrics: fakeMetrics(width: 800, height: 600),
        );

      final reason = await reasonOf(build(platform: platform).attempt(bytes));

      expect(reason, LocalCutoutFallbackReason.invalidOutput);
      expect(platform.cleaned, ['aabbccdd'], reason: 'rejected output must not linger');
    });

    test('an empty mask is rejected as a quality failure', () async {
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult(
          metrics: fakeMetrics(
            width: source.width,
            height: source.height,
            foregroundAreaRatio: 0.001,
          ),
        );
      expect(
        await reasonOf(build(platform: platform).attempt(bytes)),
        LocalCutoutFallbackReason.qualityRejected,
      );
    });

    test('no subject in the metrics is its own reason', () async {
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult(
          metrics: fakeMetrics(
            width: source.width,
            height: source.height,
            subjectCount: 0,
          ),
        );
      expect(
        await reasonOf(build(platform: platform).attempt(bytes)),
        LocalCutoutFallbackReason.noSubjectFound,
      );
    });

    test('a soft warning is ACCEPTED and carried, not rejected', () async {
      // Lace, chiffon and edge-touching garments land here. Rejecting them would
      // undo the whole point of going local.
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult(
          metrics: fakeMetrics(
            width: source.width,
            height: source.height,
            uncertainPixelRatio: 0.7,
            borderForegroundRatio: 0.9,
          ),
        );

      final attempt = await build(platform: platform).attempt(bytes);

      expect(attempt, isA<LocalCutoutAccepted>());
      final accepted = attempt as LocalCutoutAccepted;
      expect(accepted.warnings, contains(LocalCutoutQualityWarning.highUncertainty));
      expect(accepted.warnings, contains(LocalCutoutQualityWarning.highBorderContact));
      // Accepted output is kept for the caller to upload and preview.
      expect(platform.cleaned, isEmpty);
    });

    test('a clean result is accepted with no warnings', () async {
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      final attempt = await build(platform: platform).attempt(bytes);

      expect(attempt, isA<LocalCutoutAccepted>());
      expect((attempt as LocalCutoutAccepted).warnings, isEmpty);
      expect(attempt.result.operationId, 'aabbccdd');
    });

    test('an injected stricter policy changes the verdict', () async {
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      const strict = LocalCutoutQualityPolicy(minForegroundAreaRatio: 0.9);

      expect(
        await reasonOf(build(platform: platform, policy: strict).attempt(bytes)),
        LocalCutoutFallbackReason.qualityRejected,
      );
    });
  });

  group('apple vision results flow through identically', () {
    test('an iOS result is accepted with no platform branch', () async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.available,
          engine: LocalCutoutEngine.appleVision,
        ),
      )..result = goodResult(engine: LocalCutoutEngine.appleVision);

      final attempt = await build(
        platform: platform,
        target: TargetPlatform.iOS,
      ).attempt(bytes);

      expect(attempt, isA<LocalCutoutAccepted>());
      expect(
        (attempt as LocalCutoutAccepted).result.engine,
        LocalCutoutEngine.appleVision,
      );
    });
  });

  group('cleanup and preparation', () {
    test('discard forwards the operation id, never a path', () async {
      final platform = FakeLocalCutoutPlatform();
      await build(platform: platform).discard('aabbccdd');
      expect(platform.cleaned, ['aabbccdd']);
    });

    test('discarding null is a safe no-op', () async {
      final platform = FakeLocalCutoutPlatform();
      await build(platform: platform).discard(null);
      expect(platform.cleaned, isEmpty);
    });

    test('sweep clears what a previous session orphaned', () async {
      final platform = FakeLocalCutoutPlatform()..sweepResult = 3;
      expect(await build(platform: platform).sweepStaleCache(), 3);
    });

    test('prepare is a no-op when the gates are off', () async {
      final platform = FakeLocalCutoutPlatform();
      final availability = await build(
        platform: platform,
        master: false,
      ).prepare();

      expect(availability, LocalCutoutAvailability.unsupportedOs);
      expect(platform.prepareCalls, 0);
    });

    test('prepare reports what the platform says', () async {
      final platform = FakeLocalCutoutPlatform(
        prepareResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelDownloadFailed,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      expect(
        await build(platform: platform).prepare(),
        LocalCutoutAvailability.modelDownloadFailed,
      );
    });

    test('prepare never throws, whatever the platform does', () async {
      final platform = FakeLocalCutoutPlatform()
        ..prepareError = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.nativeError,
        );
      expect(
        await build(platform: platform).prepare(),
        LocalCutoutAvailability.temporarilyUnavailable,
      );
    });
  });

  group('device diagnostics (iOS Phase 3, internal builds only)', () {
    test('are unavailable unless iOS local BG AND diagnostics are both on', () {
      final platform = FakeLocalCutoutPlatform();
      // The normal production shape: iOS arm on, diagnostics compiled out.
      expect(
        build(
          platform: platform,
          diagnostics: false,
          target: TargetPlatform.iOS,
        ).diagnosticsAvailable,
        isFalse,
      );
      // Diagnostics requested but the iOS arm is off — nothing to diagnose.
      expect(
        build(
          platform: platform,
          ios: false,
          diagnostics: true,
          target: TargetPlatform.iOS,
        ).diagnosticsAvailable,
        isFalse,
      );
      expect(
        build(platform: platform, diagnostics: true, target: TargetPlatform.iOS)
            .diagnosticsAvailable,
        isTrue,
      );
    });

    test('never activate on Android, even with the flag set', () {
      final platform = FakeLocalCutoutPlatform();
      expect(
        build(
          platform: platform,
          diagnostics: true,
          target: TargetPlatform.android,
        ).diagnosticsAvailable,
        isFalse,
      );
    });

    test('a production build does not ask native to capture anything', () async {
      final platform = FakeLocalCutoutPlatform()..result = goodResult();
      await build(platform: platform, target: TargetPlatform.android).attempt(bytes);
      expect(platform.lastCaptureDiagnostics, isFalse);
    });

    test('a diagnostic build asks native to capture', () async {
      final platform = FakeLocalCutoutPlatform()
        ..result = goodResult(engine: LocalCutoutEngine.appleVision);
      await build(
        platform: platform,
        diagnostics: true,
        target: TargetPlatform.iOS,
      ).attempt(bytes);
      expect(platform.lastCaptureDiagnostics, isTrue);
    });

    test('a native failure surfaces its preserved operation id', () async {
      final platform = FakeLocalCutoutPlatform()
        ..error = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.invalidOutput,
          code: LocalCutoutErrorCode.invalidOutput,
          diagnosticOperationId: 'ffeeddcc',
        );

      final attempt = await build(
        platform: platform,
        diagnostics: true,
        target: TargetPlatform.iOS,
      ).attempt(bytes);

      final rejected = attempt as LocalCutoutRejected;
      expect(rejected.reason, LocalCutoutFallbackReason.invalidOutput);
      expect(rejected.hasExportableDiagnostics, isTrue);
      expect(rejected.diagnosticOperationId, 'ffeeddcc');
    });

    test('a production build never carries a diagnostic id', () async {
      final platform = FakeLocalCutoutPlatform()
        ..error = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.invalidOutput,
          code: LocalCutoutErrorCode.invalidOutput,
          // Even if native somehow sent one, the gate must drop it.
          diagnosticOperationId: 'ffeeddcc',
        );

      final attempt = await build(
        platform: platform,
        target: TargetPlatform.iOS,
      ).attempt(bytes);

      final rejected = attempt as LocalCutoutRejected;
      expect(rejected.hasExportableDiagnostics, isFalse);
      expect(rejected.diagnosticOperationId, isNull);
      // Fallback behaviour is untouched.
      expect(rejected.canUseCloudFallback, isTrue);
    });

    test('a quality rejection KEEPS its evidence on a diagnostic build', () async {
      // A mask whose dimensions disagree with the source is rejected by the policy.
      final platform = FakeLocalCutoutPlatform()
        ..result = fakeResult(
          engine: LocalCutoutEngine.appleVision,
          operationId: '11223344',
          metrics: fakeMetrics(width: 100, height: 100),
        );

      final attempt = await build(
        platform: platform,
        diagnostics: true,
        target: TargetPlatform.iOS,
      ).attempt(bytes);

      final rejected = attempt as LocalCutoutRejected;
      expect(rejected.diagnosticOperationId, '11223344');
      expect(
        platform.cleaned,
        isEmpty,
        reason: 'the mask must survive so a tester can look at it',
      );
    });

    test('a quality rejection still discards on a production build', () async {
      final platform = FakeLocalCutoutPlatform()
        ..result = fakeResult(
          engine: LocalCutoutEngine.appleVision,
          operationId: '11223344',
          metrics: fakeMetrics(width: 100, height: 100),
        );

      final attempt = await build(
        platform: platform,
        target: TargetPlatform.iOS,
      ).attempt(bytes);

      expect((attempt as LocalCutoutRejected).diagnosticOperationId, isNull);
      expect(platform.cleaned, contains('11223344'));
    });

    test('export is refused when diagnostics are off, without touching native', () async {
      final platform = FakeLocalCutoutPlatform();
      final outcome = await build(
        platform: platform,
        target: TargetPlatform.iOS,
      ).exportDiagnostics('11223344');

      expect(outcome, LocalCutoutExportOutcome.unavailable);
      expect(platform.exported, isEmpty);
    });

    test('export is refused for a null id', () async {
      final platform = FakeLocalCutoutPlatform();
      final outcome = await build(
        platform: platform,
        diagnostics: true,
        target: TargetPlatform.iOS,
      ).exportDiagnostics(null);

      expect(outcome, LocalCutoutExportOutcome.unavailable);
      expect(platform.exported, isEmpty);
    });

    test('export forwards the exact operation id and its outcome', () async {
      final platform = FakeLocalCutoutPlatform()
        ..exportResult = LocalCutoutExportOutcome.shared;

      final outcome = await build(
        platform: platform,
        diagnostics: true,
        target: TargetPlatform.iOS,
      ).exportDiagnostics('deadbeef');

      expect(outcome, LocalCutoutExportOutcome.shared);
      expect(platform.exported, <String>['deadbeef']);
    });

    test('a cancelled share is reported as cancelled, not as a failure', () async {
      final platform = FakeLocalCutoutPlatform()
        ..exportResult = LocalCutoutExportOutcome.cancelled;

      expect(
        await build(
          platform: platform,
          diagnostics: true,
          target: TargetPlatform.iOS,
        ).exportDiagnostics('deadbeef'),
        LocalCutoutExportOutcome.cancelled,
      );
    });
  });
}
