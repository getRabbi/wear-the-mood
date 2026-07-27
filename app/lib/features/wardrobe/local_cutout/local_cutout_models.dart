/// Canonical contract for local-first background removal (local BG §4).
///
/// One shared shape for both engines — Apple Vision on iOS 17+ and Google ML Kit
/// Subject Segmentation on Android 24+ — so the orchestrator, the quality policy
/// and the tests never branch on platform.
///
/// Deliberately dependency-free and immutable: these types are pure data, decoded
/// from the `wtm/background_removal` method channel and unit-testable without a
/// device, a model, or a running Flutter engine.
library;

import 'dart:ui' show Rect;

/// Whether local removal can run on THIS device right now.
///
/// Anything other than [available] is a normal, expected outcome that routes the
/// add to the existing Azure BiRefNet flow — never an error the user sees.
enum LocalCutoutAvailability {
  /// The engine and its model are ready; local removal may be attempted.
  available,

  /// iOS below 17, or Android below API 24 — the OS lacks the API entirely.
  unsupportedOs,

  /// Android only: Google Play services is missing or unusable (e.g. an AOSP or
  /// de-Googled device). The segmentation model is delivered by Play services, so
  /// there is nothing to download.
  missingGooglePlayServices,

  /// Android only: the `subject_segment` module has not been installed yet. The
  /// install-time manifest metadata usually handles this; when it has not landed
  /// we ask for it and fall back for this one add.
  modelNotInstalled,

  /// Android only: an install was requested and did not complete (no network,
  /// storage pressure, Play services error).
  modelDownloadFailed,

  /// A transient condition — another removal is in flight, the engine failed to
  /// initialise once, or the platform reported a recoverable error. Retryable
  /// later; this add uses the cloud path.
  temporarilyUnavailable,
}

/// Which on-device engine produced a result.
enum LocalCutoutEngine {
  /// Apple Vision `VNGenerateForegroundInstanceMaskRequest` (iOS 17+).
  appleVision,

  /// Google ML Kit Subject Segmentation (Android, Play services).
  googleMlKit;

  /// The value sent to the backend as `engine=` — a stable wire string that must
  /// not change once shipped (§13: never break a shipped contract).
  String get wireName => switch (this) {
    LocalCutoutEngine.appleVision => 'apple_vision',
    LocalCutoutEngine.googleMlKit => 'google_mlkit',
  };

  static LocalCutoutEngine? fromWireName(String? value) => switch (value) {
    'apple_vision' => LocalCutoutEngine.appleVision,
    'google_mlkit' => LocalCutoutEngine.googleMlKit,
    _ => null,
  };
}

/// Why a local attempt did not end in a persisted local cutout.
///
/// Every value routes to the same place — the existing BiRefNet flow — but they
/// are kept distinct because the *rate* of each is the signal that tells us
/// whether local removal is actually working in the field (§10). Never surfaced
/// to the user as an error.
enum LocalCutoutFallbackReason {
  /// A compile-time gate is off. The overwhelmingly common case pre-rollout.
  gateDisabled,

  /// [LocalCutoutAvailability.unsupportedOs].
  unsupportedOs,

  /// [LocalCutoutAvailability.missingGooglePlayServices].
  missingGooglePlayServices,

  /// [LocalCutoutAvailability.modelNotInstalled].
  modelNotInstalled,

  /// [LocalCutoutAvailability.modelDownloadFailed].
  modelDownloadFailed,

  /// [LocalCutoutAvailability.temporarilyUnavailable].
  temporarilyUnavailable,

  /// The engine ran and found nothing to cut out.
  noSubjectFound,

  /// The engine returned success but the files/dimensions are unusable — missing,
  /// empty, zero-sized, or a mask that does not match the cutout.
  invalidOutput,

  /// Structurally valid output that failed a HARD quality bound (§5.1).
  qualityRejected,

  /// The bounded local timeout elapsed.
  timeout,

  /// The user backed out, or the widget was disposed mid-run.
  cancelled,

  /// The native side raised an untyped/unexpected error.
  nativeError,

  /// The method channel is not registered — an engine-less build, or a platform
  /// we have not implemented. Must never crash the add.
  channelUnavailable,

  /// The backend refused the mask (validation). The original is already uploaded,
  /// so the cloud create reuses the very same object key.
  backendRejected,

  /// The backend gate is off or private storage is unavailable (404/503).
  backendUnavailable,
}

/// Safe, non-identifying measurements of one local removal.
///
/// Ratios are `0.0..1.0`. Nothing here is trusted for security — the server
/// re-derives dimensions and coverage from the bytes it stores (§5). These exist
/// to drive the quality policy and bucketed analytics.
class LocalCutoutMetrics {
  const LocalCutoutMetrics({
    required this.width,
    required this.height,
    required this.subjectCount,
    required this.foregroundAreaRatio,
    required this.borderForegroundRatio,
    required this.uncertainPixelRatio,
    required this.meanForegroundConfidence,
    this.foregroundBounds,
  });

