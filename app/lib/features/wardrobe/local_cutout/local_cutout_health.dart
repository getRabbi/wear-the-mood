/// One health model for local-first background removal (local BG §5).
///
/// The point of this file is that "we fell back to the cloud" is not a diagnosis.
/// Every one of the states below produced the same user-visible outcome — a garment
/// that took ~90 s instead of ~5 s — and the same green build, healthy API and
/// successful save. Collapsing them into a single boolean is precisely how a
/// release-wide outage stayed invisible for a full version:
///
///   * a compile-time gate silently off,
///   * a native channel that was never registered,
///   * a backend endpoint answering 404,
///   * an encoder that could not represent its own output,
///
/// all look identical to `cloudFallbackUsed == true`.
///
/// So the states stay distinct. The USER still gets a smooth fallback and never
/// sees any of these words; support and the dashboards keep the exact reason.
library;

import 'local_cutout_models.dart';

/// Why local-first removal is, or is not, working on this device right now.
///
/// Ordered roughly from healthy to broken. Everything except [enabledAndReady] and
/// [warmingModel] means the next add will use the cloud path.
enum LocalCutoutHealthState {
  /// The engine, its model and the channel are all ready.
  enabledAndReady,

  /// Android only: the `subject_segment` module is being fetched. Transient and
  /// expected on a fresh install — NOT a defect, and not something to alert on.
  warmingModel,

  /// The build never even asks: a compile-time gate is off. In production this is
  /// a RELEASE defect, not a device condition.
  gateDisabled,

  /// iOS below 17, or Android below API 24. A permanent property of the device;
  /// the correct behaviour is a cloud fallback, and the rate is a market fact
  /// rather than a problem to fix.
  unsupportedOs,

  /// Android only: no usable Google Play services (AOSP, de-Googled). There is
  /// nothing to download and nothing to fix.
  missingPlayServices,

  /// Android only: the model is not installed and preparation has not succeeded.
  /// Expected briefly after install; a high rate LONG after install is an alert.
  modelNotInstalled,

  /// The method channel is not registered. On a production build this can only
  /// mean the native engine was not compiled in or not registered — a release
  /// defect that must page, never a device condition.
  channelUnavailable,

  /// The native self-test failed: the encoder, the cache or the provider is
  /// broken on this build. The single highest-signal state here.
  nativeSelfTestFailed,

  /// A transient condition — busy, a one-off init failure, an unrecognised native
  /// state. Retryable.
  temporarilyUnavailable,

  /// The backend's emergency kill-switch is engaged. Deliberate and audited, but
  /// it must never be left on unnoticed.
  emergencyDisabled,

  /// The backend endpoint is missing or refusing (404/503). A server-side release
  /// or config defect, not a device one.
  backendUnavailable,

  /// Everything works; THIS image was refused on quality. The healthiest possible
  /// reason to fall back, and it must not be counted as an outage.
  healthyButImageRejected,
}

extension LocalCutoutHealthSeverity on LocalCutoutHealthState {
  /// True when the engine can be used for the next add.
  bool get isUsable => this == LocalCutoutHealthState.enabledAndReady;

  /// True when this state indicates something WE broke, as opposed to a property
  /// of the device or of one photo. These are the states that justify an alert.
  ///
  /// Deliberately narrow: paging on `unsupportedOs` would mean paging on the
  /// existence of iPhone 12s, and an alert that fires on normal conditions is an
  /// alert everyone learns to ignore.
  bool get isReleaseDefect => switch (this) {
    LocalCutoutHealthState.gateDisabled ||
    LocalCutoutHealthState.channelUnavailable ||
    LocalCutoutHealthState.nativeSelfTestFailed ||
    LocalCutoutHealthState.backendUnavailable => true,
    _ => false,
  };

  /// True when the condition is expected to clear on its own.
  bool get isTransient => switch (this) {
    LocalCutoutHealthState.warmingModel ||
    LocalCutoutHealthState.temporarilyUnavailable ||
    LocalCutoutHealthState.healthyButImageRejected => true,
    _ => false,
  };
}

/// The health of local removal plus the evidence behind it.
class LocalCutoutHealth {
  const LocalCutoutHealth({
    required this.state,
    this.engine,
    this.engineVersion = 'unknown',
    this.selfTest,
  });

  const LocalCutoutHealth.gateDisabled()
    : state = LocalCutoutHealthState.gateDisabled,
      engine = null,
      engineVersion = 'unknown',
      selfTest = null;

  final LocalCutoutHealthState state;
  final LocalCutoutEngine? engine;
  final String engineVersion;

  /// The last native self-test, when one has been run for this app version.
  final LocalCutoutSelfTestResult? selfTest;

  bool get isUsable => state.isUsable;

  /// The bounded fields safe to attach to any event (§6).
  Map<String, Object> toAnalyticsFields() => {
    'health': state.name,
    if (engine != null) 'engine': engine!.wireName,
    'self_test_state': selfTest?.state.name ?? 'not_run',
  };

  /// Derive health from a capability probe, so the screen and the telemetry agree
  /// on one mapping rather than each inventing their own.
  static LocalCutoutHealthState stateFor(
    LocalCutoutAvailability availability,
  ) => switch (availability) {
    LocalCutoutAvailability.available => LocalCutoutHealthState.enabledAndReady,
    LocalCutoutAvailability.unsupportedOs =>
      LocalCutoutHealthState.unsupportedOs,
    LocalCutoutAvailability.missingGooglePlayServices =>
      LocalCutoutHealthState.missingPlayServices,
    LocalCutoutAvailability.modelNotInstalled =>
      LocalCutoutHealthState.modelNotInstalled,
    LocalCutoutAvailability.modelDownloadFailed =>
      LocalCutoutHealthState.modelNotInstalled,
    LocalCutoutAvailability.temporarilyUnavailable =>
      LocalCutoutHealthState.temporarilyUnavailable,
  };

