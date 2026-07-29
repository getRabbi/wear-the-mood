/// Safe observability for local-first background removal (local BG §10).
///
/// THE RULE: buckets and bounded enums only. Nothing here may carry image or mask
/// bytes, a filesystem path, a filename, an object key, a signed URL, an access
/// token, EXIF/user metadata, a raw native exception description, or an exact pixel
/// dimension where the contract calls for a bucket. Nothing here may infer anything
/// about the *content* of a user's photo.
///
/// The payload builders are pure functions so a test can assert what is present —
/// and, more importantly, what is absent.
library;

import '../../../core/network/api_exception.dart';
import 'local_cutout_models.dart';
import 'local_cutout_quality_policy.dart';

/// Event names — `noun_verb`, snake_case, matching the CLAUDE.md §15 taxonomy.
abstract final class LocalCutoutEvents {
  static const prepareStarted = 'local_bg_prepare_started';
  static const prepareReady = 'local_bg_prepare_ready';
  static const prepareFailed = 'local_bg_prepare_failed';
  static const started = 'local_bg_started';
  static const succeeded = 'local_bg_succeeded';
  static const hardRejected = 'local_bg_hard_rejected';
  static const softWarning = 'local_bg_soft_warning';
  static const fallbackStarted = 'local_bg_fallback_started';
  static const persisted = 'local_bg_persisted';
  static const sourceMissing = 'local_bg_source_missing';
  static const improvementRequested = 'local_bg_improvement_requested';
  static const fixCutoutOpened = 'local_bg_fix_cutout_opened';
}

/// Coarse latency buckets. Deliberately wide: the exact millisecond count of one
/// user's photo is not needed to answer "is local removal fast enough".
String localCutoutLatencyBucket(Duration latency) {
  final ms = latency.inMilliseconds;
  if (ms < 0) return 'unknown';
  if (ms < 500) return 'lt500ms';
  if (ms < 1500) return '500ms-1.5s';
  if (ms < 3000) return '1.5s-3s';
  if (ms < 6000) return '3s-6s';
  if (ms < 15000) return '6s-15s';
  return 'gt15s';
}

/// Bucketed subject count, so an unusual value cannot fingerprint a photo.
String localCutoutSubjectBucket(int subjectCount) {
  if (subjectCount <= 0) return '0';
  if (subjectCount == 1) return '1';
  if (subjectCount <= 3) return '2-3';
  if (subjectCount <= 8) return '4-8';
  return 'gt8';
}

/// Properties common to every event in this family.
Map<String, Object> localCutoutBaseProperties({
  required String platform,
  LocalCutoutEngine? engine,
}) => {
  'platform': platform,
  'engine': ?engine?.wireName,
};

/// Payload for a successful local removal.
///
/// Note what is NOT here: `width`, `height`, the operation id, either file path,
/// the engine version string, and any exact ratio. Only buckets.
Map<String, Object> localCutoutSuccessProperties({
  required String platform,
  required LocalCutoutEngine engine,
  required LocalCutoutMetrics metrics,
  required Duration latency,
  required Set<LocalCutoutQualityWarning> warnings,
}) => {
  ...localCutoutBaseProperties(platform: platform, engine: engine),
  'latency_bucket': localCutoutLatencyBucket(latency),
  'subject_bucket': localCutoutSubjectBucket(metrics.subjectCount),
  'size_bucket': metrics.toAnalyticsFields()['size_bucket']! as String,
  'foreground_area_bucket':
      metrics.toAnalyticsFields()['foreground_area_bucket']! as String,
  'uncertain_pixel_bucket':
      metrics.toAnalyticsFields()['uncertain_pixel_bucket']! as String,
  'warning_count': warnings.length,
  'accepted': true,
};

/// Payload for a fallback to the cloud path. The reason is a bounded enum name,
/// never a message or an exception description.
Map<String, Object> localCutoutFallbackProperties({
  required String platform,
  required LocalCutoutFallbackReason reason,
  LocalCutoutEngine? engine,
}) => {
  ...localCutoutBaseProperties(platform: platform, engine: engine),
  'fallback_reason': reason.name,
  'terminal': !reason.canUseCloudFallback,
};

/// Payload for the persistence step, after the backend accepted or refused.
Map<String, Object> localCutoutPersistProperties({
  required String platform,
  required LocalCutoutEngine engine,
  required bool success,
  String? failureCategory,
}) => {
  ...localCutoutBaseProperties(platform: platform, engine: engine),
  'success': success,
  'failure_category': ?failureCategory,
};

/// Reduce an [ApiException] to a BOUNDED category.
///
/// The backend's `message` is human copy that may name a dimension or a limit, so
/// it never reaches analytics — only the stable code, and only if we recognise it.
String localCutoutFailureCategory(ApiException error) => switch (error.code) {
  ApiErrorCode.sourceMissing => 'source_missing',
  ApiErrorCode.validationError => 'mask_rejected',
  ApiErrorCode.providerError => 'storage_unavailable',
  ApiErrorCode.notFound => 'gate_off',
  ApiErrorCode.rateLimited => 'rate_limited',
  ApiErrorCode.network => 'network',
  // Any code this build has not heard of collapses to one bucket rather than
  // leaking a novel string into the analytics schema.
  _ => 'other',
};

/// Map a backend failure onto the client fallback taxonomy (§6.3, Phase 7).
///
/// `SOURCE_MISSING` is the ONE terminal outcome: the worker reads the same stored
/// object, so queuing a cloud attempt would create an item certain to fail. A
/// rejected MASK or a transient storage error are both recoverable through the
/// existing cloud create with the same object key.
LocalCutoutFallbackReason localCutoutReasonForApiError(ApiException error) =>
    switch (error.code) {
      ApiErrorCode.sourceMissing => LocalCutoutFallbackReason.sourceMissing,
      ApiErrorCode.notFound || ApiErrorCode.providerError =>
        LocalCutoutFallbackReason.backendUnavailable,
      _ => LocalCutoutFallbackReason.backendRejected,
    };
