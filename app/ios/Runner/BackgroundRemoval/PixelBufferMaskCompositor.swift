import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// CoreVideo / CoreGraphics adapter for local background removal (local BG §8.3).
///
/// Three jobs, all of which are easy to get subtly wrong:
///
///  1. **Read a Vision mask pixel buffer into tightly-packed alpha bytes.** The
///     buffer is NOT tightly packed — `bytesPerRow` is padded for alignment, so
///     reading `width * height` bytes linearly would shear the mask diagonally.
///     Row-by-row copying with the real stride is mandatory.
///  2. **Decode the exact compressed source bytes** at full dimensions, with no
///     resampling and no EXIF re-application.
///  3. **Encode lossless PNGs** — a grayscale mask and a transparent cutout.
///
/// Every `CVPixelBufferLockBaseAddress` is paired with a `defer`-ed unlock, and all
/// bytes are copied out before the buffer is released.
enum PixelBufferMaskCompositor {

  /// Mask formats Vision is known to hand back. Anything else is a typed failure
  /// rather than a guess — misreading a format silently corrupts every cutout.
  ///
  /// `generateScaledMaskForImage` is documented as producing a mask suitable for
  /// Core Image masking with high dynamic range preserved, and has been observed
  /// as both 8-bit and 32-bit-float single-component. Both are handled; the float
  /// path clamps to 0...1 before scaling.
  static let supportedMaskFormats: Set<OSType> = [
    kCVPixelFormatType_OneComponent8,
    kCVPixelFormatType_OneComponent32Float,
  ]

  // MARK: - Float-mask safety envelope

  /// Accepted range for a 32-bit-float Vision mask value.
  ///
  /// **Deliberately NOT Android's `-0.25 ... 1.25`.** The two platforms are
  /// validating different kinds of data, so copying the constants would be
  /// cargo-culting:
  ///
  /// * Android inspects ML Kit's **raw per-subject activation**, which is not
  ///   normalised — on a POCO X3 it measured `min=-0.183 max=1.180`, with ~24% of
  ///   values a little over 1. The envelope had to accommodate an unsquashed
  ///   activation, so it was set from that measurement.
  /// * Apple hands back something different in kind.
  ///   `generateScaledMaskForImage(forInstances:from:)` is documented as producing a
  ///   mask suitable for Core Image masking — a **rendered, resampled** mask, not
  ///   raw model output. Its expected range is `0 ... 1`.
  ///
  /// The only legitimate reason to see a value outside `0 ... 1` here is resampling
  /// overshoot: scaling a hard 0→1 edge up to the source dimensions with a
  /// higher-order filter rings slightly past both ends. A few percent is plausible;
  /// `±0.10` leaves roughly an order of magnitude of headroom over that while still
  /// rejecting what a misread buffer actually looks like — wrong `bytesPerRow`,
  /// wrong pixel format, or uninitialised memory reinterpreted as `Float32`, which
  /// yields values like `3.4e38`, denormals and NaN rather than `1.02`.
  ///
  /// **Not yet measured on hardware.** Vision has never run on a device in this
  /// project, so this envelope is reasoned from Apple's documentation, not observed.
  /// Phase 3's device diagnostic must record the real min/max and tighten or widen
  /// it on evidence — the way Android's was set.
  static let maskSafetyLow: Float32 = -0.10
  static let maskSafetyHigh: Float32 = 1.10

  /// Share of a float mask that may be unusable before the whole buffer is refused.
  ///
  /// A healthy rendered mask contains ZERO unusable values, so this is a hair above
  /// nothing rather than a real allowance. It exists only so one stray value in a
  /// multi-megapixel buffer cannot force a needless cloud fallback. The corruption
  /// that bit Android measured 69% invalid — three orders of magnitude past this.
  static let maxInvalidMaskRatio = 0.001

