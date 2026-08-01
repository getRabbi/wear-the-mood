import CoreGraphics
import Foundation
import ImageIO

/// The native contract self-test (local BG §4).
///
/// A Dart unit test can prove the orchestrator's decisions but not the one thing
/// that actually matters on a device: that the NATIVE half works.
/// `encodeCutoutPNG` had never once produced a cutout on any iPhone — it composed
/// through a `CGBitmapContext` in a pixel format CoreGraphics cannot represent, so
/// it returned nil every time — and that survived a green compile check, a green
/// Flutter suite and a typed cloud fallback that made the result look normal. The
/// encoder is the one component no test looked at.
///
/// So this exercises the real encoders end to end: encode, decode back, inspect the
/// pixels, and prove the transparent and soft-alpha values survived.
///
/// Rules it lives by:
///  * it returns only bounded, non-identifying fields — never a path, never bytes;
///  * it never throws: a failure is a typed `failureCode`, because a self-test that
///    can crash the app is worse than no self-test;
///  * Dart runs it at most once per app version (§4) — never on every launch.
enum LocalCutoutSelfTest {

  /// Bumped when the shape of the reply changes, so Dart can reason about age.
  static let channelVersion = 1

  private static let probeWidth = 8
  private static let probeHeight = 8

  /// Typed reasons, mirrored by Dart's `LocalCutoutSelfTestFailure` and by
  /// Android's `LocalCutoutSelfTest.Failure`. A shipped contract: add values,
  /// never rename one.
  enum Failure {
    static let none = "none"
    static let cache = "cache_unavailable"
    static let operationId = "operation_id_invalid"
    static let maskEncoder = "mask_encoder_lost_alpha"
    static let cutoutEncoder = "cutout_encoder_lost_transparency"
    static let decode = "output_not_decodable"
    static let dimensions = "dimensions_not_preserved"
    static let cleanup = "cleanup_failed"
    static let engineVersion = "engine_version_missing"
    static let visionUnavailable = "vision_unavailable"
    static let visionFixtureFailed = "vision_fixture_failed"
    static let internalError = "internal"
  }

