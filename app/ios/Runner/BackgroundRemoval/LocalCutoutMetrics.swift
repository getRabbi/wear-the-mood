import Foundation

/// The mask maths for local background removal (local BG §5, §8.3).
///
/// A deliberate mirror of Android's `SoftMask.kt`: the Dart quality policy applies
/// ONE set of thresholds to both platforms, so a divergent metric definition here
/// would silently mean different rejection behaviour per platform. Any change to a
/// formula must be made in both files.
///
/// THE RULE THAT MATTERS: the scaled Vision mask is soft and stays soft. Nothing
/// here thresholds the output to 0/255. A hard stencil is what makes lace,
/// chiffon, hair and thin straps look cut out with scissors.
///
/// Free of Vision, CoreVideo and CoreGraphics on purpose, so it is exercised by
/// fast deterministic tests rather than by a device.
enum LocalCutoutMaskMath {

  /// Alpha strictly between these bounds counts as "uncertain" — a genuinely soft
  /// edge. Expected to be non-trivial for lace and hair, which is why a high ratio
  /// is a soft warning in the Dart policy and never a rejection.
  static let uncertainLow: UInt8 = 16
  static let uncertainHigh: UInt8 = 239

  /// At or above this, a pixel counts as foreground for confidence averaging.
  static let foregroundThreshold: UInt8 = 128

  /// Composite straight (unpremultiplied) alpha onto BGRA/RGBA source pixels.
  ///
  /// `source` is 4 bytes per pixel; `alpha` is 1 byte per pixel. The alpha byte is
  /// written into the source's alpha channel at `alphaOffset` and the colour bytes
  /// are left untouched — premultiplying here would darken every soft edge.
  static func composite(
    source: [UInt8],
    alpha: [UInt8],
    alphaOffset: Int
  ) throws -> [UInt8] {
    guard alphaOffset >= 0, alphaOffset < 4 else {
      throw LocalCutoutError.invalidOutput
    }
    guard source.count == alpha.count * 4 else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    var out = source
    for i in 0..<alpha.count {
      out[i * 4 + alphaOffset] = alpha[i]
    }
    return out
  }

  /// Measure a finished mask. Definitions must match `SoftMask.measure` on Android.
  static func measure(
    alpha: [UInt8],
    width: Int,
    height: Int,
    subjectCount: Int
  ) throws -> LocalCutoutMaskMetrics {
    guard width > 0, height > 0 else { throw LocalCutoutError.invalidOutput }
    guard alpha.count == width * height else {
      throw LocalCutoutError.maskDimensionMismatch
    }

    var alphaSum = 0
    var uncertain = 0
    var foregroundCount = 0
    var foregroundSum = 0
    // Combined foreground bounds derived from the AUTHORITATIVE mask. The stable
    // Vision result exposes no per-instance rectangles, and inventing them would
    // be worse than reporting the union we can actually measure.
    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
      let row = y * width
      for x in 0..<width {
        let a = Int(alpha[row + x])
        alphaSum += a
        if a > Int(uncertainLow) && a < Int(uncertainHigh) { uncertain += 1 }
        if a >= Int(foregroundThreshold) {
          foregroundCount += 1
          foregroundSum += a
          if x < minX { minX = x }
          if y < minY { minY = y }
          if x > maxX { maxX = x }
          if y > maxY { maxY = y }
        }
      }
    }

    let total = width * height
    let border = borderAlpha(alpha: alpha, width: width, height: height)
    let bounds: LocalCutoutBounds? =
      maxX >= minX && maxY >= minY
      ? LocalCutoutBounds(
        x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
      : nil

    return LocalCutoutMaskMetrics(
      width: width,
      height: height,
      subjectCount: subjectCount,
      // Mean alpha: a soft edge contributes proportionally rather than counting as
      // fully present or absent. Matches the server's `mask_alpha_area_ratio`, so
      // client and server agree on what "coverage" means.
      foregroundAreaRatio: Double(alphaSum) / (Double(total) * 255.0),
      borderForegroundRatio: border.pixels == 0
        ? 0 : Double(border.sum) / (Double(border.pixels) * 255.0),
      uncertainPixelRatio: Double(uncertain) / Double(total),
      meanForegroundConfidence: foregroundCount == 0
        ? 0 : Double(foregroundSum) / (Double(foregroundCount) * 255.0),
      bounds: bounds
    )
  }

  /// Mean alpha over the one-pixel frame border, counting each pixel exactly once.
  private static func borderAlpha(alpha: [UInt8], width: Int, height: Int)
    -> (sum: Int, pixels: Int)
  {
    var sum = 0
    var pixels = 0
    func add(_ x: Int, _ y: Int) {
      sum += Int(alpha[y * width + x])
      pixels += 1
    }
    for x in 0..<width {
      add(x, 0)
      if height > 1 { add(x, height - 1) }
    }
    // Skip the corners already counted by the top/bottom rows.
    if height > 2 {
      for y in 1..<(height - 1) {
        add(0, y)
        if width > 1 { add(width - 1, y) }
      }
    }
    return (sum, pixels)
  }
}

/// Combined foreground bounds in pixels.
struct LocalCutoutBounds: Equatable {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
}

/// Safe, non-identifying measurements of one mask. Mirrors `MaskMetrics` (Kotlin)
/// and `LocalCutoutMetrics` (Dart).
struct LocalCutoutMaskMetrics {
  let width: Int
  let height: Int
  let subjectCount: Int
  let foregroundAreaRatio: Double
  let borderForegroundRatio: Double
  let uncertainPixelRatio: Double
  let meanForegroundConfidence: Double
  let bounds: LocalCutoutBounds?

  /// The exact shape `LocalCutoutMetrics.fromMap` decodes in Dart (§4).
  var channelMap: [String: Any?] {
    [
      "width": width,
      "height": height,
      "subjectCount": subjectCount,
      "foregroundAreaRatio": foregroundAreaRatio,
      "borderForegroundRatio": borderForegroundRatio,
      "uncertainPixelRatio": uncertainPixelRatio,
      "meanForegroundConfidence": meanForegroundConfidence,
      "foregroundBounds": bounds.map {
        [
          "left": Double($0.x),
          "top": Double($0.y),
          "right": Double($0.x + $0.width),
          "bottom": Double($0.y + $0.height),
        ]
      },
    ]
  }
}
