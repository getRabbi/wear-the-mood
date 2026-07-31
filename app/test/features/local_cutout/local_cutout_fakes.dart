/// Test doubles for local-first background removal (local BG §11.2).
///
/// The orchestrator (Phase 5) must be provable without a device, a model or a
/// registered method channel, so every scenario in the test matrix — unsupported
/// OS, missing Play services, model download failure, timeout, busy, invalid
/// output — is expressible here.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:app/features/wardrobe/local_cutout/local_cutout_health.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';

/// A scriptable [LocalCutoutPlatform].
///
/// Defaults to a healthy Android engine returning a plausible result, so a test
/// only has to state the thing it is actually about.
class FakeLocalCutoutPlatform implements LocalCutoutPlatform {
  FakeLocalCutoutPlatform({
    LocalCutoutCapability? capabilityResult,
    LocalCutoutCapability? prepareResult,
    this.result,
    this.error,
    this.removeDelay = Duration.zero,
  }) : capabilityResult =
           capabilityResult ??
           const LocalCutoutCapability(
             availability: LocalCutoutAvailability.available,
             engine: LocalCutoutEngine.googleMlKit,
             engineVersion: 'fake-1',
           ),
       prepareResult = prepareResult ?? capabilityResult;

  /// What [capability] returns.
  LocalCutoutCapability capabilityResult;

  /// What [prepare] returns; defaults to [capabilityResult].
  LocalCutoutCapability? prepareResult;

  /// What [removeBackground] returns when [error] is null.
  LocalCutoutResult? result;

  /// When set, [removeBackground] throws this instead of returning.
  LocalCutoutPlatformException? error;

  /// When set, [capability] throws — e.g. a build with no native engine.
  LocalCutoutPlatformException? capabilityError;

  /// When set, [prepare] throws, to prove preparation never propagates.
  LocalCutoutPlatformException? prepareError;

  /// Lets a test outrun a bounded timeout.
  Duration removeDelay;

  /// Make cleanup/sweep fail, to prove the cache swallows housekeeping errors.
  bool cleanupThrows = false;
  bool sweepThrows = false;
  int sweepResult = 0;

  /// What [selfTest] reports. Defaults to a healthy native half, so a test only
  /// states the thing it is about.
  LocalCutoutSelfTestResult selfTestResult = const LocalCutoutSelfTestResult(
    state: LocalCutoutSelfTestState.passed,
    engine: LocalCutoutEngine.googleMlKit,
    engineVersion: 'fake-1',
    channelVersion: 1,
    encoderOk: true,
    cacheOk: true,
    platformAvailable: true,
    modelAvailable: true,
    failureCode: 'none',
  );

  // ── call log, so tests can assert on interactions ────────────────────────
  int capabilityCalls = 0;
  int prepareCalls = 0;
  int removeCalls = 0;
  int selfTestCalls = 0;

  /// How often an URGENT install was requested. The add path may ask once; the
  /// background path after sign-in must never ask urgently (§4).
  int urgentPrepareCalls = 0;
  bool? lastPrepareUrgent;
  final List<String> cancelled = <String>[];
  final List<String> cleaned = <String>[];
  int sweepCalls = 0;
  Duration? sweptMaxAge;

  /// The bytes handed to the last [removeBackground] — asserts that the engine
  /// segments the EXACT bytes that get uploaded (§8.1).
  Uint8List? lastImageBytes;

  /// Whether the last removal asked native to capture diagnostics (iOS Phase 3).
  bool? lastCaptureDiagnostics;

  /// Queued outcome for [exportDiagnostics], and what it was asked to export.
  LocalCutoutExportOutcome exportResult = LocalCutoutExportOutcome.shared;
  final List<String> exported = <String>[];

  @override
  Future<LocalCutoutCapability> capability() async {
    capabilityCalls++;
    final failure = capabilityError;
    if (failure != null) throw failure;
    return capabilityResult;
  }

  @override
  Future<LocalCutoutCapability> prepare({
    required Duration timeout,
    bool urgent = false,
  }) async {
    prepareCalls++;
    urgentPrepareCalls += urgent ? 1 : 0;
    lastPrepareUrgent = urgent;
    final failure = prepareError;
    if (failure != null) throw failure;
    final prepared = prepareResult ?? capabilityResult;
    capabilityResult = prepared;
    return prepared;
  }

  @override
  Future<LocalCutoutSelfTestResult> selfTest({required Duration timeout}) async {
    selfTestCalls++;
    return selfTestResult;
  }

  @override
  Future<LocalCutoutResult> removeBackground({
    required Uint8List imageBytes,
    required Duration timeout,
    bool captureDiagnostics = false,
  }) async {
    removeCalls++;
    lastImageBytes = imageBytes;
    lastCaptureDiagnostics = captureDiagnostics;
    if (removeDelay > Duration.zero) {
      await Future<void>.delayed(removeDelay);
    }
    final failure = error;
    if (failure != null) throw failure;
    final value = result;
    if (value == null) {
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.invalidOutput,
        code: LocalCutoutErrorCode.invalidOutput,
      );
    }
    return value;
  }

  @override
  Future<LocalCutoutExportOutcome> exportDiagnostics(String operationId) async {
    exported.add(operationId);
    return exportResult;
  }

  @override
  Future<void> cancel(String operationId) async => cancelled.add(operationId);

  @override
  Future<void> cleanup(String operationId) async {
    cleaned.add(operationId);
    if (cleanupThrows) {
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.nativeError,
      );
    }
  }

  @override
  Future<int> sweepCache({required Duration maxAge}) async {
    sweepCalls++;
    sweptMaxAge = maxAge;
    if (sweepThrows) {
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.nativeError,
      );
    }
    return sweepResult;
  }
}

/// Well-formed metrics for a typical flat-lay: garment over a third of the
/// frame, little border contact, a soft but not extreme edge.
LocalCutoutMetrics fakeMetrics({
  int width = 1600,
  int height = 1200,
  int subjectCount = 1,
  double foregroundAreaRatio = 0.35,
  double borderForegroundRatio = 0.05,
  double uncertainPixelRatio = 0.08,
  double meanForegroundConfidence = 0.92,
  Rect? foregroundBounds,
}) => LocalCutoutMetrics(
  width: width,
  height: height,
  subjectCount: subjectCount,
  foregroundAreaRatio: foregroundAreaRatio,
  borderForegroundRatio: borderForegroundRatio,
  uncertainPixelRatio: uncertainPixelRatio,
  meanForegroundConfidence: meanForegroundConfidence,
  foregroundBounds: foregroundBounds,
);

/// A successful result. [directory] only shapes the two file paths — the contract
/// exposes no deletable directory, and cleanup is by [operationId] (R10b).
LocalCutoutResult fakeResult({
  LocalCutoutEngine engine = LocalCutoutEngine.googleMlKit,
  String operationId = 'op-test',
  String directory = '/tmp/wtm-local-cutout/op-test',
  String? maskFilePath,
  String? cutoutFilePath,
  LocalCutoutMetrics? metrics,
  Duration latency = const Duration(milliseconds: 900),
}) => LocalCutoutResult(
  engine: engine,
  engineVersion: 'fake-1',
  operationId: operationId,
  maskFilePath: maskFilePath ?? '$directory/mask.png',
  cutoutFilePath: cutoutFilePath ?? '$directory/cutout.png',
  metrics: metrics ?? fakeMetrics(),
  latency: latency,
);
