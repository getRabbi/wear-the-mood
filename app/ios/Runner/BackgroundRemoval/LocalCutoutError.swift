import Foundation

/// Stable error codes for local-first background removal (local BG §4, §8.3).
///
/// These travel to Dart as `FlutterError.code` and MUST match
/// `LocalCutoutErrorCode` in `local_cutout_platform.dart` and
/// `LocalCutoutErrors` on Android, character for character. They are a shipped
/// contract: add values, never rename or repurpose one. Dart maps an unrecognised
/// code to a generic native error, so a newer native layer can never break an
/// older Dart layer.
enum LocalCutoutErrorCode: String {
  /// iOS below 17 — the Vision foreground-instance API does not exist.
  case unsupported = "unsupported"
  /// The engine ran and found no foreground instance.
  case noSubject = "no_subject"
  /// Structurally unusable output: undecodable source, zero dimensions, an
  /// unsupported mask pixel format, or a mask that does not match the source.
  case invalidOutput = "invalid_output"
  /// The operation exceeded its bound.
  case timeout = "timeout"
  /// Cancelled explicitly, or by plugin teardown.
  case cancelled = "cancelled"
  /// Another removal is already running — only one at a time is permitted.
  case busy = "busy"
  /// The operation directory could not be created, or is not containable.
  case cacheUnavailable = "cache_unavailable"
  /// Anything else.
  case internalError = "internal"
}

/// A typed failure.
///
/// `diagnostic` is developer-facing only and must never contain image bytes, mask
/// bytes, filesystem paths, filenames, user identifiers or raw Apple error
/// descriptions (§10) — it is logged locally and returned to Dart. Concrete Apple
/// errors are deliberately collapsed into a category before they reach here.
struct LocalCutoutError: Error {
  let code: LocalCutoutErrorCode
  let diagnostic: String

  init(_ code: LocalCutoutErrorCode, _ diagnostic: String) {
    self.code = code
    self.diagnostic = diagnostic
  }

  // MARK: - Categorised constructors
  //
  // Each of these is a named case from the Phase 4 error-mapping list. They exist
  // so the call sites read as the taxonomy rather than as ad-hoc strings, and so
  // a raw `NSError.localizedDescription` never becomes the diagnostic.

  static let unsupportedOsVersion = LocalCutoutError(
    .unsupported, "Vision foreground instance masking requires iOS 17."
  )
  static let malformedOperationId = LocalCutoutError(
    .cacheUnavailable, "Malformed operation id."
  )
  static let cacheNotContained = LocalCutoutError(
    .cacheUnavailable, "Operation directory escapes the cache root."
  )
  static let cacheWriteFailed = LocalCutoutError(
    .cacheUnavailable, "Could not persist the operation output."
  )
  static let sourceMissing = LocalCutoutError(
    .invalidOutput, "No source image bytes supplied."
  )
  static let sourceDecodeFailed = LocalCutoutError(
    .invalidOutput, "Could not decode the source image."
  )
  /// The compressed source declares a non-upright EXIF orientation.
  ///
  /// `flutter_image_compress` bakes rotation into the pixels and strips EXIF, so
  /// this should never occur. If it ever does, failing here is deliberate: the
  /// backend applies `exif_transpose` to the stored original, which could swap
  /// width and height, and a mask built on un-rotated pixels would then be
  /// rejected server-side anyway. Better a clean local fallback than a mask that
  /// silently does not line up (§8.1).
  static let unsupportedSourceOrientation = LocalCutoutError(
    .invalidOutput, "Source image declares a non-upright orientation."
  )
  static let visionRequestFailed = LocalCutoutError(
    .internalError, "The Vision request failed."
  )
  static let noObservation = LocalCutoutError(
    .noSubject, "Vision returned no observation."
  )
  static let noForegroundInstances = LocalCutoutError(
    .noSubject, "No foreground subject was found."
  )
  static let unsupportedMaskPixelFormat = LocalCutoutError(
    .invalidOutput, "Unsupported mask pixel format."
  )
  static let maskDimensionMismatch = LocalCutoutError(
    .invalidOutput, "Mask dimensions do not match the source."
  )
  static let emptyOutput = LocalCutoutError(
    .invalidOutput, "Encoder produced an empty image."
  )
  /// A structurally impossible argument reached a pure helper (zero dimensions,
  /// an out-of-range offset, an overflowing byte count).
  static let invalidOutput = LocalCutoutError(
    .invalidOutput, "Invalid image argument."
  )
  static let maskEffectivelyEmpty = LocalCutoutError(
    .invalidOutput, "Mask selects effectively nothing."
  )
  static let maskEffectivelyFull = LocalCutoutError(
    .invalidOutput, "Mask selects effectively the whole frame."
  )
  /// The float mask carried too many non-finite or out-of-envelope values to be
  /// trusted. `summary` is bounded counts only — never a pixel value or coordinate.
  static func maskCorrupt(_ summary: String) -> LocalCutoutError {
    LocalCutoutError(.invalidOutput, "Mask failed the safety envelope: \(summary).")
  }
  /// An encoded PNG could not be decoded back, or decoded to the wrong geometry.
  /// Non-empty bytes are not proof of a usable image.
  static let outputNotDecodable = LocalCutoutError(
    .invalidOutput, "Encoded output could not be decoded back."
  )
  static let busy = LocalCutoutError(
    .busy, "Another background removal is already running."
  )
  static let cancelled = LocalCutoutError(
    .cancelled, "Operation cancelled."
  )
  static let timedOut = LocalCutoutError(
    .timeout, "Local background removal timed out."
  )
  static let disposed = LocalCutoutError(
    .cancelled, "The engine has been disposed."
  )

  /// Collapse an arbitrary Swift/Apple error into the taxonomy WITHOUT leaking its
  /// description. Only the error's type name is retained as a safe category.
  static func unexpected(_ error: Error) -> LocalCutoutError {
    LocalCutoutError(.internalError, "Unexpected \(type(of: error)).")
  }
}
