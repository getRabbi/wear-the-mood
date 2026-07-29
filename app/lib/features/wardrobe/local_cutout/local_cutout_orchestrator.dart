/// Decides whether a garment photo is cut out on the device or in the cloud
/// (local BG §9.1).
///
/// Everything platform-specific sits behind [LocalCutoutPlatform]; every threshold
/// sits in [LocalCutoutQualityPolicy]; the clock and the dimension reader are
/// injectable. So this class — the one that decides what the user experiences — is
/// fully unit-testable with no device, no engine and no network.
///
/// It never talks to a widget and never performs the upload or the save. It answers
/// exactly one question: *can we use a local cutout for these bytes, and if not,
/// why not.*
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/config/feature_gates.dart';
import 'local_cutout_cache.dart';
import 'local_cutout_models.dart';
import 'local_cutout_platform.dart';
import 'local_cutout_quality_policy.dart';

/// Reads the pixel dimensions of encoded image bytes without rasterising them.
typedef SourceDimensionsReader = Future<SourceDimensions?> Function(Uint8List bytes);

/// The dimensions of the compressed source, used to validate the native mask.
@immutable
class SourceDimensions {
  const SourceDimensions(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is SourceDimensions && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// The outcome of one local attempt.
@immutable
sealed class LocalCutoutAttempt {
  const LocalCutoutAttempt();
}

/// Usable local output. [warnings] are observational only — the result is kept.
final class LocalCutoutAccepted extends LocalCutoutAttempt {
  const LocalCutoutAccepted(this.result, this.warnings);

  final LocalCutoutResult result;
  final Set<LocalCutoutQualityWarning> warnings;
}

/// No local cutout. [reason] decides what happens next: everything except
/// [LocalCutoutFallbackReason.sourceMissing] routes to the existing cloud flow.
final class LocalCutoutRejected extends LocalCutoutAttempt {
  const LocalCutoutRejected(this.reason);

  final LocalCutoutFallbackReason reason;

  bool get canUseCloudFallback => reason.canUseCloudFallback;
}

class LocalCutoutOrchestrator {
  LocalCutoutOrchestrator({
    required LocalCutoutPlatform platform,
    LocalCutoutCache? cache,
    this.policy = kDefaultLocalCutoutQualityPolicy,
    SourceDimensionsReader? readDimensions,
    this.timeout = defaultTimeout,
    this.prepareTimeout = defaultPrepareTimeout,
    this.channelGrace = defaultChannelGrace,
    bool? masterEnabled,
    bool? androidEnabled,
    bool? iosEnabled,
    TargetPlatform? targetPlatform,
  }) : _platform = platform,
       _cache = cache ?? LocalCutoutCache(platform),
       _readDimensions = readDimensions ?? readEncodedDimensions,
       _masterEnabled = masterEnabled ?? kLocalBgRemovalEnabled,
       _androidEnabled = androidEnabled ?? kLocalBgAndroidEnabled,
       _iosEnabled = iosEnabled ?? kLocalBgIosEnabled,
       _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  /// Bounded so a wedged engine can never hold the Add Garment screen. Chosen well
  /// above the ~1.5 s P50 target but far below the cloud path's ~90 s, so falling
  /// back still beats waiting.
  static const Duration defaultTimeout = Duration(seconds: 20);

  /// Model preparation is best-effort and must never feel like a stall.
  static const Duration defaultPrepareTimeout = Duration(seconds: 12);

  /// Headroom over the native bound, so a native timeout — which carries a precise
  /// reason — wins the race against this generic backstop.
  static const Duration defaultChannelGrace = Duration(seconds: 5);

  final LocalCutoutPlatform _platform;
  final LocalCutoutCache _cache;
  final LocalCutoutQualityPolicy policy;
  final SourceDimensionsReader _readDimensions;
  final Duration timeout;
  final Duration prepareTimeout;
  final Duration channelGrace;
  final bool _masterEnabled;
  final bool _androidEnabled;
  final bool _iosEnabled;
  final TargetPlatform _targetPlatform;

  /// True when this build may even ask the device. Cheap and synchronous, so the
  /// screen can decide which copy to show before any await.
  bool get isEnabledForThisBuild {
    if (!_masterEnabled) return false;
    return switch (_targetPlatform) {
      TargetPlatform.android => _androidEnabled,
      TargetPlatform.iOS => _iosEnabled,
      _ => false,
    };
  }

  /// Best-effort model preparation, for the authenticated/closet lifecycle rather
  /// than the add path (§8.2): on Android this lets Play services fetch the
  /// segmentation model in the background so the first add does not wait on it.
  /// iOS has nothing to download. Never throws.
  Future<LocalCutoutAvailability> prepare() async {
    if (!isEnabledForThisBuild) return LocalCutoutAvailability.unsupportedOs;
    try {
      final capability = await _platform.prepare(timeout: prepareTimeout);
      return capability.availability;
    } on Object {
      return LocalCutoutAvailability.temporarilyUnavailable;
    }
  }

  /// Try to cut out [bytes] on the device.
  ///
  /// [bytes] MUST be the exact compressed JPEG that will be uploaded as the
  /// original — never a re-read or re-encode — or the mask will not line up with
  /// what the backend stores (§8.1).
  ///
  /// Never throws. Every failure is a typed [LocalCutoutRejected], and any
  /// temporary files are removed before returning.
  Future<LocalCutoutAttempt> attempt(Uint8List bytes) async {
    if (!isEnabledForThisBuild) {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.gateDisabled);
    }
    if (bytes.isEmpty) {
      // No usable source at all: the cloud worker would have nothing either.
      return const LocalCutoutRejected(LocalCutoutFallbackReason.sourceMissing);
    }

    final capability = await _capability();
    if (capability != LocalCutoutAvailability.available) {
      return LocalCutoutRejected(fallbackReasonFor(capability));
    }

    // Read the source dimensions BEFORE inference: without them the mask cannot be
    // validated, and an unreadable source is not worth an expensive engine call.
    final SourceDimensions? source;
    try {
      source = await _readDimensions(bytes);
    } on Object {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.invalidOutput);
    }
    if (source == null || source.width <= 0 || source.height <= 0) {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.invalidOutput);
    }