  /// How one float mask value classifies. The single place the envelope is applied,
  /// so the counting pass and the tests cannot drift apart.
  ///
  /// NaN and the two infinities are separate cases rather than one `nonFinite`
  /// bucket because the Phase 3 device diagnostic must report them separately: they
  /// point at different faults. NaN is characteristic of uninitialised memory or a
  /// bad arithmetic path; a run of `+inf` is more typical of a stride/format
  /// misread. Distinguishing them is what will make a real device failure
  /// diagnosable instead of merely detected.
  enum MaskValueClass: Equatable {
    case usable
    case notANumber
    case positiveInfinity
    case negativeInfinity
    case outOfRange
  }

  static func classify(_ value: Float32) -> MaskValueClass {
    // NaN fails every comparison, so it must be tested explicitly and first —
    // relying on the range check would silently classify it as usable.
    if value.isNaN { return .notANumber }
    if value.isInfinite { return value > 0 ? .positiveInfinity : .negativeInfinity }
    if value < maskSafetyLow || value > maskSafetyHigh { return .outOfRange }
    return .usable
  }

  /// What an inspection found. Counts and aggregate extremes only — never a
  /// coordinate, never a pixel's position, so it is safe to log and to export in a
  /// diagnostic bundle (§10).
  struct MaskConfidenceReport: Equatable {
    let total: Int
    let nanCount: Int
    let positiveInfinityCount: Int
    let negativeInfinityCount: Int
    let outOfRangeCount: Int
    /// Extremes across the FINITE values only, so one NaN cannot erase the range.
    /// Both nil when no finite value was seen.
    let finiteMin: Float32?
    let finiteMax: Float32?

    var nonFinite: Int { nanCount + positiveInfinityCount + negativeInfinityCount }
    var invalid: Int { nonFinite + outOfRangeCount }

    /// An empty buffer is fully invalid, not vacuously perfect.
    var invalidRatio: Double {
      total <= 0 ? 1.0 : Double(invalid) / Double(total)
    }

    var isUsable: Bool {
      total > 0 && invalidRatio <= PixelBufferMaskCompositor.maxInvalidMaskRatio
    }

    /// Bounded and non-identifying.
    var summary: String {
      let range =
        finiteMin.map { min in
          finiteMax.map { max in
            " finite_min=\(String(format: "%.4f", min))"
              + " finite_max=\(String(format: "%.4f", max))"
          } ?? ""
        } ?? " finite_min=none finite_max=none"
      return "total=\(total) nan=\(nanCount) pos_inf=\(positiveInfinityCount)"
        + " neg_inf=\(negativeInfinityCount) out_of_range=\(outOfRangeCount)"
        + " invalid_ratio=\(String(format: "%.4f", invalidRatio))" + range
    }
  }

  /// Accumulates mask statistics one value at a time.
  ///
  /// Shared by the pixel-buffer pass (which must not allocate a second copy of a
  /// multi-megapixel buffer) and by `inspectFloatMask` (which tests drive with plain
  /// arrays), so the two can never disagree about what the envelope means.
  struct MaskStatisticsAccumulator {
    private(set) var total = 0
    private(set) var nanCount = 0
    private(set) var positiveInfinityCount = 0
    private(set) var negativeInfinityCount = 0
    private(set) var outOfRangeCount = 0
    private(set) var finiteMin: Float32?
    private(set) var finiteMax: Float32?

    mutating func add(_ value: Float32) {
      total += 1
      let kind = classify(value)
      switch kind {
      case .notANumber: nanCount += 1
      case .positiveInfinity: positiveInfinityCount += 1
      case .negativeInfinity: negativeInfinityCount += 1
      case .usable, .outOfRange:
        // Out-of-range values are still FINITE, so they belong in the observed
        // range — that range is exactly the evidence Phase 3 needs to judge whether
        // the envelope is right.
        if kind == .outOfRange { outOfRangeCount += 1 }
        finiteMin = finiteMin.map { Swift.min($0, value) } ?? value
        finiteMax = finiteMax.map { Swift.max($0, value) } ?? value
      }
    }