  /// Run the contract checks against the REAL encoders and cache.
  ///
  /// `runVisionFixture` drives the optional provider smoke (§4). It is a closure so
  /// the pure contract half stays runnable on a simulator and in the standalone
  /// RunnerTests bundle, where Vision has no camera-grade hardware behind it.
  static func run(
    cache: LocalCutoutOperationCache,
    engineVersion: String,
    platformAvailable: Bool,
    runVisionFixture: (() -> VisionFixtureOutcome)? = nil
    // `[String: Any]`, not `[String: Any?]`: every value here is non-nil by
    // construction, and a double optional would make `reply["status"] as? String`
    // at the call site a cast from `Any??` -- which silently misses.
  ) -> [String: Any] {
    var encoderOk = false
    var cacheOk = false
    var operationId: String?

    func reply(_ failureCode: String, modelAvailable: Bool) -> [String: Any] {
      if let operationId { _ = cache.delete(operationId) }
      return [
        "status": failureCode == Failure.none && encoderOk && cacheOk ? "pass" : "fail",
        "engine": AppleVisionCutoutEngine.engineName,
        "engineVersion": engineVersion,
        "channelVersion": channelVersion,
        "encoderOk": encoderOk,
        "cacheOk": cacheOk,
        "platformAvailable": platformAvailable,
        "modelAvailable": modelAvailable,
        "failureCode": failureCode,
      ]
    }

    do {
      let identifier = LocalCutoutOperationCache.newOperationId()
      guard LocalCutoutOperationCache.isValidOperationId(identifier) else {
        return reply(Failure.operationId, modelAvailable: false)
      }
      operationId = identifier

      // 1. The cache root is writable and containment-checked.
      let directory = try cache.createOperationDirectory(identifier)
      let probe = directory.appendingPathComponent("selftest.bin")
      try Data([1, 2, 3, 4]).write(to: probe)
      cacheOk =
        FileManager.default.fileExists(atPath: probe.path)
        && (try? Data(contentsOf: probe))?.count == 4
      guard cacheOk else { return reply(Failure.cache, modelAvailable: false) }

      // 2. The MASK encoder must preserve the confidence value, including a soft
      //    mid-tone. A thresholding encoder hardens every lace and chiffon edge.
      // Explicit `-> UInt8`: a multi-statement closure with a switch is exactly
      // where Swift's return-type inference gives up, and every round trip to
      // find that out costs a full CI build.
      let alpha: [UInt8] = (0..<(probeWidth * probeHeight)).map { index -> UInt8 in
        switch index % 3 {
        case 0: return 0
        case 1: return 128
        default: return 255
        }
      }
      let maskPNG = try PixelBufferMaskCompositor.encodeMaskPNG(
        alpha: alpha, width: probeWidth, height: probeHeight)
      guard !maskPNG.isEmpty else { return reply(Failure.maskEncoder, modelAvailable: false) }
      guard let maskImage = decodeImage(maskPNG) else {
        return reply(Failure.decode, modelAvailable: false)
      }
      guard maskImage.width == probeWidth, maskImage.height == probeHeight else {
        return reply(Failure.dimensions, modelAvailable: false)
      }
      guard maskValuesSurvived(maskImage, expected: alpha) else {
        return reply(Failure.maskEncoder, modelAvailable: false)
      }

      // 3. The CUTOUT encoder must keep fully transparent pixels transparent AND an
      //    intermediate alpha intermediate. Losing the first is an opaque rectangle
      //    in the closet; losing the second is a hard, cut-out-with-scissors edge.
      //    Layout is B,G,R,A with STRAIGHT alpha, matching the compositor.
      var bgra = [UInt8](repeating: 0, count: probeWidth * probeHeight * 4)
      for index in 0..<(probeWidth * probeHeight) {
        let offset = index * 4
        switch index % 3 {
        case 0:
          bgra[offset] = 0; bgra[offset + 1] = 0; bgra[offset + 2] = 0; bgra[offset + 3] = 0
        case 1:
          bgra[offset] = 0; bgra[offset + 1] = 0; bgra[offset + 2] = 255; bgra[offset + 3] = 128
        default:
          bgra[offset] = 0; bgra[offset + 1] = 255; bgra[offset + 2] = 0; bgra[offset + 3] = 255
        }
      }
      let cutoutPNG = try PixelBufferMaskCompositor.encodeCutoutPNG(
        bgra: bgra, width: probeWidth, height: probeHeight)
      guard !cutoutPNG.isEmpty else { return reply(Failure.cutoutEncoder, modelAvailable: false) }
      guard let cutoutImage = decodeImage(cutoutPNG) else {
        return reply(Failure.decode, modelAvailable: false)
      }
      guard cutoutImage.width == probeWidth, cutoutImage.height == probeHeight else {
        return reply(Failure.dimensions, modelAvailable: false)
      }
      guard cutoutAlphaSurvived(cutoutImage) else {
        return reply(Failure.cutoutEncoder, modelAvailable: false)
      }
      encoderOk = true

      // 4. Cleanup really removes the directory (a leak here fills the cache).
      _ = cache.delete(identifier)
      operationId = nil
      if FileManager.default.fileExists(atPath: directory.path) {
        return reply(Failure.cleanup, modelAvailable: false)
      }

      guard !engineVersion.trimmingCharacters(in: .whitespaces).isEmpty else {
        return reply(Failure.engineVersion, modelAvailable: false)
      }
    } catch let error as LocalCutoutError {
      return reply(
        error.code == .cacheUnavailable ? Failure.cache : Failure.internalError,
        modelAvailable: false)
    } catch {
      return reply(Failure.internalError, modelAvailable: false)
    }

    // 5. Provider smoke — real Vision inference over a small app-owned fixture, run
    //    at most once per app version. Skipped entirely below iOS 17, where the
    //    correct behaviour is an unsupported capability and a cloud fallback, not a
    //    failure.
    guard platformAvailable, let runVisionFixture else {
      return reply(Failure.none, modelAvailable: false)
    }
    switch runVisionFixture() {
    case .passed:
      return reply(Failure.none, modelAvailable: true)
    case .unavailable:
      return reply(Failure.visionUnavailable, modelAvailable: false)
    case .failed:
      return reply(Failure.visionFixtureFailed, modelAvailable: false)
    }
  }