  /// Mask dimensions, which must equal the compressed source's.
  final int width;
  final int height;

  /// How many separate foreground instances the engine found.
  final int subjectCount;

  /// Mean alpha across the mask — how much of the frame the garment covers.
  final double foregroundAreaRatio;

  /// Share of the 1px image border that is foreground. High values mean the
  /// subject is cropped or the mask leaked into the background.
  final double borderForegroundRatio;

  /// Share of pixels at genuinely intermediate alpha. Expected to be non-trivial
  /// for lace, chiffon and hair — a soft edge is a feature, not a defect.
  final double uncertainPixelRatio;

  /// Mean confidence over foreground pixels, as reported by the engine.
  final double meanForegroundConfidence;

  /// Union bounding box of all subjects, in pixels, if the engine reported one.
  final Rect? foregroundBounds;

  /// Every ratio is a real number in `0..1` and the dimensions are positive.
  /// A NaN or infinity anywhere is a hard rejection (§5.1) — a metric that
  /// cannot be reasoned about must not be reasoned about.
  bool get isWellFormed =>
      width > 0 &&
      height > 0 &&
      subjectCount >= 0 &&
      _isRatio(foregroundAreaRatio) &&
      _isRatio(borderForegroundRatio) &&
      _isRatio(uncertainPixelRatio) &&
      _isRatio(meanForegroundConfidence);

  static bool _isRatio(double v) => v.isFinite && v >= 0.0 && v <= 1.0;

