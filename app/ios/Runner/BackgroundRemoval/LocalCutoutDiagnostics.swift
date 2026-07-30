import Foundation
import UIKit

/// Device diagnostics for one Apple Vision cutout (iOS Phase 3).
///
/// Exists because Vision has never run on real hardware in this project, and
/// development happens on Windows. Compilation and simulator tests cannot show
/// what `generateScaledMaskForImage` actually returns on a device — Android
/// compiled, passed its tests, and still produced a corrupt mask on its first
/// device run. This type makes the answer exportable.
///
/// It records ONE operation's stage-by-stage facts and serialises them to
/// `result.json` beside that operation's mask and cutout, so the whole bundle can
/// be zipped and shared off the phone.
///
/// **Privacy is a hard allow-list, not a filter.** Every field is enumerated in
/// `payload` below. Nothing reaches this type that could carry a token, a user id,
/// a signed URL, an R2 key, a Supabase key, an authorization header or an absolute
/// filesystem path — the fields simply do not exist. Adding one is a deliberate
/// edit, reviewable in a diff, and `LocalCutoutDiagnosticsTests` asserts the
/// serialised keys against a fixed list so a careless addition fails a test rather
/// than leaking to a share sheet.
struct LocalCutoutDiagnostics {

  /// Which stage the operation reached. Recorded even on success, so a failure
  /// report says where it stopped rather than only that it stopped.
  enum Stage: String {
    case started
    case sourceDecoded = "source_decoded"
    case visionCompleted = "vision_completed"
    case maskScaled = "mask_scaled"
    case maskExtracted = "mask_extracted"
    case composited
    case encoded
    case written
    case completed
  }

  // MARK: - Environment (fixed, non-identifying)

  let appVersion: String
  let appBuild: String
  let systemVersion: String
  /// Hardware identifier such as "iPhone16,1". A model, not a device — it carries
  /// no serial, no name, no advertising id.
  let deviceModel: String

  // MARK: - Per-operation facts

  var stage: Stage = .started
  var sourceWidth: Int?
  var sourceHeight: Int?
  var maskWidth: Int?
  var maskHeight: Int?
  var cutoutWidth: Int?
  var cutoutHeight: Int?
  var sourceByteCount: Int?

  /// `request.results?.count` — how many observations Vision returned.
  var observationCount: Int?
  /// `observation.allInstances.count` — how many instances were selected.
  var instanceCount: Int?

  /// Four-character CoreVideo format code, e.g. "L008" or "L00f".
  var maskPixelFormat: String?
  var maskPlaneCount: Int?
  var maskBytesPerRow: Int?

  var maskStatistics: PixelBufferMaskCompositor.MaskConfidenceReport?
  var meanAlphaCoverage: Double?

  var decodeMs: Int?
  var inferenceMs: Int?
  var maskMs: Int?
  var compositeMs: Int?
  var encodeMs: Int?
  var writeMs: Int?
  var totalMs: Int?

  /// Outcome of `POST /v1/wardrobe/local-cutout`, filled in by Dart.
  var localEndpointStatus: Int?
  /// The typed `LocalCutoutErrorCode` raw value when the operation failed.
  var failureCode: String?
  /// The bounded, non-identifying diagnostic string from `LocalCutoutError`.
  var failureDetail: String?

  // MARK: - Construction

  static func current(bundle: Bundle = .main, device: UIDevice = .current)
    -> LocalCutoutDiagnostics
  {
    LocalCutoutDiagnostics(
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "unknown",
      appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "unknown",
      systemVersion: device.systemVersion,
      deviceModel: Self.hardwareModel()
    )
  }

  /// `uname` machine string. Deliberately not `device.name`, which is user-chosen
  /// and frequently contains a real person's name.
  static func hardwareModel() -> String {
    var info = utsname()
    uname(&info)
    let mirror = Mirror(reflecting: info.machine)
    let identifier = mirror.children.reduce(into: "") { result, element in
      guard let value = element.value as? Int8, value != 0 else { return }
      result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
    }
    return identifier.isEmpty ? "unknown" : identifier
  }