    var report: MaskConfidenceReport {
      MaskConfidenceReport(
        total: total,
        nanCount: nanCount,
        positiveInfinityCount: positiveInfinityCount,
        negativeInfinityCount: negativeInfinityCount,
        outOfRangeCount: outOfRangeCount,
        finiteMin: finiteMin,
        finiteMax: finiteMax
      )
    }
  }

  /// Count the unusable values in `values`. Never throws, never mutates.
  static func inspectFloatMask<S: Sequence>(_ values: S) -> MaskConfidenceReport
  where S.Element == Float32 {
    var accumulator = MaskStatisticsAccumulator()
    for value in values { accumulator.add(value) }
    return accumulator.report
  }

  // MARK: - Mask extraction

  /// Copy a single-component mask buffer into tightly-packed 8-bit alpha.
  ///
  /// Intermediate values are preserved: the float path rounds, it does not
  /// threshold. Returns `width * height` bytes in row-major order.
  static func alphaBytes(from buffer: CVPixelBuffer) throws -> (
    alpha: [UInt8], width: Int, height: Int, statistics: MaskConfidenceReport
  ) {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    guard supportedMaskFormats.contains(format) else {
      throw LocalCutoutError.unsupportedMaskPixelFormat
    }
    // A planar buffer would need per-plane handling; the masks we accept are not.
    guard CVPixelBufferGetPlaneCount(buffer) <= 1 else {
      throw LocalCutoutError.unsupportedMaskPixelFormat
    }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    guard width > 0, height > 0 else { throw LocalCutoutError.invalidOutput }
    // Guard the byte-count arithmetic before it is used to size an allocation.
    guard let pixelCount = multiplyChecked(width, height) else {
      throw LocalCutoutError.invalidOutput
    }

    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
      throw LocalCutoutError.invalidOutput
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw LocalCutoutError.invalidOutput
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let bytesPerPixel = format == kCVPixelFormatType_OneComponent8 ? 1 : 4
    // Rows are padded: never assume tight packing, and never read past the row.
    guard bytesPerRow >= width * bytesPerPixel else {
      throw LocalCutoutError.invalidOutput
    }
    guard
      let requiredBytes = multiplyChecked(bytesPerRow, height),
      requiredBytes <= CVPixelBufferGetDataSize(buffer)
    else {
      throw LocalCutoutError.invalidOutput
    }

    var alpha = [UInt8](repeating: 0, count: pixelCount)
    var statistics: MaskConfidenceReport
    if format == kCVPixelFormatType_OneComponent8 {
      // An 8-bit mask cannot be non-finite or out of envelope, so there is nothing
      // to validate. The extremes are still recorded: the device diagnostic needs to
      // know which format Vision actually returned and what range it spanned.
      let bytes = base.assumingMemoryBound(to: UInt8.self)
      var lowest = UInt8.max
      var highest = UInt8.min
      for y in 0..<height {
        let row = bytes.advanced(by: y * bytesPerRow)
        let destination = y * width
        for x in 0..<width {
          let value = row[x]
          alpha[destination + x] = value
          if value < lowest { lowest = value }
          if value > highest { highest = value }
        }
      }
      statistics = MaskConfidenceReport(
        total: pixelCount,
        nanCount: 0,
        positiveInfinityCount: 0,
        negativeInfinityCount: 0,
        outOfRangeCount: 0,
        finiteMin: Float32(lowest) / 255,
        finiteMax: Float32(highest) / 255
      )
    } else {
      // PASS 1 — measure only. Nothing is clamped, converted or written yet.
      //
      // This ordering is the whole point. The previous implementation coerced NaN
      // to 0 and clamped anything huge into range while converting, which turns a
      // corrupt buffer into a plausible-looking mask and then into a saved wardrobe
      // item. That is exactly how Android shipped a corrupt cutout. A buffer is
      // judged in full BEFORE any of it is trusted.
      var accumulator = MaskStatisticsAccumulator()
      for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow)
          .assumingMemoryBound(to: Float32.self)
        for x in 0..<width {
          accumulator.add(row[x])
        }
      }
      let report = accumulator.report
      guard report.isUsable else {
        throw LocalCutoutError.maskCorrupt(report.summary)
      }
      statistics = report

