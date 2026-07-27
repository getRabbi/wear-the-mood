/// The native bridge contract for local-first background removal (local BG §4, §8).
///
/// Phase 1 defines the CONTRACT only — channel name, method names, typed error
/// codes and the interface the orchestrator will program against. The Android
/// (Phase 3) and iOS (Phase 4) engines implement it; the tests use a fake. No
/// method channel is opened from this file.
///
/// Design rules the native side must honour:
///   * write the mask + cutout PNGs into a per-operation cache directory and
///     return PATHS, never large byte arrays over the channel;
///   * use random, non-identifying file and directory names;
///   * do all decode/inference/compositing/PNG work off the main thread;
///   * run at most one removal at a time per process;
///   * never log image bytes, mask bytes, or file paths that contain user ids;
///   * fail with one of [LocalCutoutErrorCode] — never an untyped throw.
library;

import 'dart:typed_data';

import 'local_cutout_models.dart';

/// The single method channel. Changing this string breaks every shipped build
/// that has a native engine — treat it as a wire contract.
const String kLocalCutoutChannel = 'wtm/background_removal';

/// Method names on [kLocalCutoutChannel].
abstract final class LocalCutoutMethod {
  /// `() -> Map` — what this device can do, before any image is handled.
  /// Must be cheap, must not download anything, must never throw.
  static const String capability = 'capability';

  /// `({int timeoutMs}) -> Map` — Android: ensure the `subject_segment` module is
  /// present, asking Play services for it if not. Bounded by `timeoutMs`; returns
  /// the resulting capability. A no-op returning the current capability on iOS.
  static const String prepare = 'prepare';

  /// `({Uint8List imageBytes, int timeoutMs}) -> Map` — segment the EXACT bytes
  /// that will be uploaded as the original, and write the two PNGs to cache.
  static const String removeBackground = 'removeBackground';

  /// `({String operationId}) -> void` — best-effort cancel of an in-flight run.
  static const String cancel = 'cancel';

  /// `({String operationId}) -> void` — delete one operation's cache directory.
  /// Idempotent: a missing directory is a success, never an error.
  static const String cleanup = 'cleanup';

  /// `({int maxAgeMs}) -> int` — delete operation directories older than
  /// `maxAgeMs` (crash/kill recovery) and return how many were removed.
  static const String sweepCache = 'sweepCache';
}

/// Stable error codes the native side returns as `PlatformException.code`.
///
/// These are a shipped contract: add values, never rename or repurpose them. An
/// unrecognised code maps to [LocalCutoutFallbackReason.nativeError] so a newer
/// native layer can never break an older Dart layer.
abstract final class LocalCutoutErrorCode {
  /// The OS/engine cannot do this at all (iOS < 17, Android < 24).
  static const String unsupported = 'unsupported';

  /// Google Play services missing or unusable (Android).
  static const String missingPlayServices = 'missing_play_services';

  /// The `subject_segment` module is not installed (Android).
  static const String modelNotInstalled = 'model_not_installed';

  /// An install was requested and did not complete (Android).
  static const String modelDownloadFailed = 'model_download_failed';

  /// The engine ran and found no foreground instance.
  static const String noSubject = 'no_subject';

  /// The engine produced something structurally unusable — undecodable source,
  /// zero dimensions, or a mask that does not match the source size.
  static const String invalidOutput = 'invalid_output';

  /// The native operation exceeded its own bound.
  static const String timeout = 'timeout';

  /// Cancelled by [LocalCutoutMethod.cancel] or by activity/engine teardown.
  static const String cancelled = 'cancelled';

  /// Another removal is already running (only one at a time is permitted).
  static const String busy = 'busy';

  /// Could not create/write the operation cache directory.
  static const String cacheUnavailable = 'cache_unavailable';

  /// Anything else the engine reported.
  static const String internal = 'internal';

