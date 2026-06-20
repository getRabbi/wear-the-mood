import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/tryon/two_d/mannequin.dart';

/// Capability 7: the procedural mannequin's synthetic pose feeds the anchoring
/// pipeline, so it must be a usable, level, head-to-toe body.
void main() {
  test('mannequinPose is a usable, level, head-to-toe body', () {
    final pose = mannequinPose();
    expect(pose.hasTorso, isTrue);
    expect(pose.tilt, 0); // level
    expect(pose.shoulderCenter!.dy, lessThan(pose.hipCenter!.dy)); // shoulders above hips
    expect(pose.hipCenter!.dy, lessThan(pose.kneeCenter!.dy)); // hips above knees
    expect(pose.ankleCenter!.dy, greaterThan(0.85)); // feet near the bottom
    expect(pose.shoulderSpan!, greaterThan(pose.hipSpan!)); // shoulders wider than hips
  });

  test('kMannequinAspect is portrait (taller than wide)', () {
    expect(kMannequinAspect, lessThan(1.0));
  });
}