    LocalCutoutResult result;
    try {
      result = await _platform
          .removeBackground(imageBytes: bytes, timeout: timeout)
          // Belt and braces over the native bound: a channel that never replies
          // must not hold the screen open.
          .timeout(timeout + channelGrace);
    } on LocalCutoutPlatformException catch (error) {
      return LocalCutoutRejected(error.reason);
    } on TimeoutException {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.timeout);
    } on Object {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.nativeError);
    }

    final verdict = policy.evaluate(
      result.metrics,
      sourceWidth: source.width,
      sourceHeight: source.height,
    );
    if (!verdict.isAccepted) {
      // The engine's own scratch files are useless now.
      await discard(result.operationId);
      return LocalCutoutRejected(
        verdict.rejection ?? LocalCutoutFallbackReason.qualityRejected,
      );
    }
    return LocalCutoutAccepted(result, verdict.warnings);
  }

  /// Delete one operation's files. Call on every terminal path — success after the
  /// save completes, failure, cancellation, and widget disposal.
  Future<void> discard(String? operationId) =>
      _cache.disposeOperation(operationId).then((_) {});

  /// Best-effort cancel of an in-flight native operation, so a disposed screen does
  /// not leave the engine grinding on work nobody will read. Never throws.
  void cancel(String operationId) {
    unawaited(_platform.cancel(operationId).catchError((_) {}));
  }

  /// Clear anything a previous session's crash orphaned. Call once after the closet
  /// is ready, never on the add path.
  Future<int> sweepStaleCache() => _cache.sweepStale();

  Future<LocalCutoutAvailability> _capability() async {
    try {
      final capability = await _platform.capability();
      if (capability.isAvailable) return LocalCutoutAvailability.available;
      // Android may simply not have fetched the model yet: one bounded attempt to
      // prepare it, then take whatever answer comes back.
      if (capability.availability == LocalCutoutAvailability.modelNotInstalled) {
        final prepared = await _platform.prepare(timeout: prepareTimeout);
        return prepared.isAvailable
            ? LocalCutoutAvailability.available
            : prepared.availability;
      }
      return capability.availability;
    } on LocalCutoutPlatformException catch (error) {
      return switch (error.reason) {
        LocalCutoutFallbackReason.unsupportedOs => LocalCutoutAvailability.unsupportedOs,
        LocalCutoutFallbackReason.missingGooglePlayServices =>
          LocalCutoutAvailability.missingGooglePlayServices,
        LocalCutoutFallbackReason.modelNotInstalled =>
          LocalCutoutAvailability.modelNotInstalled,
        LocalCutoutFallbackReason.modelDownloadFailed =>
          LocalCutoutAvailability.modelDownloadFailed,
        // channelUnavailable included: a build with no native engine is simply an
        // unsupported device from the user's point of view.
        _ => LocalCutoutAvailability.temporarilyUnavailable,
      };
    } on Object {
      return LocalCutoutAvailability.temporarilyUnavailable;
    }
  }

  /// Header-only dimension read — no full raster, so a 1600px JPEG costs almost
  /// nothing. Returns null when the bytes are not a decodable image.
  static Future<SourceDimensions?> readEncodedDimensions(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) return null;
      return SourceDimensions(width, height);
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