  /// Maps a native code onto the reason the orchestrator records and reports.
  static LocalCutoutFallbackReason toFallbackReason(String? code) => switch (code) {
    unsupported => LocalCutoutFallbackReason.unsupportedOs,
    missingPlayServices => LocalCutoutFallbackReason.missingGooglePlayServices,
    modelNotInstalled => LocalCutoutFallbackReason.modelNotInstalled,
    modelDownloadFailed => LocalCutoutFallbackReason.modelDownloadFailed,
    noSubject => LocalCutoutFallbackReason.noSubjectFound,
    invalidOutput => LocalCutoutFallbackReason.invalidOutput,
    timeout => LocalCutoutFallbackReason.timeout,
    cancelled => LocalCutoutFallbackReason.cancelled,
    // Busy and a missing cache are both "try again later", not "this device
    // can't do it" — the distinction matters for the fallback-rate dashboards.
    busy || cacheUnavailable => LocalCutoutFallbackReason.temporarilyUnavailable,
    _ => LocalCutoutFallbackReason.nativeError,
  };
}

/// Raised by a platform implementation for a typed native failure. Carries no
/// image data and no user-identifying detail (§10).
class LocalCutoutPlatformException implements Exception {
  const LocalCutoutPlatformException(this.reason, {this.code});

  final LocalCutoutFallbackReason reason;

  /// The raw native code, kept for analytics; may be null when the channel
  /// itself was unavailable.
  final String? code;

  @override
  String toString() => 'LocalCutoutPlatformException(${reason.name}, code: $code)';
}

/// What the orchestrator programs against. One implementation talks to
/// [kLocalCutoutChannel] (Phase 3); tests supply a fake.
abstract class LocalCutoutPlatform {
  /// Cheap probe of this device's engine. Must never throw — an unreachable
  /// channel resolves to [LocalCutoutCapability.unsupported].
  Future<LocalCutoutCapability> capability();

  /// Android: make the segmentation model available, bounded by [timeout].
  /// iOS: returns the current capability unchanged. Must never throw.
  Future<LocalCutoutCapability> prepare({required Duration timeout});

  /// Segment [imageBytes] — the exact compressed JPEG that will be uploaded.
  ///
  /// Throws [LocalCutoutPlatformException] on any typed failure. A returned
  /// result is not yet trusted: the caller still validates the files and applies
  /// the quality policy.
  Future<LocalCutoutResult> removeBackground({
    required Uint8List imageBytes,
    required Duration timeout,
  });

  /// Best-effort cancel. Never throws.
  Future<void> cancel(String operationId);

  /// Delete one operation's cache directory. Idempotent; never throws.
  Future<void> cleanup(String operationId);

  /// Delete operation directories older than [maxAge]; returns how many went.
  /// Never throws.
  Future<int> sweepCache({required Duration maxAge});
}

/// The platform for a build with no native engine — every gate off, an
/// unsupported OS, or a unit test that has not installed a fake.
///
/// Everything is a safe no-op, so wiring this in can never change behaviour.
class UnsupportedLocalCutoutPlatform implements LocalCutoutPlatform {
  const UnsupportedLocalCutoutPlatform();

  @override
  Future<LocalCutoutCapability> capability() async =>
      const LocalCutoutCapability.unsupported();

  @override
  Future<LocalCutoutCapability> prepare({required Duration timeout}) async =>
      const LocalCutoutCapability.unsupported();

  @override
  Future<LocalCutoutResult> removeBackground({
    required Uint8List imageBytes,
    required Duration timeout,
  }) async => throw const LocalCutoutPlatformException(
    LocalCutoutFallbackReason.unsupportedOs,
    code: LocalCutoutErrorCode.unsupported,
  );

  @override
  Future<void> cancel(String operationId) async {}

  @override
  Future<void> cleanup(String operationId) async {}

  @override
  Future<int> sweepCache({required Duration maxAge}) async => 0;
}
