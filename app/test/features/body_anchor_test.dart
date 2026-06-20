import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/tryon/two_d/body_anchor.dart';

void main() {
  // A simple upright, level pose (normalized 0..1 of the image).
  const pose = BodyPose(
    leftShoulder: Offset(0.40, 0.25),
    rightShoulder: Offset(0.60, 0.25),
    leftHip: Offset(0.43, 0.55),
    rightHip: Offset(0.57, 0.55),
    leftKnee: Offset(0.44, 0.75),
    rightKnee: Offset(0.56, 0.75),
    leftAnkle: Offset(0.45, 0.95),
    rightAnkle: Offset(0.55, 0.95),
    nose: Offset(0.50, 0.12),
  );

  test('top is anchored shoulders->upper-waist, sized to shoulder span', () {
    final ap = anchoredPlacement('White top', pose)!;
    expect(ap.widthFactor, closeTo(0.20 * 2.05, 0.001)); // shoulderSpan*2.05
    expect(ap.verticalCenter, closeTo(0.25 * 0.6 + 0.55 * 0.4, 0.001)); // 0.37
    expect(ap.tilt, closeTo(0, 0.001)); // level shoulders
  });

  test('bottoms anchored waist->ankles, sized to hip span', () {
    final ap = anchoredPlacement('Blue jeans', pose)!;
    expect(ap.widthFactor, closeTo(0.14 * 1.9, 0.001)); // hipSpan*1.9
    expect(ap.verticalCenter, closeTo((0.55 + 0.95) / 2, 0.001)); // 0.75
  });

  test('accessories fall back to the heuristic (null)', () {
    expect(anchoredPlacement('Gold necklace', pose), isNull);
    expect(anchoredPlacement('Sunglasses', pose), isNull);
    expect(anchoredPlacement('Leather belt', pose), isNull);
  });

  test('missing torso landmarks => null (heuristic fallback)', () {
    expect(anchoredPlacement('top', const BodyPose()), isNull);
  });

  test('a leaning pose produces a non-zero tilt', () {
    const leaning = BodyPose(
      leftShoulder: Offset(0.40, 0.22),
      rightShoulder: Offset(0.60, 0.30), // right shoulder lower → lean
      leftHip: Offset(0.43, 0.55),
      rightHip: Offset(0.57, 0.57),
    );
    final ap = anchoredPlacement('shirt', leaning)!;
    expect(ap.tilt.abs(), greaterThan(0.05));
  });

  test('containImageRect letterboxes a wide image in a square canvas', () {
    final r = containImageRect(const Size(100, 100), 2.0); // 2:1 image
    expect(r.width, 100);
    expect(r.height, 50);
    expect(r.top, 25);
  });

  test('toCanvasPlacement maps image-space to canvas fractions', () {
    const ap = AnchoredPlacement(widthFactor: 0.5, verticalCenter: 0.5, tilt: 0);
    final cp = toCanvasPlacement(ap, const Size(100, 100), 2.0);
    expect(cp.widthFactor, closeTo(0.5, 0.001));
    expect(cp.verticalCenter, closeTo(0.5, 0.001)); // 25 + 0.5*50 = 50 → /100
  });
}
