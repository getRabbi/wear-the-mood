import CoreGraphics
import CoreVideo
import XCTest

/// Mask maths, pixel-buffer reading and PNG encoding (local BG §11.4).
///
/// Unlike Android's JVM tests, XCTest runs on a real (simulated) OS, so CoreVideo
/// and CoreGraphics are genuinely exercised here rather than faked. The two things
/// most worth proving:
///
///  * **Padded rows.** A Vision mask buffer is not tightly packed; reading
///    `width * height` bytes linearly would shear the mask diagonally. These tests
///    build buffers with deliberately padded `bytesPerRow`.
///  * **Soft alpha survives.** Nothing may threshold the mask to 0/255.
final class LocalCutoutMaskTests: XCTestCase {

  // MARK: - Helpers

  /// Build a single-component pixel buffer.
  ///
  /// `rowAlignment` is a real CoreVideo alignment (not a stride): passing 64 for a
  /// narrow buffer reliably forces `bytesPerRow` well past `width`, which is what
  /// the padded-row tests need. Writers always consult the ACTUAL
  /// `CVPixelBufferGetBytesPerRow`, never an assumed value.
  private func makeMaskBuffer(
    width: Int,
    height: Int,
    format: OSType,
    rowAlignment: Int,
    fill: (_ x: Int, _ y: Int) -> Double
  ) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    var attributes: [String: Any] = [:]
    if rowAlignment > 0 {
      attributes[kCVPixelBufferBytesPerRowAlignmentKey as String] = rowAlignment
    }
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, format,
      attributes.isEmpty ? nil : attributes as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
      throw XCTSkip("could not allocate a \(width)x\(height) mask buffer")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw XCTSkip("mask buffer has no base address")
    }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
      for x in 0..<width {
        let value = fill(x, y)
        if format == kCVPixelFormatType_OneComponent8 {
          base.advanced(by: y * stride + x)
            .assumingMemoryBound(to: UInt8.self)
            .pointee = UInt8((value * 255).rounded())
        } else {
          base.advanced(by: y * stride + x * 4)
            .assumingMemoryBound(to: Float32.self)
            .pointee = Float32(value)
        }
      }
    }
    return buffer
  }

  private func alpha(_ bytes: [UInt8], _ index: Int) -> Int { Int(bytes[index]) }

  // MARK: - Pixel-buffer reading

  func testReadsAnEightBitMask() throws {
    let buffer = try makeMaskBuffer(
      width: 4, height: 3, format: kCVPixelFormatType_OneComponent8, rowAlignment: 0
    ) { x, _ in Double(x) / 3.0 }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    XCTAssertEqual(extracted.width, 4)
    XCTAssertEqual(extracted.height, 3)
    XCTAssertEqual(extracted.alpha.count, 12)
    XCTAssertEqual(alpha(extracted.alpha, 0), 0)
    XCTAssertEqual(alpha(extracted.alpha, 3), 255)
  }

  func testRespectsPaddedBytesPerRow() throws {
    // THE test for this file. Row 1 must read as row 1, not as row 0 shifted by
    // the padding. A stride-unaware reader shears the mask diagonally.
    let width = 5
    let height = 4
    let buffer = try makeMaskBuffer(
      width: width, height: height,
      format: kCVPixelFormatType_OneComponent8, rowAlignment: 64
    ) { _, y in Double(y) / 3.0 }

    XCTAssertGreaterThan(
      CVPixelBufferGetBytesPerRow(buffer), width,
      "the buffer must actually be padded for this test to mean anything")

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    for y in 0..<height {
      let expected = Int((Double(y) / 3.0 * 255).rounded())
      for x in 0..<width {
        XCTAssertEqual(
          alpha(extracted.alpha, y * width + x), expected,
          "row \(y) column \(x) read from the wrong offset")
      }
    }
  }

  func testReadsAFloatMaskAndPreservesIntermediateValues() throws {
    let values: [Double] = [0.0, 0.2, 0.45, 0.62, 0.8, 1.0]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 64
    ) { x, _ in values[x] }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    // Six distinct inputs must give six distinct outputs: rounding, not thresholding.
    let distinct = Set(extracted.alpha)
    XCTAssertEqual(distinct.count, values.count)
    XCTAssertEqual(alpha(extracted.alpha, 0), 0)
    XCTAssertEqual(alpha(extracted.alpha, values.count - 1), 255)
    XCTAssertEqual(alpha(extracted.alpha, 2), Int((0.45 * 255).rounded()))
  }

  // MARK: - Float-mask corruption guard
  //
  // These replace an earlier `testFloatMaskClampsOutOfRangeAndNaN`, which asserted
  // that [-0.5, 1.7, NaN] silently became [0, 255, 0]. That behaviour was the
  // defect, not the contract: coercing unusable values into plausible alpha is
  // precisely how Android turned a 69%-invalid buffer into a saved wardrobe item.
  // The assertions below pin the opposite guarantee — a materially corrupt buffer is
  // refused, and only values already proved safe are clamped.

  /// A corrupt buffer must be refused, not coerced.
  func testNaNHeavyFloatMaskIsRefused() throws {
    let values: [Double] = [0.5, Double.nan, Double.nan, 0.4]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 0
    ) { x, _ in values[x] }

    XCTAssertThrowsError(try PixelBufferMaskCompositor.alphaBytes(from: buffer)) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  func testInfiniteFloatMaskIsRefused() throws {
    let values: [Double] = [0.5, Double.infinity, -Double.infinity, 0.4]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 0
    ) { x, _ in values[x] }

    XCTAssertThrowsError(try PixelBufferMaskCompositor.alphaBytes(from: buffer)) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  /// The shape a misread buffer actually has — uninitialised memory reinterpreted
  /// as Float32 gives values like 3.4e38, not 1.02.
  func testOutOfRangeHeavyFloatMaskIsRefused() throws {
    let values: [Double] = [0.5, 3.4e38, -2.0, 12.0]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 0
    ) { x, _ in values[x] }

    XCTAssertThrowsError(try PixelBufferMaskCompositor.alphaBytes(from: buffer)) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  /// A small overshoot is legitimate — `generateScaledMaskForImage` resamples a
  /// 0→1 edge up to the source size, and a higher-order filter rings slightly past
  /// both ends. It must be accepted and folded into 0...1, NOT refused.
  func testSmallResamplingOvershootIsAcceptedAndClamped() throws {
    let values: [Double] = [-0.05, 0.0, 0.5, 1.0, 1.05]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 64
    ) { x, _ in values[x] }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    XCTAssertEqual(alpha(extracted.alpha, 0), 0, "negative overshoot clamps to 0")
    XCTAssertEqual(alpha(extracted.alpha, 1), 0)
    XCTAssertEqual(
      alpha(extracted.alpha, 2), Int((0.5 * 255).rounded()),
      "a genuine soft-edge value must survive clamping untouched")
    XCTAssertEqual(alpha(extracted.alpha, 3), 255)
    XCTAssertEqual(alpha(extracted.alpha, 4), 255, "positive overshoot clamps to 255")
  }

  /// The envelope is a reasoned choice, not Android's numbers. Pin it so widening it
  /// is a deliberate edit with a visible diff.
  func testTheSafetyEnvelopeIsTighterThanAndroids() {
    XCTAssertEqual(PixelBufferMaskCompositor.maskSafetyLow, -0.10)
    XCTAssertEqual(PixelBufferMaskCompositor.maskSafetyHigh, 1.10)
    // Android's raw-activation envelope is -0.25...1.25; Apple returns a rendered,
    // normalised mask, so iOS is deliberately stricter at both ends.
    XCTAssertGreaterThan(PixelBufferMaskCompositor.maskSafetyLow, -0.25)
    XCTAssertLessThan(PixelBufferMaskCompositor.maskSafetyHigh, 1.25)
    XCTAssertEqual(PixelBufferMaskCompositor.maxInvalidMaskRatio, 0.001)
  }

  func testClassifySortsValuesByTheEnvelope() {
    XCTAssertEqual(PixelBufferMaskCompositor.classify(0.0), .usable)
    XCTAssertEqual(PixelBufferMaskCompositor.classify(1.0), .usable)
    XCTAssertEqual(PixelBufferMaskCompositor.classify(-0.10), .usable, "boundary")
    XCTAssertEqual(PixelBufferMaskCompositor.classify(1.10), .usable, "boundary")
    XCTAssertEqual(PixelBufferMaskCompositor.classify(-0.11), .outOfRange)
    XCTAssertEqual(PixelBufferMaskCompositor.classify(1.11), .outOfRange)
    // NaN fails every comparison, so it must be caught explicitly rather than by
    // the range test.
    XCTAssertEqual(PixelBufferMaskCompositor.classify(Float32.nan), .nonFinite)
    XCTAssertEqual(PixelBufferMaskCompositor.classify(.infinity), .nonFinite)
    XCTAssertEqual(PixelBufferMaskCompositor.classify(-.infinity), .nonFinite)
  }

  func testInspectionCountsAndJudgesUsability() {
    let clean = PixelBufferMaskCompositor.inspectFloatMask(
      [Float32](repeating: 0.5, count: 1000))
    XCTAssertEqual(clean.total, 1000)
    XCTAssertEqual(clean.invalid, 0)
    XCTAssertTrue(clean.isUsable)

    var mixed = [Float32](repeating: 0.5, count: 998)
    mixed.append(.nan)
    mixed.append(9999)
    let report = PixelBufferMaskCompositor.inspectFloatMask(mixed)
    XCTAssertEqual(report.total, 1000)
    XCTAssertEqual(report.nonFinite, 1)
    XCTAssertEqual(report.outOfRange, 1)
    XCTAssertEqual(report.invalidRatio, 0.002, accuracy: 1e-9)
    XCTAssertFalse(report.isUsable, "0.2% invalid is past the 0.1% allowance")

    // An empty buffer is fully invalid, not vacuously perfect.
    let empty = PixelBufferMaskCompositor.inspectFloatMask([Float32]())
    XCTAssertEqual(empty.invalidRatio, 1.0)
    XCTAssertFalse(empty.isUsable)

    // One stray value in a megapixel buffer must NOT force a cloud fallback.
    var oneStray = [Float32](repeating: 0.5, count: 1_000_000)
    oneStray[500_000] = .nan
    XCTAssertTrue(PixelBufferMaskCompositor.inspectFloatMask(oneStray).isUsable)
  }

  /// The report is logged, so it must carry counts only — no pixel values, no
  /// coordinates (§10).
  func testReportSummaryCarriesCountsOnly() {
    let summary = PixelBufferMaskCompositor.inspectFloatMask(
      [0.5, Float32.nan, 9999] as [Float32]
    ).summary
    XCTAssertTrue(summary.contains("total=3"))
    XCTAssertTrue(summary.contains("non_finite=1"))
    XCTAssertTrue(summary.contains("out_of_range=1"))
    XCTAssertFalse(summary.contains("9999"), "no pixel value may be logged")
  }

  /// An 8-bit mask cannot be out of range or non-finite by construction, so the
  /// guard must not interfere with it.
  func testEightBitMaskNeedsNoEnvelopeAndIsUnaffected() throws {
    let buffer = try makeMaskBuffer(
      width: 4, height: 1, format: kCVPixelFormatType_OneComponent8, rowAlignment: 0
    ) { x, _ in Double(x) / 3.0 }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    XCTAssertEqual(alpha(extracted.alpha, 0), 0)
    XCTAssertEqual(alpha(extracted.alpha, 3), 255)
  }

  // MARK: - Output verification

  func testDecodedDimensionsRoundTripAPNG() throws {
    let png = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: [UInt8](repeating: 120, count: 7 * 3 * 4), width: 7, height: 3)

    let size = try PixelBufferMaskCompositor.decodedDimensions(of: png)

    XCTAssertEqual(size.width, 7)
    XCTAssertEqual(size.height, 3)
  }

  func testDecodedDimensionsRejectsEmptyData() {
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.decodedDimensions(of: Data())
    ) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  func testDecodedDimensionsRejectsAnInvalidPNG() {
    // A correct PNG signature followed by nothing usable: non-empty bytes are not
    // proof of a decodable image.
    let fake = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.decodedDimensions(of: fake)
    ) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.decodedDimensions(of: Data([1, 2, 3, 4, 5]))
    ) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  func testEncodedMaskPNGAlsoDecodesAtTheExactDimensions() throws {
    let png = try PixelBufferMaskCompositor.encodeMaskPNG(
      alpha: [UInt8](repeating: 200, count: 5 * 4), width: 5, height: 4)

    let size = try PixelBufferMaskCompositor.decodedDimensions(of: png)

    XCTAssertEqual(size.width, 5)
    XCTAssertEqual(size.height, 4)
  }

  func testUnsupportedPixelFormatFailsTyped() throws {
    // A BGRA buffer is not a mask. Misreading a format silently corrupts every
    // cutout, so this must be a typed refusal rather than a best-effort guess.
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer)
    try XCTSkipUnless(status == kCVReturnSuccess, "could not allocate a BGRA buffer")

    XCTAssertThrowsError(try PixelBufferMaskCompositor.alphaBytes(from: buffer!)) {
      error in
      XCTAssertEqual((error as? LocalCutoutError)?.code, .invalidOutput)
      XCTAssertEqual(
        (error as? LocalCutoutError)?.diagnostic,
        LocalCutoutError.unsupportedMaskPixelFormat.diagnostic)
    }
  }

  func testSupportedFormatsAreExactlyTheTwoWeHandle() {
    XCTAssertEqual(
      PixelBufferMaskCompositor.supportedMaskFormats,
      [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent32Float])
  }

  func testMultiplyCheckedRejectsOverflow() {
    XCTAssertEqual(PixelBufferMaskCompositor.multiplyChecked(1600, 1200), 1_920_000)
    XCTAssertNil(PixelBufferMaskCompositor.multiplyChecked(Int.max, 4))
    XCTAssertNil(PixelBufferMaskCompositor.multiplyChecked(-1, 4))
  }

  // MARK: - Label map vs alpha mask

  func testLabelMapValuesAreNotTreatedAsAlpha() throws {
    // `observation.instanceMask` is an instance-LABEL map: 0 = background, other
    // values are instance IDS. If those ever reached the alpha path, a two-subject
    // image would produce alpha 1 and 2 out of 255 — a virtually invisible cutout.
    // The engine only ever reads the SCALED mask, and this test documents why by
    // showing what the label values would have produced.
    let labels: [UInt8] = [0, 1, 2, 1]
    let buffer = try makeMaskBuffer(
      width: labels.count, height: 1,
      format: kCVPixelFormatType_OneComponent8, rowAlignment: 0
    ) { x, _ in Double(labels[x]) / 255.0 }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: extracted.alpha, width: labels.count, height: 1, subjectCount: 2)

    // Near-zero coverage: the engine rejects this as effectively empty rather than
    // shipping it, which is the safety net if a label map ever arrived by mistake.
    XCTAssertLessThan(metrics.foregroundAreaRatio, 0.01)
    XCTAssertEqual(metrics.meanForegroundConfidence, 0)
  }

  // MARK: - Metrics

  func testMeasuresAHalfCoveredFrame() throws {
    var alpha = [UInt8](repeating: 0, count: 8)
    for y in 0..<2 { for x in 0..<2 { alpha[y * 4 + x] = 255 } }

    let metrics = try LocalCutoutMaskMath.measure(
      alpha: alpha, width: 4, height: 2, subjectCount: 1)

    XCTAssertEqual(metrics.foregroundAreaRatio, 0.5, accuracy: 1e-9)
    XCTAssertEqual(metrics.meanForegroundConfidence, 1.0, accuracy: 1e-9)
    XCTAssertEqual(metrics.uncertainPixelRatio, 0.0, accuracy: 1e-9)
  }

  func testCountsSoftAlphaProportionally() throws {
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [UInt8](repeating: 128, count: 16), width: 4, height: 4, subjectCount: 1)
    XCTAssertEqual(metrics.foregroundAreaRatio, 128.0 / 255.0, accuracy: 1e-9)
  }

  func testEmptyMaskReportsZeroes() throws {
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [UInt8](repeating: 0, count: 16), width: 4, height: 4, subjectCount: 0)
    XCTAssertEqual(metrics.foregroundAreaRatio, 0, accuracy: 1e-9)
    XCTAssertEqual(metrics.borderForegroundRatio, 0, accuracy: 1e-9)
    XCTAssertEqual(metrics.meanForegroundConfidence, 0, accuracy: 1e-9)
    XCTAssertNil(metrics.bounds)
  }

  func testNearFullMaskReportsTotalCoverage() throws {
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [UInt8](repeating: 255, count: 16), width: 4, height: 4, subjectCount: 1)
    XCTAssertEqual(metrics.foregroundAreaRatio, 1.0, accuracy: 1e-9)
    XCTAssertEqual(metrics.borderForegroundRatio, 1.0, accuracy: 1e-9)
  }

  func testBorderRatioIgnoresTheInterior() throws {
    var alpha = [UInt8](repeating: 0, count: 16)
    for y in 1...2 { for x in 1...2 { alpha[y * 4 + x] = 255 } }

    let metrics = try LocalCutoutMaskMath.measure(
      alpha: alpha, width: 4, height: 4, subjectCount: 1)

    XCTAssertEqual(metrics.borderForegroundRatio, 0, accuracy: 1e-9)
    XCTAssertEqual(metrics.foregroundAreaRatio, 4.0 / 16.0, accuracy: 1e-9)
  }

  func testBorderRatioCountsEachBorderPixelOnce() throws {
    // A full 3x3 border is 8 pixels; double-counting the corners would skew the
    // ratio in a way no other assertion here notices.
    var alpha = [UInt8](repeating: 255, count: 9)
    alpha[4] = 0
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: alpha, width: 3, height: 3, subjectCount: 1)
    XCTAssertEqual(metrics.borderForegroundRatio, 1.0, accuracy: 1e-9)
  }

  func testUncertainRatioCountsOnlyIntermediateAlpha() throws {
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [0, 255, 128, 200], width: 4, height: 1, subjectCount: 1)
    XCTAssertEqual(metrics.uncertainPixelRatio, 0.5, accuracy: 1e-9)
  }

  func testMeanForegroundConfidenceAveragesOnlyForeground() throws {
    // One background pixel must not drag the foreground average down.
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [0, 200, 200, 200], width: 4, height: 1, subjectCount: 1)
    XCTAssertEqual(metrics.meanForegroundConfidence, 200.0 / 255.0, accuracy: 1e-9)
  }

  func testCombinedBoundsComeFromTheMask() throws {
    var alpha = [UInt8](repeating: 0, count: 25)
    alpha[1 * 5 + 1] = 255
    alpha[3 * 5 + 3] = 255

    let metrics = try LocalCutoutMaskMath.measure(
      alpha: alpha, width: 5, height: 5, subjectCount: 2)

    // The union of both foreground pixels, inclusive.
    XCTAssertEqual(metrics.bounds, LocalCutoutBounds(x: 1, y: 1, width: 3, height: 3))
  }

  func testSubjectCountIsCarriedThrough() throws {
    let metrics = try LocalCutoutMaskMath.measure(
      alpha: [UInt8](repeating: 128, count: 4), width: 2, height: 2, subjectCount: 7)
    XCTAssertEqual(metrics.subjectCount, 7)
    XCTAssertEqual(metrics.channelMap["subjectCount"] as? Int, 7)
  }

  func testMeasureRejectsDimensionMismatch() {
    XCTAssertThrowsError(
      try LocalCutoutMaskMath.measure(
        alpha: [UInt8](repeating: 0, count: 5), width: 4, height: 4, subjectCount: 1)
    ) { error in
      XCTAssertEqual((error as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  func testMeasureRejectsNonPositiveDimensions() {
    XCTAssertThrowsError(
      try LocalCutoutMaskMath.measure(alpha: [], width: 0, height: 4, subjectCount: 1))
  }

  // MARK: - Compositing

  func testCompositesStraightAlphaOntoSourceColour() throws {
    // BGRA, alpha at byte 3. Colour bytes must be untouched: premultiplying here
    // would darken every soft edge.
    let source: [UInt8] = [0x33, 0x22, 0x11, 0xFF, 0x66, 0x55, 0x44, 0xFF]
    let composited = try LocalCutoutMaskMath.composite(
      source: source, alpha: [0, 140], alphaOffset: 3)

    XCTAssertEqual(composited[3], 0)
    XCTAssertEqual(Array(composited[0..<3]), [0x33, 0x22, 0x11])
    XCTAssertEqual(composited[7], 140)
    XCTAssertEqual(Array(composited[4..<7]), [0x66, 0x55, 0x44])
  }

  func testCompositeRejectsSizeMismatch() {
    XCTAssertThrowsError(
      try LocalCutoutMaskMath.composite(
        source: [UInt8](repeating: 0, count: 8), alpha: [0, 1, 2], alphaOffset: 3))
  }

  func testCompositeRejectsBadAlphaOffset() {
    XCTAssertThrowsError(
      try LocalCutoutMaskMath.composite(
        source: [UInt8](repeating: 0, count: 4), alpha: [0], alphaOffset: 4))
  }

  // MARK: - PNG encoding

  func testEncodesALosslessGrayscaleMaskPNG() throws {
    let alpha: [UInt8] = [0, 64, 140, 255]
    let data = try PixelBufferMaskCompositor.encodeMaskPNG(
      alpha: alpha, width: 4, height: 1)

    XCTAssertFalse(data.isEmpty)
    // PNG magic number, so we know it is genuinely a PNG and not a stub.
    XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
  }

  func testEncodesATransparentCutoutPNG() throws {
    let bgra: [UInt8] = [0x33, 0x22, 0x11, 140, 0x66, 0x55, 0x44, 0]
    let data = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: bgra, width: 2, height: 1)

    XCTAssertFalse(data.isEmpty)
    XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
  }

  func testEncodersRejectDimensionMismatch() {
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.encodeMaskPNG(alpha: [0, 1], width: 4, height: 4))
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.encodeCutoutPNG(bgra: [0, 1], width: 4, height: 4))
  }

  // MARK: - Source decoding

  func testDecodeRejectsEmptyAndGarbageData() {
    XCTAssertThrowsError(try PixelBufferMaskCompositor.decodeSource(Data())) { error in
      XCTAssertEqual(
        (error as? LocalCutoutError)?.diagnostic,
        LocalCutoutError.sourceMissing.diagnostic)
    }
    XCTAssertThrowsError(
      try PixelBufferMaskCompositor.decodeSource(Data([1, 2, 3, 4, 5]))
    ) { error in
      XCTAssertEqual((error as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  /// Regression test for the defect that made `encodeCutoutPNG` fail on EVERY
  /// call: it built the image through a `CGBitmapContext`, which cannot represent
  /// `kCGImageAlphaFirst` (straight alpha), so `CGContext(...)` always returned nil
  /// and the engine threw `invalid_output` before writing a single cutout.
  ///
  /// Proves the three properties that matter for a soft-edged cutout: alpha
  /// survives the PNG round trip, colour is NOT premultiplied on the way out, and
  /// the geometry is exact.
  func testCutoutPNGKeepsStraightAlphaAndUnbrightenedColour() throws {
    /// Compare with a tolerance, without depending on the numeric `accuracy:`
    /// overload resolving for integers.
    func assertNear(
      _ actual: UInt8, _ expected: Int, _ tolerance: Int, _ what: String,
      line: UInt = #line
    ) {
      XCTAssertLessThanOrEqual(
        abs(Int(actual) - expected), tolerance,
        "\(what): got \(actual), expected ~\(expected)", line: line)
    }

    // BGRA in memory, STRAIGHT alpha. Pixel 0 is the case a soft mask edge really
    // produces: a mid-tone colour at half coverage.
    let bgra: [UInt8] = [
      50, 100, 200, 128,  // -> RGB(200,100,50) @ alpha 128
      10, 20, 30, 255,  // fully opaque
      99, 99, 99, 0,  // fully transparent
      0, 0, 0, 255,
    ]
    let width = 4
    let height = 1

    let png = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: bgra, width: width, height: height)
    XCTAssertFalse(png.isEmpty)
    XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG magic bytes")

    let image = try PixelBufferMaskCompositor.decodeSource(png)
    XCTAssertEqual(image.width, width, "width must round-trip exactly (§8.1)")
    XCTAssertEqual(image.height, height, "height must round-trip exactly (§8.1)")

    // Read back through a PREMULTIPLIED context. If the encoder had stored colour
    // already premultiplied, it would be premultiplied a SECOND time here and come
    // out about half as bright again — the soft-edge darkening this format choice
    // exists to prevent. premultipliedLast without a byte-order flag is R,G,B,A.
    var out = [UInt8](repeating: 0, count: width * height * 4)
    out.withUnsafeMutableBytes { raw in
      let context = CGContext(
        data: raw.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
      XCTAssertNotNil(context, "premultipliedLast IS a legal bitmap-context format")
      context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    // Straight RGB(200,100,50) at alpha 128 premultiplies to (100,50,25). Storing
    // it premultiplied instead would land near (50,25,13) — far outside tolerance.
    assertNear(out[3], 128, 1, "alpha must survive verbatim")
    assertNear(out[0], 100, 2, "red must not be pre-darkened")
    assertNear(out[1], 50, 2, "green must not be pre-darkened")
    assertNear(out[2], 25, 2, "blue must not be pre-darkened")

    // Opaque pixel keeps its colour exactly; transparent stays fully transparent.
    assertNear(out[7], 255, 1, "opaque alpha")
    assertNear(out[4], 30, 2, "opaque red")
    assertNear(out[5], 20, 2, "opaque green")
    assertNear(out[6], 10, 2, "opaque blue")
    assertNear(out[11], 0, 0, "transparent alpha must stay 0")
  }

  func testDecodeRoundTripsDimensionsExactly() throws {
    // The whole §8.1 contract: the mask must match the uploaded original pixel for
    // pixel, so decoding must never resample.
    let png = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: [UInt8](repeating: 200, count: 6 * 5 * 4), width: 6, height: 5)

    let image = try PixelBufferMaskCompositor.decodeSource(png)

    XCTAssertEqual(image.width, 6)
    XCTAssertEqual(image.height, 5)
    let pixels = try PixelBufferMaskCompositor.bgraBytes(from: image)
    XCTAssertEqual(pixels.count, 6 * 5 * 4)
  }
}