  /// Decodes the channel payload. Returns null when a required field is missing
  /// or the wrong type, so a malformed native reply is a typed fallback rather
  /// than a crash.
  static LocalCutoutMetrics? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final width = _int(map['width']);
    final height = _int(map['height']);
    final subjectCount = _int(map['subjectCount']);
    final area = _double(map['foregroundAreaRatio']);
    final border = _double(map['borderForegroundRatio']);
    final uncertain = _double(map['uncertainPixelRatio']);
    final confidence = _double(map['meanForegroundConfidence']);
    if (width == null ||
        height == null ||
        subjectCount == null ||
        area == null ||
        border == null ||
        uncertain == null ||
        confidence == null) {
      return null;
    }
    return LocalCutoutMetrics(
      width: width,
      height: height,
      subjectCount: subjectCount,
      foregroundAreaRatio: area,
      borderForegroundRatio: border,
      uncertainPixelRatio: uncertain,
      meanForegroundConfidence: confidence,
      foregroundBounds: _rect(map['foregroundBounds']),
    );
  }

  /// The bucketed, non-identifying form sent to analytics (§10). Never carries
  /// exact pixel counts that could fingerprint a specific photo.
  Map<String, Object?> toAnalyticsFields() => {
    'subject_count': subjectCount.clamp(0, 10),
    'foreground_area_bucket': _bucket(foregroundAreaRatio),
    'uncertain_pixel_bucket': _bucket(uncertainPixelRatio),
    'border_contact_bucket': _bucket(borderForegroundRatio),
    'size_bucket': _sizeBucket(width, height),
  };

  static String _bucket(double ratio) {
    if (ratio < 0.05) return '0-5';
    if (ratio < 0.25) return '5-25';
    if (ratio < 0.50) return '25-50';
    if (ratio < 0.75) return '50-75';
    if (ratio < 0.95) return '75-95';
    return '95-100';
  }

  static String _sizeBucket(int width, int height) {
    final longEdge = width > height ? width : height;
    if (longEdge <= 800) return 'le800';
    if (longEdge <= 1200) return 'le1200';
    if (longEdge <= 1600) return 'le1600';
    return 'gt1600';
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

  static double? _double(Object? v) => v is double ? v : (v is num ? v.toDouble() : null);

  static Rect? _rect(Object? v) {
    if (v is! Map) return null;
    final left = _double(v['left']);
    final top = _double(v['top']);
    final right = _double(v['right']);
    final bottom = _double(v['bottom']);
    if (left == null || top == null || right == null || bottom == null) return null;
    if (![left, top, right, bottom].every((d) => d.isFinite)) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// A successful local removal: two files on disk plus what we measured.
///
/// The native side writes the PNGs into a per-operation cache directory and
/// returns PATHS — never two large byte arrays over the channel (§4).
///
/// Note what is deliberately absent: the operation DIRECTORY. Dart reads the two
/// files (preview + mask upload) but is never given a path to delete. Cleanup goes
/// back over the channel as [operationId], which native re-validates and resolves
/// inside its own cache root — see `local_cutout_cache.dart` (blocker R10b).
class LocalCutoutResult {
  const LocalCutoutResult({
    required this.engine,
    required this.engineVersion,
    required this.operationId,
    required this.maskFilePath,
    required this.cutoutFilePath,
    required this.metrics,
    required this.latency,
  });

  /// Which engine produced this.
  final LocalCutoutEngine engine;

  /// Bounded, non-identifying engine/OS version string for observability.
  final String engineVersion;

  /// Random, non-identifying id for this run. The ONLY handle Dart may use to ask
  /// for these files to be deleted.
  final String operationId;

  /// Lossless grayscale/alpha PNG at full source dimensions. Uploaded to the
  /// backend, which re-composites the cutout from the stored original.
  final String maskFilePath;

  /// Transparent PNG at full source dimensions — the instant local preview.
  /// Never uploaded; the server's own composite is authoritative.
  final String cutoutFilePath;

  final LocalCutoutMetrics metrics;

  /// Wall-clock time the native call took.
  final Duration latency;

  /// Decodes the channel payload; null when anything required is missing or
  /// malformed, which the caller treats as [LocalCutoutFallbackReason.invalidOutput].
  static LocalCutoutResult? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final engine = LocalCutoutEngine.fromWireName(map['engine'] as String?);
    final operationId = map['operationId'];
    final mask = map['maskFilePath'];
    final cutout = map['cutoutFilePath'];
    final metrics = LocalCutoutMetrics.fromMap(map['metrics'] as Map<Object?, Object?>?);
    if (engine == null ||
        operationId is! String ||
        operationId.isEmpty ||
        mask is! String ||
        mask.isEmpty ||
        cutout is! String ||
        cutout.isEmpty ||
        metrics == null) {
      return null;
    }
    final latencyMs = LocalCutoutMetrics._int(map['latencyMs']) ?? 0;
    final version = map['engineVersion'];
    return LocalCutoutResult(
      engine: engine,
      // Bound it here rather than trusting the native side not to over-share.
      engineVersion: version is String
          ? (version.length > 64 ? version.substring(0, 64) : version)
          : 'unknown',
      operationId: operationId,
      maskFilePath: mask,
      cutoutFilePath: cutout,
      metrics: metrics,
      latency: Duration(milliseconds: latencyMs < 0 ? 0 : latencyMs),
    );
  }
}

/// What the platform reports about this device, before any image is processed.
class LocalCutoutCapability {
  const LocalCutoutCapability({
    required this.availability,
    this.engine,
    this.engineVersion = 'unknown',
  });

  /// A device with no engine at all — the safe default and the value used when
  /// the method channel is not registered.
  const LocalCutoutCapability.unsupported()
    : availability = LocalCutoutAvailability.unsupportedOs,
      engine = null,
      engineVersion = 'unknown';

  final LocalCutoutAvailability availability;
  final LocalCutoutEngine? engine;
  final String engineVersion;

  bool get isAvailable =>
      availability == LocalCutoutAvailability.available && engine != null;

  static LocalCutoutCapability fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const LocalCutoutCapability.unsupported();
    final availability = _availabilityFromWire(map['availability'] as String?);
    final version = map['engineVersion'];
    return LocalCutoutCapability(
      availability: availability,
      engine: LocalCutoutEngine.fromWireName(map['engine'] as String?),
      engineVersion: version is String && version.isNotEmpty
          ? (version.length > 64 ? version.substring(0, 64) : version)
          : 'unknown',
    );
  }

  static LocalCutoutAvailability _availabilityFromWire(String? value) => switch (value) {
    'available' => LocalCutoutAvailability.available,
    'unsupported_os' => LocalCutoutAvailability.unsupportedOs,
    'missing_google_play_services' => LocalCutoutAvailability.missingGooglePlayServices,
    'model_not_installed' => LocalCutoutAvailability.modelNotInstalled,
    'model_download_failed' => LocalCutoutAvailability.modelDownloadFailed,
    // Anything unrecognised is treated as a transient condition rather than a
    // permanent one: a future native version can add a value without this build
    // deciding the device is broken forever.
    _ => LocalCutoutAvailability.temporarilyUnavailable,
  };
}

/// Maps an availability onto the fallback reason it produces.
LocalCutoutFallbackReason fallbackReasonFor(LocalCutoutAvailability availability) =>
    switch (availability) {
      LocalCutoutAvailability.available => LocalCutoutFallbackReason.temporarilyUnavailable,
      LocalCutoutAvailability.unsupportedOs => LocalCutoutFallbackReason.unsupportedOs,
      LocalCutoutAvailability.missingGooglePlayServices =>
        LocalCutoutFallbackReason.missingGooglePlayServices,
      LocalCutoutAvailability.modelNotInstalled => LocalCutoutFallbackReason.modelNotInstalled,
      LocalCutoutAvailability.modelDownloadFailed =>
        LocalCutoutFallbackReason.modelDownloadFailed,
      LocalCutoutAvailability.temporarilyUnavailable =>
        LocalCutoutFallbackReason.temporarilyUnavailable,
    };
