/// Health, the native self-test and the release telemetry (local BG §4, §5, §6).
///
/// The premise these tests defend: "we fell back to the cloud" is not a diagnosis.
/// A gate compiled off, a channel never registered, an endpoint answering 404 and
/// an encoder that cannot represent its own output all produced the SAME
/// user-visible outcome, the same green build and the same healthy API. Collapsing
/// them into one boolean is how a release-wide outage stayed invisible for a whole
/// version.
///
/// So what is asserted here is that the states stay DISTINCT, that the ones which
/// mean "we broke it" are separable from the ones that mean "this device cannot" or
/// "this photo could not", and that none of the telemetry carries anything
/// identifying.
library;

import 'package:app/features/wardrobe/local_cutout/local_cutout_analytics.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_health.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_orchestrator.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_cutout_fakes.dart';

void main() {
  LocalCutoutOrchestrator android(
    FakeLocalCutoutPlatform platform, {
    bool master = true,
    bool androidArm = true,
  }) => LocalCutoutOrchestrator(
    platform: platform,
    masterEnabled: master,
    androidEnabled: androidArm,
    iosEnabled: false,
    diagnosticsEnabled: false,
    targetPlatform: TargetPlatform.android,
  );

  group('health states stay distinct', () {
    test('a gate compiled off is a RELEASE defect, not a device condition', () async {
      final health = await android(
        FakeLocalCutoutPlatform(),
        master: false,
      ).health();
      expect(health.state, LocalCutoutHealthState.gateDisabled);
      expect(health.state.isReleaseDefect, isTrue);
      expect(health.isUsable, isFalse);
    });

    test('an unregistered channel is a release defect, never "unsupported"', () async {
      final platform = FakeLocalCutoutPlatform()
        ..capabilityError = const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.channelUnavailable,
        );
      final health = await android(platform).health();
      expect(health.state, LocalCutoutHealthState.channelUnavailable);
      expect(
        health.state.isReleaseDefect,
        isTrue,
        reason: 'a production build with no native engine must page, not fall back quietly',
      );
    });

    test('an unsupported OS is NOT a release defect', () async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability.unsupported(),
      );
      final health = await android(platform).health();
      expect(health.state, LocalCutoutHealthState.unsupportedOs);
      expect(
        health.state.isReleaseDefect,
        isFalse,
        reason: 'paging on unsupportedOs would mean paging on the existence of old phones',
      );
    });

    test('a failed native self-test outranks whatever capability reports', () async {
      final platform = FakeLocalCutoutPlatform()
        ..selfTestResult = const LocalCutoutSelfTestResult(
          state: LocalCutoutSelfTestState.failed,
          engine: LocalCutoutEngine.googleMlKit,
          failureCode: 'mask_encoder_lost_alpha',
        );
      final orchestrator = android(platform);
      await orchestrator.selfTest();
      final health = await orchestrator.health();
      expect(health.state, LocalCutoutHealthState.nativeSelfTestFailed);
      expect(health.state.isReleaseDefect, isTrue);
      expect(
        platform.capabilityCalls,
        0,
        reason: 'a broken encoder makes the capability answer irrelevant',
      );
    });

    test('a model still downloading reads as warming, not as missing', () async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelNotInstalled,
          engine: LocalCutoutEngine.googleMlKit,
        ),
        prepareResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelNotInstalled,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      final orchestrator = android(platform);
      expect(
        (await orchestrator.health()).state,
        LocalCutoutHealthState.modelNotInstalled,
        reason: 'before anything asked for it, the model is simply absent',
      );
      await orchestrator.prepare();
      expect(
        (await orchestrator.health()).state,
        LocalCutoutHealthState.warmingModel,
        reason: 'a normal first run must not look like an outage on a dashboard',
      );
    });
  });

  group('a rejected photo is not an outage', () {
    for (final reason in [
      LocalCutoutFallbackReason.noSubjectFound,
      LocalCutoutFallbackReason.qualityRejected,
      LocalCutoutFallbackReason.invalidOutput,
      LocalCutoutFallbackReason.backendRejected,
    ]) {
      test('${reason.name} reads as healthy-but-rejected', () {
        final state = LocalCutoutHealth.stateForReason(reason);
        expect(state, LocalCutoutHealthState.healthyButImageRejected);
        expect(state.isReleaseDefect, isFalse);
      });
    }

    test('a backend gate off IS an outage', () {
      final state = LocalCutoutHealth.stateForReason(
        LocalCutoutFallbackReason.backendUnavailable,
      );
      expect(state, LocalCutoutHealthState.backendUnavailable);
      expect(state.isReleaseDefect, isTrue);
    });
  });

  group('native self-test', () {
    test('runs at most once per process', () async {
      final platform = FakeLocalCutoutPlatform();
      final orchestrator = android(platform);
      await orchestrator.selfTest();
      await orchestrator.selfTest();
      await orchestrator.selfTest();
      expect(
        platform.selfTestCalls,
        1,
        reason: 'it performs a real Vision inference on iOS; once per process is the budget',
      );
    });

    test('is never run when the build has the feature off', () async {
      final platform = FakeLocalCutoutPlatform();
      final result = await android(platform, master: false).selfTest();
      expect(platform.selfTestCalls, 0);
      expect(result.state, LocalCutoutSelfTestState.unavailable);
    });

    test('an undecodable reply is unavailable, never a false pass', () {
      expect(
        LocalCutoutSelfTestResult.fromMap(null).state,
        LocalCutoutSelfTestState.unavailable,
      );
      expect(
        LocalCutoutSelfTestResult.fromMap(<Object?, Object?>{'status': 'weird'}).state,
        LocalCutoutSelfTestState.unavailable,
      );
    });

    test('decodes the native contract fields', () {
      final result = LocalCutoutSelfTestResult.fromMap(<Object?, Object?>{
        'status': 'fail',
        'engine': 'apple_vision',
        'engineVersion': 'vision-foreground-instance-mask-r1',
        'channelVersion': 1,
        'encoderOk': false,
        'cacheOk': true,
        'platformAvailable': true,
        'modelAvailable': false,
        'failureCode': 'cutout_encoder_lost_transparency',
      });
      expect(result.state, LocalCutoutSelfTestState.failed);
      expect(result.engine, LocalCutoutEngine.appleVision);
      expect(result.encoderOk, isFalse);
      expect(result.failureCode, 'cutout_encoder_lost_transparency');
    });

    test('bounds an over-long native string rather than trusting it', () {
      final result = LocalCutoutSelfTestResult.fromMap(<Object?, Object?>{
        'status': 'pass',
        'engineVersion': 'x' * 500,
        'failureCode': 'y' * 500,
      });
      expect(result.engineVersion.length, 64);
      expect(result.failureCode.length, 48);
    });
  });

  group('model preparation does not storm Play services', () {
    test('the background path asks DEFERRED, never urgent', () async {
      final platform = FakeLocalCutoutPlatform();
      await android(platform).prepare();
      expect(platform.lastPrepareUrgent, isFalse);
      expect(
        platform.urgentPrepareCalls,
        0,
        reason: 'app start must never wait on a model download',
      );
    });

    test('a successful preparation is cached for the process', () async {
      final platform = FakeLocalCutoutPlatform();
      final orchestrator = android(platform);
      await orchestrator.prepare();
      await orchestrator.prepare();
      await orchestrator.prepare();
      expect(
        platform.prepareCalls,
        1,
        reason: 're-entering the closet must not become a request per rebuild',
      );
    });

    test('a FAILED preparation is retried, not written off for the process', () async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelDownloadFailed,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      final orchestrator = android(platform);
      await orchestrator.prepare();
      await orchestrator.prepare();
      expect(platform.prepareCalls, 2);
    });

    test('the add path escalates to ONE urgent install, and only one', () async {
      final platform = FakeLocalCutoutPlatform(
        capabilityResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelNotInstalled,
          engine: LocalCutoutEngine.googleMlKit,
        ),
        prepareResult: const LocalCutoutCapability(
          availability: LocalCutoutAvailability.modelDownloadFailed,
          engine: LocalCutoutEngine.googleMlKit,
        ),
      );
      final orchestrator = android(platform);
      await orchestrator.attempt(Uint8List.fromList(<int>[1, 2, 3]));
      await orchestrator.attempt(Uint8List.fromList(<int>[1, 2, 3]));
      await orchestrator.attempt(Uint8List.fromList(<int>[1, 2, 3]));
      expect(
        platform.urgentPrepareCalls,
        1,
        reason: 'one bounded attempt; after that go to the cloud rather than retry in a loop',
      );
    });
  });

  group('release telemetry carries the build, and nothing identifying', () {
    final build = localCutoutBuildProperties(
      platform: 'android',
      appVersion: '1.0.18',
      buildNumber: '21',
      shortGitSha: '9605b4e0',
    );

    test('every operation event names its own build', () {
      final properties = localCutoutOperationProperties(
        build: build,
        health: const LocalCutoutHealth(state: LocalCutoutHealthState.enabledAndReady),
        localGateEnabled: true,
        localAttempted: true,
        localAccepted: true,
        cloudFallbackUsed: false,
      );
      expect(properties['app_version'], '1.0.18');
      expect(properties['build_number'], '21');
      expect(properties['short_git_sha'], '9605b4e0');
      expect(
        properties['local_attempted'],
        isTrue,
        reason: 'the series an alert watches for a collapse to near zero',
      );
    });

    test('a successful cloud fallback still records that local was NOT used', () {
      final properties = localCutoutOperationProperties(
        build: build,
        health: const LocalCutoutHealth(state: LocalCutoutHealthState.channelUnavailable),
        localGateEnabled: true,
        localAttempted: true,
        localAccepted: false,
        cloudFallbackUsed: true,
        fallbackReason: LocalCutoutFallbackReason.channelUnavailable,
      );
      expect(properties['local_accepted'], isFalse);
      expect(properties['cloud_fallback_used'], isTrue);
      expect(properties['health'], 'channelUnavailable');
      expect(
        properties['fallback_reason'],
        'channelUnavailable',
        reason: 'a working cloud fallback must not be able to read as a healthy release',
      );
    });

    test('latency is bucketed, never exact', () {
      final properties = localCutoutOperationProperties(
        build: build,
        health: const LocalCutoutHealth(state: LocalCutoutHealthState.enabledAndReady),
        localGateEnabled: true,
        localAttempted: true,
        localAccepted: true,
        cloudFallbackUsed: false,
        nativeLatency: const Duration(milliseconds: 1234),
      );
      expect(properties['native_latency_bucket'], '500ms-1.5s');
      expect(properties.values, isNot(contains(1234)));
    });

    test('no property is a path, a URL, an email or bytes', () {
      final properties = localCutoutOperationProperties(
        build: build,
        health: LocalCutoutHealth(
          state: LocalCutoutHealthState.nativeSelfTestFailed,
          engine: LocalCutoutEngine.googleMlKit,
          selfTest: const LocalCutoutSelfTestResult(
            state: LocalCutoutSelfTestState.failed,
            failureCode: 'mask_encoder_lost_alpha',
          ),
        ),
        localGateEnabled: true,
        localAttempted: true,
        localAccepted: false,
        cloudFallbackUsed: true,
        fallbackReason: LocalCutoutFallbackReason.nativeError,
        backendStatusCategory: 'gate_off',
      );
      for (final entry in properties.entries) {
        final value = entry.value;
        if (value is! String) continue;
        expect(value, isNot(contains('/')), reason: '${entry.key} looks like a path or URL');
        expect(value, isNot(contains('@')), reason: '${entry.key} looks like an address');
        expect(value, isNot(contains('http')), reason: '${entry.key} looks like a URL');
      }
    });

    test('the self-test event carries only the bounded native fields', () {
      final properties = localCutoutSelfTestProperties(
        build: build,
        result: const LocalCutoutSelfTestResult(
          state: LocalCutoutSelfTestState.passed,
          engine: LocalCutoutEngine.googleMlKit,
          encoderOk: true,
          cacheOk: true,
          platformAvailable: true,
          modelAvailable: true,
          channelVersion: 1,
          failureCode: 'none',
        ),
      );
      expect(properties.keys, containsAll(<String>['encoder_ok', 'cache_ok', 'model_available']));
      expect(properties.keys, isNot(contains('mask_file_path')));
      expect(properties.keys, isNot(contains('operation_id')));
    });
  });
}
