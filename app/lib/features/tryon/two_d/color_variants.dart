import 'dart:math' as math;
import 'dart:ui';

/// Luminance-preserving hue-rotation colour matrix (20 values, row-major 4×5) for
/// `ColorFilter.matrix` — recolours a garment cutout while keeping its shading,
/// so a piece looks like the same fabric in another colour. Pure + testable.
List<double> hueRotationMatrix(double degrees) {
  final rad = degrees * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return [
    lr + c * (1 - lr) + s * (-lr), lg + c * (-lg) + s * (-lg), lb + c * (-lb) + s * (1 - lb), 0, 0,
    lr + c * (-lr) + s * 0.143, lg + c * (1 - lg) + s * 0.140, lb + c * (-lb) + s * (-0.283), 0, 0,
    lr + c * (-lr) + s * (-(1 - lr)), lg + c * (-lg) + s * lg, lb + c * (1 - lb) + s * lb, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Desaturating (greyscale / "mono") colour matrix.
List<double> greyscaleMatrix() {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return const [
    lr, lg, lb, 0, 0,
    lr, lg, lb, 0, 0,
    lr, lg, lb, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// One on-device colour variant for a garment (Capability 4). Index 0 in
/// [kColorVariants] is the original (no filter).
class ColorVariant {
  const ColorVariant(this.matrix);

  final List<double>? matrix;

  ColorFilter? get filter => matrix == null ? null : ColorFilter.matrix(matrix!);
}

/// Original + a spread of hue rotations + mono. Kept small + ordered (original
/// first, mono last) so the picker can label the ends.
final List<ColorVariant> kColorVariants = [
  const ColorVariant(null),
  ColorVariant(hueRotationMatrix(40)),
  ColorVariant(hueRotationMatrix(90)),
  ColorVariant(hueRotationMatrix(150)),
  ColorVariant(hueRotationMatrix(210)),
  ColorVariant(hueRotationMatrix(270)),
  ColorVariant(hueRotationMatrix(320)),
  ColorVariant(greyscaleMatrix()),
];
