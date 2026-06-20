import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/tryon/two_d/color_variants.dart';

/// Capability 4: on-device garment recolour matrices.
void main() {
  test('hueRotationMatrix is a 20-value identity at 0°', () {
    final m = hueRotationMatrix(0);
    expect(m.length, 20);
    expect(m[0], closeTo(1, 0.001)); // r→r
    expect(m[6], closeTo(1, 0.001)); // g→g
    expect(m[12], closeTo(1, 0.001)); // b→b
    expect(m[18], 1); // a→a
    expect(m[1], closeTo(0, 0.001)); // no cross-channel bleed at 0°
    expect(m[2], closeTo(0, 0.001));
  });

  test('hueRotationMatrix actually rotates at 120°', () {
    final m = hueRotationMatrix(120);
    expect(m.length, 20);
    expect(m[0], isNot(closeTo(1, 0.05))); // diagonal moved → real rotation
  });

  test('greyscaleMatrix collapses channels to shared luminance weights', () {
    final m = greyscaleMatrix();
    expect(m.length, 20);
    expect(m[0], m[5]); // each output row uses the same RGB weights
    expect(m[1], m[6]);
    expect(m[2], m[7]);
    expect(m[0] + m[1] + m[2], closeTo(1.0, 0.001));
  });

  test('kColorVariants: original first (no filter), mono last (has filter)', () {
    expect(kColorVariants.first.matrix, isNull);
    expect(kColorVariants.first.filter, isNull);
    expect(kColorVariants.last.filter, isNotNull);
    expect(kColorVariants.length, greaterThanOrEqualTo(6));
  });
}