  /// Human-readable four-character code for a CoreVideo pixel format.
  static func formatCode(_ format: OSType) -> String {
    let bytes = [
      UInt8((format >> 24) & 0xFF), UInt8((format >> 16) & 0xFF),
      UInt8((format >> 8) & 0xFF), UInt8(format & 0xFF),
    ]
    let text = String(bytes: bytes, encoding: .ascii) ?? ""
    // Some formats are plain integers rather than FourCC; fall back to the number
    // so the diagnostic is never blank.
    let printable = text.allSatisfy { $0.isASCII && !$0.isNewline && $0 != "\0" }
    return printable && !text.isEmpty ? text : String(format)
  }

  // MARK: - Serialisation

  /// THE ALLOW-LIST. Every exported key is written here explicitly; there is no
  /// reflection, no dictionary merge and no pass-through of arbitrary values.
  var payload: [String: Any] {
    var out: [String: Any] = [
      "schema": "wtm.local-cutout.diagnostics/1",
      "platform": "ios",
      "engine": AppleVisionCutoutEngine.engineName,
      "engine_version": AppleVisionCutoutEngine.engineVersion,
      "app_version": appVersion,
      "app_build": appBuild,
      "ios_version": systemVersion,
      "device_model": deviceModel,
      "stage": stage.rawValue,
      "mask_safety_low": Double(PixelBufferMaskCompositor.maskSafetyLow),
      "mask_safety_high": Double(PixelBufferMaskCompositor.maskSafetyHigh),
      "max_invalid_mask_ratio": PixelBufferMaskCompositor.maxInvalidMaskRatio,
    ]
    func put(_ key: String, _ value: Int?) { if let value { out[key] = value } }
    func putDouble(_ key: String, _ value: Double?) { if let value { out[key] = value } }

    put("source_width", sourceWidth)
    put("source_height", sourceHeight)
    put("mask_width", maskWidth)
    put("mask_height", maskHeight)
    put("cutout_width", cutoutWidth)
    put("cutout_height", cutoutHeight)
    put("source_byte_count", sourceByteCount)
    put("observation_count", observationCount)
    put("instance_count", instanceCount)
    put("mask_plane_count", maskPlaneCount)
    put("mask_bytes_per_row", maskBytesPerRow)
    put("decode_ms", decodeMs)
    put("inference_ms", inferenceMs)
    put("mask_ms", maskMs)
    put("composite_ms", compositeMs)
    put("encode_ms", encodeMs)
    put("write_ms", writeMs)
    put("total_ms", totalMs)
    put("local_endpoint_status", localEndpointStatus)
    putDouble("mean_alpha_coverage", meanAlphaCoverage)

    if let maskPixelFormat { out["mask_pixel_format"] = maskPixelFormat }
    if let failureCode { out["failure_code"] = failureCode }
    if let failureDetail { out["failure_detail"] = failureDetail }

    if let s = maskStatistics {
      out["mask_total_pixels"] = s.total
      out["mask_nan_count"] = s.nanCount
      out["mask_positive_infinity_count"] = s.positiveInfinityCount
      out["mask_negative_infinity_count"] = s.negativeInfinityCount
      out["mask_out_of_envelope_count"] = s.outOfRangeCount
      out["mask_invalid_ratio"] = s.invalidRatio
      // The two numbers Phase 3 exists to obtain: whether real Vision output fits
      // the provisional -0.10...1.10 envelope.
      if let low = s.finiteMin { out["mask_finite_min"] = Double(low) }
      if let high = s.finiteMax { out["mask_finite_max"] = Double(high) }
    }
    return out
  }

  func encoded() throws -> Data {
    try JSONSerialization.data(
      withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }
}