      // PASS 2 — only now is clamping legitimate. Every value has been shown to be
      // finite and inside the safety envelope, so this clamp only folds the accepted
      // resampling overshoot into 0...1. Intermediate values are rounded, never
      // thresholded: soft edges survive intact.
      for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow)
          .assumingMemoryBound(to: Float32.self)
        let destination = y * width
        for x in 0..<width {
          let clamped = min(max(row[x], 0), 1)
          alpha[destination + x] = UInt8((clamped * 255).rounded())
        }
      }
    }
    return (alpha, width, height, statistics)
  }

  // MARK: - Output verification

  /// Dimensions of an encoded image, proved by actually decoding it.
  ///
  /// A non-empty byte array is not evidence of a usable PNG. This decodes the bytes
  /// the way any consumer would — the Flutter preview, the backend, the closet grid
  /// — so a well-formed-but-wrong or truncated image is refused locally instead of
  /// being uploaded and rejected server-side (or worse, accepted and displayed
  /// broken).
  static func decodedDimensions(of data: Data) throws -> (width: Int, height: Int) {
    guard !data.isEmpty else { throw LocalCutoutError.emptyOutput }
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width > 0, image.height > 0
    else {
      throw LocalCutoutError.outputNotDecodable
    }
    return (image.width, image.height)
  }

  // MARK: - Source decoding

  /// Decode the EXACT compressed bytes Flutter will upload as the original.
  ///
  /// No resampling, no thumbnail path and no orientation transform: the mask must
  /// match the stored original pixel for pixel or the backend rejects it (§8.1).
  /// A source declaring a non-upright orientation is refused rather than
  /// double-corrected — see `LocalCutoutError.unsupportedSourceOrientation`.
  static func decodeSource(_ data: Data) throws -> CGImage {
    guard !data.isEmpty else { throw LocalCutoutError.sourceMissing }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw LocalCutoutError.sourceDecodeFailed
    }
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as NSDictionary?,
      let orientation = properties[kCGImagePropertyOrientation] as? Int,
      orientation != 1
    {
      throw LocalCutoutError.unsupportedSourceOrientation
    }
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false,
      kCGImageSourceShouldAllowFloat: false,
    ]
    guard
      let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
      image.width > 0, image.height > 0
    else {
      throw LocalCutoutError.sourceDecodeFailed
    }
    return image
  }

  /// Redraw `image` into a known 8-bit BGRA layout so the compositor can rely on
  /// a fixed byte order and stride. Returns tightly-packed pixels.
  static func bgraBytes(from image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    guard let rowBytes = multiplyChecked(width, 4),
      let totalBytes = multiplyChecked(rowBytes, height)
    else { throw LocalCutoutError.invalidOutput }

    var pixels = [UInt8](repeating: 0, count: totalBytes)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    // premultipliedFirst + byteOrder32Little == BGRA in memory. The source is
    // opaque JPEG, so premultiplication is a no-op on the way in; alpha is applied
    // afterwards by the compositor as STRAIGHT alpha.
    let bitmapInfo =
      CGImageAlphaInfo.premultipliedFirst.rawValue
      | CGBitmapInfo.byteOrder32Little.rawValue
    // The CGContext must be created AND used entirely inside the closure: it holds
    // a raw pointer into `pixels`, which is only valid for the closure's duration.
    let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: rowBytes,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { throw LocalCutoutError.sourceDecodeFailed }
    return pixels
  }

  // MARK: - PNG encoding

  /// Lossless 8-bit grayscale PNG at the exact mask dimensions.
  ///
  /// Written as GRAYSCALE (value in the single channel, fully opaque) rather than
  /// as an alpha-only image, matching Android. The backend's
  /// `decode_uploaded_mask` reduces any accepted mask to one channel and takes
  /// luminance for an opaque image — which is exactly the confidence value.
  static func encodeMaskPNG(alpha: [UInt8], width: Int, height: Int) throws -> Data {
    guard width > 0, height > 0, alpha.count == width * height else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    var bytes = alpha
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let image: CGImage? = bytes.withUnsafeMutableBytes { raw -> CGImage? in
      guard
        let context = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else { return nil }
      return context.makeImage()
    }
    guard let image else { throw LocalCutoutError.emptyOutput }
    return try encodePNG(image)
  }

  /// Lossless transparent PNG at the exact source dimensions.
  ///
  /// Built as a `CGImage` over a data provider rather than drawn through a
  /// `CGContext`, because the alpha layout the compositor produces cannot be
  /// expressed by a bitmap context at all.
  ///
  /// `CGBitmapContext` accepts only `none`, `noneSkipFirst`, `noneSkipLast`,
  /// `premultipliedFirst`, `premultipliedLast` and `alphaOnly`. STRAIGHT alpha —
  /// `kCGImageAlphaFirst` — is valid for a `CGImage` but not for a context, so
  /// `CGContext(...)` returned nil for every call and this function could never
  /// produce a cutout on any device. `CGImage(width:height:...provider:)` accepts
  /// it, so the bytes are handed over verbatim instead of being drawn.
  ///
  /// Straight alpha is deliberate and preserved: declaring the buffer
  /// premultiplied would make CoreGraphics treat already un-premultiplied colour
  /// as premultiplied and brighten every soft edge — exactly the artefact on lace,
  /// chiffon and hair that the soft mask exists to avoid. PNG stores
  /// non-premultiplied alpha natively, so this round-trips losslessly.
  static func encodeCutoutPNG(bgra: [UInt8], width: Int, height: Int) throws -> Data {
    guard width > 0, height > 0, bgra.count == width * height * 4 else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    // Same overflow discipline as everywhere else: a corrupt dimension must not
    // wrap the stride calculation.
    guard let bytesPerRow = multiplyChecked(width, 4) else {
      throw LocalCutoutError.invalidOutput
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    // `.first` + byteOrder32Little == B,G,R,A in memory with STRAIGHT alpha at
    // byte 3 — the exact layout `LocalCutoutMaskMath.composite(alphaOffset: 3)`
    // wrote, and the same byte order `bgraBytes` produces.
    let bitmapInfo = CGBitmapInfo(
      rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    // `Data(bgra)` copies, so the provider owns memory that outlives this scope —
    // unlike a pointer into a local array.
    guard let provider = CGDataProvider(data: Data(bgra) as CFData) else {
      throw LocalCutoutError.emptyOutput
    }
    guard
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else { throw LocalCutoutError.emptyOutput }
    // Dimensions are re-proved on the constructed image: a silently resized or
    // reinterpreted buffer would produce a cutout the backend rejects (§8.1).
    guard image.width == width, image.height == height else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    return try encodePNG(image)
  }

  private static func encodePNG(_ image: CGImage) throws -> Data {
    let output = NSMutableData()
    let type: CFString
    if #available(iOS 14.0, *) {
      type = UTType.png.identifier as CFString
    } else {
      type = "public.png" as CFString
    }
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, type, 1, nil)
    else { throw LocalCutoutError.emptyOutput }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination), output.length > 0 else {
      throw LocalCutoutError.emptyOutput
    }
    return output as Data
  }

  /// Overflow-safe multiply, so a hostile or corrupt dimension cannot wrap a
  /// byte-count calculation into a small allocation.
  static func multiplyChecked(_ a: Int, _ b: Int) -> Int? {
    guard a >= 0, b >= 0 else { return nil }
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    return overflow ? nil : result
  }
}