  /// Outcome of the optional Vision fixture run.
  enum VisionFixtureOutcome {
    /// Vision returned at least one instance and its mask passed the structural
    /// envelope — dimensions, format, finiteness, neither empty nor full.
    case passed
    /// Vision could not run at all on this device/build.
    case unavailable
    /// Vision ran and produced something structurally unusable.
    case failed
  }

  // MARK: - regression fixture

  /// The app-owned Vision fixture: a garment-shaped silhouette drawn in code.
  ///
  /// Deliberately GENERATED rather than bundled. A photograph would raise a licence
  /// question the commercial build cannot afford (CLAUDE.md §2.2), would add bytes
  /// to every install, and would drift from the repo. Drawing it costs microseconds,
  /// is byte-identical on every device, and is unambiguously ours.
  ///
  /// It is checked with BROAD structural invariants — at least one instance, mask
  /// dimensions matching the source, a supported format, a finite-value envelope,
  /// neither empty nor full — never exact pixel equality, which would fail on the
  /// first OS revision that changes resampling by a hair.
  static func makeFixtureImage(width: Int = 256, height: Int = 384) -> CGImage? {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    // A light, flat background and a dark garment body with sleeves: enough
    // separation for a foreground instance to exist without pretending to be a real
    // photograph. Vision either finds a subject here or it is not working.
    context.setFillColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
    let w = CGFloat(width)
    let h = CGFloat(height)
    context.fill(CGRect(x: w * 0.28, y: h * 0.10, width: w * 0.44, height: h * 0.62))
    context.fill(CGRect(x: w * 0.14, y: h * 0.52, width: w * 0.16, height: h * 0.18))
    context.fill(CGRect(x: w * 0.70, y: h * 0.52, width: w * 0.16, height: h * 0.18))
    return context.makeImage()
  }

  /// Structural envelope for a fixture mask. Kept here, not in the engine, so the
  /// self-test cannot silently loosen the production validation it borrows.
  static func fixtureOutcome(
    maskWidth: Int,
    maskHeight: Int,
    sourceWidth: Int,
    sourceHeight: Int,
    instanceCount: Int,
    coverage: Double
  ) -> VisionFixtureOutcome {
    guard instanceCount > 0 else { return .failed }
    guard maskWidth == sourceWidth, maskHeight == sourceHeight else { return .failed }
    guard coverage.isFinite, coverage > 0.01, coverage < 0.99 else { return .failed }
    return .passed
  }

  // MARK: - pixel inspection

  private static func decodeImage(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// Re-render into a known 8-bit layout so the check reads the same bytes whatever
  /// colour space or channel order the PNG decoder chose.
  private static func rgbaBytes(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          // Straight alpha is not representable in a bitmap context (that is the
          // whole encoder defect), so read back premultiplied and un-premultiply.
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return ok ? buffer : nil
  }

  /// A grayscale mask decodes with the value in the colour channels and alpha 255,
  /// so the VALUE is what is asserted here, not the alpha byte.
  private static func maskValuesSurvived(_ image: CGImage, expected: [UInt8]) -> Bool {
    guard let bytes = rgbaBytes(image), bytes.count == expected.count * 4 else { return false }
    var sawZero = false
    var sawSoft = false
    for index in expected.indices {
      let actual = Int(bytes[index * 4])  // R; grayscale replicates across RGB
      let want = Int(expected[index])
      // One step of tolerance for colour-space conversion on the round trip.
      if abs(actual - want) > 2 { return false }
      if want == 0 { sawZero = true }
      if want > 0 && want < 255 { sawSoft = true }
    }
    // Prove the probe itself discriminated: a uniformly opaque encoder must not be
    // able to pass by accident.
    return sawZero && sawSoft
  }

  private static func cutoutAlphaSurvived(_ image: CGImage) -> Bool {
    guard let bytes = rgbaBytes(image) else { return false }
    var transparent = 0
    var soft = 0
    var opaque = 0
    for offset in stride(from: 3, to: bytes.count, by: 4) {
      let alpha = Int(bytes[offset])
      if alpha == 0 {
        transparent += 1
      } else if alpha == 255 {
        opaque += 1
      } else if (100...160).contains(alpha) {
        soft += 1
      }
    }
    return transparent > 0 && soft > 0 && opaque > 0
  }
}
