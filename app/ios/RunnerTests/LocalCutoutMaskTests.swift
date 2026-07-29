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

  func testFloatMaskClampsOutOfRangeAndNaN() throws {
    let values: [Double] = [-0.5, 1.7, Double.nan]
    let buffer = try makeMaskBuffer(
      width: values.count, height: 1,
      format: kCVPixelFormatType_OneComponent32Float, rowAlignment: 0
    ) { x, _ in values[x] }

    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: buffer)

    XCTAssertEqual(alpha(extracted.alpha, 0), 0)
    XCTAssertEqual(alpha(extracted.alpha, 1), 255)
    XCTAssertEqual(alpha(extracted.alpha, 2), 0, "NaN must not become arbitrary alpha")
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