  /// Derive health from a fallback reason, so an add's outcome and the device's
  /// health are described in the same vocabulary.
  static LocalCutoutHealthState stateForReason(
    LocalCutoutFallbackReason reason,
  ) => switch (reason) {
    LocalCutoutFallbackReason.gateDisabled =>
      LocalCutoutHealthState.gateDisabled,
    LocalCutoutFallbackReason.unsupportedOs =>
      LocalCutoutHealthState.unsupportedOs,
    LocalCutoutFallbackReason.missingGooglePlayServices =>
      LocalCutoutHealthState.missingPlayServices,
    LocalCutoutFallbackReason.modelNotInstalled ||
    LocalCutoutFallbackReason.modelDownloadFailed =>
      LocalCutoutHealthState.modelNotInstalled,
    LocalCutoutFallbackReason.channelUnavailable =>
      LocalCutoutHealthState.channelUnavailable,
    LocalCutoutFallbackReason.backendUnavailable =>
      LocalCutoutHealthState.backendUnavailable,
    // The engine worked; this photo did not pass. Never an outage.
    LocalCutoutFallbackReason.noSubjectFound ||
    LocalCutoutFallbackReason.qualityRejected ||
    LocalCutoutFallbackReason.invalidOutput ||
    LocalCutoutFallbackReason.backendRejected =>
      LocalCutoutHealthState.healthyButImageRejected,
    LocalCutoutFallbackReason.temporarilyUnavailable ||
    LocalCutoutFallbackReason.timeout ||
    LocalCutoutFallbackReason.cancelled ||
    LocalCutoutFallbackReason.nativeError ||
    LocalCutoutFallbackReason.sourceMissing =>
      LocalCutoutHealthState.temporarilyUnavailable,
  };
}

/// What the native `selfTest` reported (§4).
///
/// Bounded, non-identifying fields only: no paths, no bytes, no user data. A
/// malformed or missing reply decodes to [LocalCutoutSelfTestState.unavailable]
/// rather than throwing — a self-test that can break the app is worse than none.
enum LocalCutoutSelfTestState {
  /// Encoder, cache and (where applicable) provider all verified.
  passed,

  /// The native side ran and reported a defect. See [LocalCutoutSelfTestResult.failureCode].
  failed,

  /// The channel is not registered, or the reply could not be decoded.
  unavailable,
}

class LocalCutoutSelfTestResult {
  const LocalCutoutSelfTestResult({
    required this.state,
    this.engine,
    this.engineVersion = 'unknown',
    this.channelVersion = 0,
    this.encoderOk = false,
    this.cacheOk = false,
    this.platformAvailable = false,
    this.modelAvailable = false,
    this.failureCode = 'unknown',
  });

  const LocalCutoutSelfTestResult.unavailable()
    : state = LocalCutoutSelfTestState.unavailable,
      engine = null,
      engineVersion = 'unknown',
      channelVersion = 0,
      encoderOk = false,
      cacheOk = false,
      platformAvailable = false,
      modelAvailable = false,
      failureCode = 'channel_unavailable';

  final LocalCutoutSelfTestState state;
  final LocalCutoutEngine? engine;
  final String engineVersion;
  final int channelVersion;

  /// The mask and cutout encoders round-tripped with alpha intact. The single most
  /// valuable bit here: both platforms have shipped an encoder that silently
  /// produced unusable output past a fully green test suite.
  final bool encoderOk;
  final bool cacheOk;

  /// Android: Google Play services usable. iOS: the OS supports Vision (17+).
  final bool platformAvailable;

  /// Android: the `subject_segment` module is installed and the segmenter
  /// initialised. iOS: the Vision fixture produced a structurally valid mask.
  final bool modelAvailable;

  /// Bounded native reason; `'none'` when nothing failed.
  final String failureCode;

  bool get passed => state == LocalCutoutSelfTestState.passed;

  Map<String, Object> toAnalyticsFields() => {
    'self_test_state': state.name,
    'self_test_failure': failureCode,
    'encoder_ok': encoderOk,
    'cache_ok': cacheOk,
    'platform_available': platformAvailable,
    'model_available': modelAvailable,
    'channel_version': channelVersion,
  };

  /// Decode the channel reply. Never throws; anything unexpected is `unavailable`.
  static LocalCutoutSelfTestResult fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const LocalCutoutSelfTestResult.unavailable();
    final status = map['status'];
    final state = switch (status) {
      'pass' => LocalCutoutSelfTestState.passed,
      'fail' => LocalCutoutSelfTestState.failed,
      _ => LocalCutoutSelfTestState.unavailable,
    };
    final version = map['engineVersion'];
    final failure = map['failureCode'];
    return LocalCutoutSelfTestResult(
      state: state,
      engine: LocalCutoutEngine.fromWireName(map['engine'] as String?),
      // Bound it here rather than trusting native not to over-share.
      engineVersion: version is String && version.isNotEmpty
          ? (version.length > 64 ? version.substring(0, 64) : version)
          : 'unknown',
      channelVersion: map['channelVersion'] is int
          ? map['channelVersion']! as int
          : 0,
      encoderOk: map['encoderOk'] == true,
      cacheOk: map['cacheOk'] == true,
      platformAvailable: map['platformAvailable'] == true,
      modelAvailable: map['modelAvailable'] == true,
      failureCode: failure is String && failure.isNotEmpty
          ? (failure.length > 48 ? failure.substring(0, 48) : failure)
          : 'unknown',
    );
  }
}
