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

  // MARK: - Mask extraction

  /// Copy a single-component mask buffer into tightly-packed 8-bit alpha.
  ///
  /// Intermediate values are preserved: the float path rounds, it does not
  /// threshold. Returns `width * height` bytes in row-major order.
  static func alphaBytes(from buffer: CVPixelBuffer) throws -> (
    alpha: [UInt8], width: Int, height: Int
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
    if format == kCVPixelFormatType_OneComponent8 {
      let bytes = base.assumingMemoryBound(to: UInt8.self)
      for y in 0..<height {
        let row = bytes.advanced(by: y * bytesPerRow)
        let destination = y * width
        for x in 0..<width {
          alpha[destination + x] = row[x]
        }
      }
    } else {
      for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow)
          .assumingMemoryBound(to: Float32.self)
        let destination = y * width
        for x in 0..<width {
          let value = row[x]
          // NaN fails both comparisons and lands on 0 — an unusable value must
          // never become an arbitrary alpha.
          let clamped: Float32 = value.isNaN ? 0 : min(max(value, 0), 1)
          alpha[destination + x] = UInt8((clamped * 255).rounded())
        }
      }
    }
    return (alpha, width, height)
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
