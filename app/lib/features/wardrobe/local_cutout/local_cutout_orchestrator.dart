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
import 'local_cutout_health.dart';
import 'local_cutout_models.dart';
import 'local_cutout_platform.dart';
import 'local_cutout_quality_policy.dart';

/// Reads the pixel dimensions of encoded image bytes without rasterising them.
typedef SourceDimensionsReader =
    Future<SourceDimensions?> Function(Uint8List bytes);

/// The dimensions of the compressed source, used to validate the native mask.
@immutable
class SourceDimensions {
  const SourceDimensions(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is SourceDimensions &&
      other.width == width &&
      other.height == height;

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
  const LocalCutoutRejected(this.reason, {this.diagnosticOperationId});

  final LocalCutoutFallbackReason reason;

  /// INTERNAL BUILDS ONLY (iOS Phase 3). The operation whose evidence was
  /// deliberately KEPT so a tester can export it. Null in every production build,
  /// where a failed operation's files are swept immediately as before.
  ///
  /// Its presence is what lets Add Garment surface the exact local failure instead
  /// of silently falling through to the cloud — the whole point of a diagnostic
  /// session.
  final String? diagnosticOperationId;

  bool get canUseCloudFallback => reason.canUseCloudFallback;

  /// True when there is preserved evidence a tester could export.
  bool get hasExportableDiagnostics => diagnosticOperationId != null;
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
    bool? diagnosticsEnabled,
    TargetPlatform? targetPlatform,
  }) : _platform = platform,
       _cache = cache ?? LocalCutoutCache(platform),
       _readDimensions = readDimensions ?? readEncodedDimensions,
       _masterEnabled = masterEnabled ?? kLocalBgRemovalEnabled,
       _androidEnabled = androidEnabled ?? kLocalBgAndroidEnabled,
       _iosEnabled = iosEnabled ?? kLocalBgIosEnabled,
       _diagnosticsEnabled =
           diagnosticsEnabled ?? kLocalBgIosDiagnosticsEnabled,
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

  /// The self-test does one real Vision inference on a small fixture. Generous for
  /// a cold first run, bounded so it can never hold anything open.
  static const Duration selfTestTimeout = Duration(seconds: 25);

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
  final bool _diagnosticsEnabled;
  final TargetPlatform _targetPlatform;

  /// Process-lifetime caches. Both exist to stop a screen rebuild turning into
  /// repeated Play-services calls or repeated Vision inferences (§4, §10).
  LocalCutoutAvailability? _preparedAvailability;
  LocalCutoutSelfTestResult? _lastSelfTest;
  bool _preparationRequested = false;
  bool _urgentPrepareAttempted = false;

  /// THE preparation for this process, shared by every caller.
  ///
  /// The whole first-run defect lived in this gap: [prepare] existed to warm the
  /// model after sign-in and nothing ever called it, so the FIRST Add Garment
  /// discovered a missing model with the user standing in front of it. Holding
  /// the in-flight future here means the startup warm-up and the add path are
  /// the same operation — an add that arrives mid-download waits for the
  /// download that is already running rather than starting a second one.
  Future<LocalCutoutAvailability>? _preparation;
  bool _preparing = false;

  /// True while [ensureReady] has work IN FLIGHT, so the screen can say
  /// "Preparing image tools…" honestly instead of looking stalled. Tracked
  /// separately from [_preparation], which outlives the call when the result
  /// was positive and is cached for the process.
  bool get isPreparing => _preparing;

  /// True when the engine is known-ready and an attempt will not wait.
  bool get isReady =>
      _preparedAvailability == LocalCutoutAvailability.available;

  /// Make the engine ready, at most once at a time.
  ///
  /// Idempotent by construction: a positive result is cached for the process, an
  /// in-flight preparation is shared, and a NEGATIVE result deliberately clears
  /// the handle so a download that failed once (no network at sign-in, say) is
  /// retried on the next add rather than written off for the life of the
  /// process. Never throws.
  Future<LocalCutoutAvailability> ensureReady() {
    if (!isEnabledForThisBuild) {
      return Future.value(LocalCutoutAvailability.unsupportedOs);
    }
    if (isReady) return Future.value(LocalCutoutAvailability.available);
    return _preparation ??= _prepareOnce();
  }

  Future<LocalCutoutAvailability> _prepareOnce() async {
    _preparing = true;
    try {
      return await prepare();
    } finally {
      _preparing = false;
      // Existing awaiters already hold the future; clearing the handle only
      // affects who starts the NEXT one.
      if (!isReady) _preparation = null;
    }
  }

  /// Warm the engine and clear anything a previous session's crash orphaned.
  ///
  /// Call once after authentication, off the first frame. Best-effort and fully
  /// swallowed: app start must never wait on, or be broken by, a model download.
  Future<void> warmUp() async {
    if (!isEnabledForThisBuild) return;
    try {
      await ensureReady();
    } on Object {
      // ensureReady already swallows; belt and braces.
    }
    try {
      await sweepStaleCache();
    } on Object {
      // Housekeeping. A failure here changes nothing the user can see.
    }
  }

  /// [attempt], but only once the engine is actually ready.
  ///
  /// This is what the add path should call. It waits for the shared preparation
  /// (rather than racing it), and on a transient READINESS failure it retries
  /// the analysis exactly once after confirming the engine came up.
  ///
  /// The retry is the on-device segmentation ONLY. The upload runs on its own
  /// future alongside this, no job is created here and no credit is spent here,
  /// so a retry can never duplicate an upload, a try-on job or a charge.
  Future<LocalCutoutAttempt> attemptWhenReady(Uint8List bytes) async {
    if (!isEnabledForThisBuild) {
      return const LocalCutoutRejected(LocalCutoutFallbackReason.gateDisabled);
    }
    await ensureReady();
    final first = await attempt(bytes);
    if (first is! LocalCutoutRejected || !_isReadinessTransient(first.reason)) {
      return first;
    }
    // The engine was not up when we asked. If it is up NOW — the common
    // first-install case, where the module landed while we were working — one
    // more try beats sending a perfectly capable device to the cloud.
    final availability = await ensureReady();
    if (availability != LocalCutoutAvailability.available) return first;
    return attempt(bytes);
  }

  /// Reasons that mean "the engine was not ready", as opposed to "the engine ran
  /// and this photo did not work out". Only the former is worth one retry —
  /// retrying a quality rejection or a missing subject would just cost time.
  static bool _isReadinessTransient(LocalCutoutFallbackReason reason) =>
      reason == LocalCutoutFallbackReason.modelNotInstalled ||
      reason == LocalCutoutFallbackReason.modelDownloadFailed ||
      reason == LocalCutoutFallbackReason.temporarilyUnavailable;

  /// True only in an internal iOS diagnostic build: the feature must be on for this
  /// platform AND diagnostics compiled in. Android never reaches this — its engine
  /// ignores the flag, and there is nothing to diagnose there.
  bool get diagnosticsAvailable =>
      isEnabledForThisBuild &&
      _diagnosticsEnabled &&
      _targetPlatform == TargetPlatform.iOS;

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
  ///
  /// The result is cached for the process so entering the closet repeatedly cannot
  /// turn into a request-per-rebuild storm against Play services (§4). A NEGATIVE
  /// result is deliberately not cached forever: a download that failed once should
  /// be retried on the next add, not written off for the life of the process.
  Future<LocalCutoutAvailability> prepare() async {
    if (!isEnabledForThisBuild) return LocalCutoutAvailability.unsupportedOs;
    final cached = _preparedAvailability;
    if (cached == LocalCutoutAvailability.available) return cached!;
    _preparationRequested = true;
    try {
      final capability = await _platform.prepare(timeout: prepareTimeout);
      if (capability.availability == LocalCutoutAvailability.available) {
        _preparedAvailability = capability.availability;
      }
      return capability.availability;
    } on Object {
      return LocalCutoutAvailability.temporarilyUnavailable;
    }
  }

  /// What state local removal is in on this device, without processing anything.
  ///
  /// Cheap: one capability probe plus whatever the self-test already reported. The
  /// screen uses it to decide what to say; the telemetry uses it so a fallback
  /// carries a REASON rather than just the fact that it happened (§5).
  Future<LocalCutoutHealth> health() async {
    if (!isEnabledForThisBuild) {
      // On a production build this is not a device condition, it is a release
      // defect — the gate was compiled off in an artifact that should have had it on.
      return const LocalCutoutHealth.gateDisabled();
    }
    final selfTest = _lastSelfTest;
    if (selfTest != null && selfTest.state == LocalCutoutSelfTestState.failed) {
      return LocalCutoutHealth(
        state: LocalCutoutHealthState.nativeSelfTestFailed,
        engine: selfTest.engine,
        engineVersion: selfTest.engineVersion,
        selfTest: selfTest,
      );
    }
    final LocalCutoutCapability capability;
    try {
      capability = await _platform.capability();
    } on LocalCutoutPlatformException catch (error) {
      return LocalCutoutHealth(
        state: error.reason == LocalCutoutFallbackReason.channelUnavailable
            ? LocalCutoutHealthState.channelUnavailable
            : LocalCutoutHealthState.temporarilyUnavailable,
        selfTest: selfTest,
      );
    } on Object {
      return LocalCutoutHealth(
        state: LocalCutoutHealthState.temporarilyUnavailable,
        selfTest: selfTest,
      );
    }
    var state = LocalCutoutHealth.stateFor(capability.availability);
    // A model that is on its way is "warming", not "missing": distinguishing them
    // is what keeps a normal first-run from looking like an outage on a dashboard.
    if (state == LocalCutoutHealthState.modelNotInstalled &&
        _preparationRequested) {
      state = LocalCutoutHealthState.warmingModel;
    }
    return LocalCutoutHealth(
      state: state,
      engine: capability.engine,
      engineVersion: capability.engineVersion,
      selfTest: selfTest,
    );
  }

  /// Run the native contract self-test at most once per process (§4).
  ///
  /// Deliberately NOT called on launch: it performs one real Vision inference on
  /// iOS, and paying that on every cold start to answer a question whose answer
  /// only changes with an app update would be indefensible. The caller runs it when
  /// the closet is ready, and persists the verdict per app version.
  Future<LocalCutoutSelfTestResult> selfTest() async {
    if (!isEnabledForThisBuild) {
      return const LocalCutoutSelfTestResult.unavailable();
    }
    final cached = _lastSelfTest;
    if (cached != null) return cached;
    final result = await _platform.selfTest(timeout: selfTestTimeout);
    _lastSelfTest = result;
    return result;
  }

  /// The most recent self-test verdict, if one has run in this process.
  LocalCutoutSelfTestResult? get lastSelfTest => _lastSelfTest;

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

    final capture = diagnosticsAvailable;
    LocalCutoutResult result;
    try {
      result = await _platform
          .removeBackground(
            imageBytes: bytes,
            timeout: timeout,
            captureDiagnostics: capture,
          )
          // Belt and braces over the native bound: a channel that never replies
          // must not hold the screen open.
          .timeout(timeout + channelGrace);
    } on LocalCutoutPlatformException catch (error) {
      // On a diagnostic build the native side preserved this operation's evidence
      // and told us its id, so the failure can be surfaced and exported rather than
      // silently becoming a cloud fallback.
      return LocalCutoutRejected(
        error.reason,
        diagnosticOperationId: capture ? error.diagnosticOperationId : null,
      );
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
      final reason =
          verdict.rejection ?? LocalCutoutFallbackReason.qualityRejected;
      if (capture) {
        // KEEP the scratch files. A quality rejection is one of the most useful
        // things to inspect on a device — the mask exists and can be looked at, and
        // discarding it would leave only a reason code. The tester exports, then the
        // screen discards on dismissal like any other terminal path.
        return LocalCutoutRejected(
          reason,
          diagnosticOperationId: result.operationId,
        );
      }
      // The engine's own scratch files are useless now.
      await discard(result.operationId);
      return LocalCutoutRejected(reason);
    }
    return LocalCutoutAccepted(result, verdict.warnings);
  }

  /// Share one operation's diagnostic bundle through the iOS share sheet.
  ///
  /// INTERNAL BUILDS ONLY, and safe to call regardless: on any build without
  /// diagnostics this returns [LocalCutoutExportOutcome.unavailable] without
  /// touching the native side. Never throws.
  Future<LocalCutoutExportOutcome> exportDiagnostics(
    String? operationId,
  ) async {
    if (!diagnosticsAvailable || operationId == null) {
      return LocalCutoutExportOutcome.unavailable;
    }
    return _platform.exportDiagnostics(operationId);
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
      if (capability.isAvailable) {
        _preparedAvailability = LocalCutoutAvailability.available;
        return LocalCutoutAvailability.available;
      }
      // Android may simply not have fetched the model yet. The user is standing in
      // Add Garment with a photo selected, so this ONE attempt is urgent — the
      // deferred install that runs after sign-in is the polite path, and if it has
      // not landed by now waiting politely again just means another cloud fallback.
      // Exactly one attempt per add, bounded; on failure we take the answer and go
      // to the cloud rather than retrying in a loop (§4.5).
      if (capability.availability ==
              LocalCutoutAvailability.modelNotInstalled &&
          !_urgentPrepareAttempted) {
        _urgentPrepareAttempted = true;
        final prepared = await _platform.prepare(
          timeout: prepareTimeout,
          urgent: true,
        );
        if (prepared.isAvailable) {
          _preparedAvailability = LocalCutoutAvailability.available;
          return LocalCutoutAvailability.available;
        }
        return prepared.availability;
      }
      return capability.availability;
    } on LocalCutoutPlatformException catch (error) {
      return switch (error.reason) {
        LocalCutoutFallbackReason.unsupportedOs =>
          LocalCutoutAvailability.unsupportedOs,
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
  static Future<SourceDimensions?> readEncodedDimensions(
    Uint8List bytes,
  ) async {
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
