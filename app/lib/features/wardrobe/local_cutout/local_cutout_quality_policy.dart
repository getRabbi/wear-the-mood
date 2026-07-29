/// The ONE place local-cutout quality thresholds live (local BG §5).
///
/// Deliberately a plain, injectable object rather than constants scattered across
/// widgets and native code: the numbers below decide how often a user waits ~90 s
/// for the cloud instead of ~2 s for the device, so they have to be reviewable,
/// tunable and unit-testable in isolation.
///
/// Two levels, and the split matters:
///
///   * **Hard rejection** — structural failure only. The mask cannot be used at
///     all: wrong size, empty, effectively the whole frame, no subject, or a
///     metric that is not a number. These fall back to BiRefNet.
///   * **Soft warning** — accepted, kept, logged. Lace, chiffon, thin straps and
///     a garment touching the frame edge all produce "suspicious" numbers and
///     perfectly good cutouts. Rejecting them without benchmark evidence would
///     send most users to the slow path for no reason (§5.2), so we surface
///     "Improve edges" and "Fix cutout" instead and watch the rates.
library;

import 'local_cutout_models.dart';

/// A non-fatal observation about an accepted local result.
enum LocalCutoutQualityWarning {
  /// Several separate instances — possibly a cluttered shot or a garment the
  /// engine split into pieces.
  manySubjects,

  /// A lot of the frame border is foreground: cropped garment, or mask leakage.
  highBorderContact,

  /// A large share of genuinely intermediate alpha. Normal for lace/chiffon/hair.
  highUncertainty,

  /// The engine was not very sure about its own foreground.
  lowConfidence,

  /// The subject occupies a very small part of the frame.
  smallSubject,
}

/// The verdict for one local result.
class LocalCutoutQualityVerdict {
  const LocalCutoutQualityVerdict.accepted(this.warnings)
    : rejection = null;

  const LocalCutoutQualityVerdict.rejected(LocalCutoutFallbackReason reason)
    : rejection = reason,
      warnings = const <LocalCutoutQualityWarning>{};

  /// Null when the result is usable.
  final LocalCutoutFallbackReason? rejection;

  /// Non-fatal observations; always empty on a rejection.
  final Set<LocalCutoutQualityWarning> warnings;

  bool get isAccepted => rejection == null;

  bool get hasWarnings => warnings.isNotEmpty;

  /// Stable, sorted names for analytics (§10) — no image data, no identifiers.
  List<String> get warningNames =>
      (warnings.map((w) => w.name).toList()..sort());
}

/// Thresholds + the decision. Immutable; construct a variant in tests rather
/// than mutating shared state.
class LocalCutoutQualityPolicy {
  const LocalCutoutQualityPolicy({
    this.minForegroundAreaRatio = 0.01,
    this.maxForegroundAreaRatio = 0.995,
    this.minSubjectCount = 1,
    this.softMaxSubjectCount = 4,
    this.softMaxBorderForegroundRatio = 0.40,
    this.softMaxUncertainPixelRatio = 0.35,
    this.softMinMeanForegroundConfidence = 0.55,
    this.softMinBoundsAreaRatio = 0.02,
  });

  /// Below this the mask is effectively empty — nothing was cut out.
  final double minForegroundAreaRatio;

  /// Above this the mask covers essentially the entire frame, which in practice
  /// means segmentation failed open rather than that the garment truly fills it.
  final double maxForegroundAreaRatio;

  /// At least one foreground instance is required.
  final int minSubjectCount;

  // ── soft (observe, never reject) ──────────────────────────────────────────
  final int softMaxSubjectCount;
  final double softMaxBorderForegroundRatio;
  final double softMaxUncertainPixelRatio;
  final double softMinMeanForegroundConfidence;
  final double softMinBoundsAreaRatio;

  /// Judges [metrics] against the bytes we are about to upload.
  ///
  /// [sourceWidth]/[sourceHeight] are the dimensions of the compressed JPEG that
  /// will be stored as the original. A mismatch is fatal: the backend requires an
  /// exact match and would reject the upload anyway, so catching it here saves a
  /// pointless round trip (§5.1).
  LocalCutoutQualityVerdict evaluate(
    LocalCutoutMetrics metrics, {
    required int sourceWidth,
    required int sourceHeight,
  }) {
    // NaN / infinity / out-of-range / zero dimensions — cannot be reasoned about.
    if (!metrics.isWellFormed) {
      return const LocalCutoutQualityVerdict.rejected(
        LocalCutoutFallbackReason.invalidOutput,
      );
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return const LocalCutoutQualityVerdict.rejected(
        LocalCutoutFallbackReason.invalidOutput,
      );
    }
    if (metrics.width != sourceWidth || metrics.height != sourceHeight) {
      return const LocalCutoutQualityVerdict.rejected(
        LocalCutoutFallbackReason.invalidOutput,
      );
    }
    if (metrics.subjectCount < minSubjectCount) {
      return const LocalCutoutQualityVerdict.rejected(
        LocalCutoutFallbackReason.noSubjectFound,
      );
    }
    if (metrics.foregroundAreaRatio < minForegroundAreaRatio ||
        metrics.foregroundAreaRatio > maxForegroundAreaRatio) {
      return const LocalCutoutQualityVerdict.rejected(
        LocalCutoutFallbackReason.qualityRejected,
      );
    }

    final warnings = <LocalCutoutQualityWarning>{};
    if (metrics.subjectCount > softMaxSubjectCount) {
      warnings.add(LocalCutoutQualityWarning.manySubjects);
    }
    if (metrics.borderForegroundRatio > softMaxBorderForegroundRatio) {
      warnings.add(LocalCutoutQualityWarning.highBorderContact);
    }
    if (metrics.uncertainPixelRatio > softMaxUncertainPixelRatio) {
      warnings.add(LocalCutoutQualityWarning.highUncertainty);
    }
    if (metrics.meanForegroundConfidence < softMinMeanForegroundConfidence) {
      warnings.add(LocalCutoutQualityWarning.lowConfidence);
    }
    final bounds = metrics.foregroundBounds;
    if (bounds != null) {
      final frame = sourceWidth * sourceHeight;
      if (frame > 0 && (bounds.width * bounds.height) / frame < softMinBoundsAreaRatio) {
        warnings.add(LocalCutoutQualityWarning.smallSubject);
      }
    }
    return LocalCutoutQualityVerdict.accepted(warnings);
  }
}

/// The shipped thresholds. Conservative on purpose (§5.1: "Start conservatively"):
/// reject only what is structurally broken.
const LocalCutoutQualityPolicy kDefaultLocalCutoutQualityPolicy =
    LocalCutoutQualityPolicy();
