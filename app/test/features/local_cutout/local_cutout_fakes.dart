/// Test doubles for local-first background removal (local BG §11.2).
///
/// The orchestrator (Phase 5) must be provable without a device, a model or a
/// registered method channel, so every scenario in the test matrix — unsupported
/// OS, missing Play services, model download failure, timeout, busy, invalid
/// output — is expressible here.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

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

  /// Lets a test outrun a bounded timeout.
  Duration removeDelay;

  // ── call log, so tests can assert on interactions ────────────────────────
  int capabilityCalls = 0;
  int prepareCalls = 0;
  int removeCalls = 0;
  final List<String> cancelled = <String>[];
  final List<String> cleaned = <String>[];
  int sweepCalls = 0;

  /// The bytes handed to the last [removeBackground] — asserts that the engine
  /// segments the EXACT bytes that get uploaded (§8.1).
  Uint8List? lastImageBytes;

  @override
  Future<LocalCutoutCapability> capability() async {
    capabilityCalls++;
    return capabilityResult;
  }

  @override
  Future<LocalCutoutCapability> prepare({required Duration timeout}) async {
    prepareCalls++;
    final prepared = prepareResult ?? capabilityResult;
    capabilityResult = prepared;
    return prepared;
  }

  @override
  Future<LocalCutoutResult> removeBackground({
    required Uint8List imageBytes,
    required Duration timeout,
  }) async {
    removeCalls++;
    lastImageBytes = imageBytes;
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
  Future<void> cancel(String operationId) async => cancelled.add(operationId);

  @override
  Future<void> cleanup(String operationId) async => cleaned.add(operationId);

  @override
  Future<int> sweepCache({required Duration maxAge}) async {
    sweepCalls++;
    return 0;
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

/// A successful result pointing at [directory]; pair it with real temp files
/// when a test needs the files to exist.
LocalCutoutResult fakeResult({
  LocalCutoutEngine engine = LocalCutoutEngine.googleMlKit,
  String operationId = 'op-test',
  String directory = '/tmp/wtm-bg/op-test',
  String? maskFilePath,
  String? cutoutFilePath,
  LocalCutoutMetrics? metrics,
  Duration latency = const Duration(milliseconds: 900),
}) => LocalCutoutResult(
  engine: engine,
  engineVersion: 'fake-1',
  operationId: operationId,
  operationDirectory: directory,
  maskFilePath: maskFilePath ?? '$directory/mask.png',
  cutoutFilePath: cutoutFilePath ?? '$directory/cutout.png',
  metrics: metrics ?? fakeMetrics(),
  latency: latency,
);
