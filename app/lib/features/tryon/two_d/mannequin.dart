import 'package:flutter/widgets.dart';

import 'body_anchor.dart';

/// Portrait aspect (w/h) of the procedural mannequin "image" — used both to lay
/// it out (contained) and to map [mannequinPose] landmarks onto it.
const double kMannequinAspect = 0.5;

/// Fixed, level landmark layout of the mannequin (normalized 0..1) — fed to the
/// anchoring pipeline (Capability 1) so garments land on the mannequin exactly
/// like a real detected pose (Capability 7).
BodyPose mannequinPose() => const BodyPose(
      nose: Offset(0.5, 0.095),
      leftShoulder: Offset(0.36, 0.26),
      rightShoulder: Offset(0.64, 0.26),
      leftHip: Offset(0.41, 0.55),
      rightHip: Offset(0.59, 0.55),
      leftKnee: Offset(0.44, 0.76),
      rightKnee: Offset(0.56, 0.76),
      leftAnkle: Offset(0.455, 0.93),
      rightAnkle: Offset(0.545, 0.93),
    );

/// A stylized, bundled 2D mannequin silhouette (no assets, no network) for when
/// there's no usable body photo. Drawn to fill its box; its proportions match
/// [mannequinPose] so garments anchor correctly.
class MannequinPainter extends CustomPainter {
  const MannequinPainter({this.fill = const Color(0xFFBDB8AF)});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    Offset p(double nx, double ny) => Offset(nx * w, ny * h);
    RRect capsule(double x0, double y0, double x1, double y1) {
      final r = (x1 - x0) * w / 2;
      return RRect.fromRectAndRadius(
        Rect.fromLTRB(x0 * w, y0 * h, x1 * w, y1 * h),
        Radius.circular(r),
      );
    }

    // Head + neck.
    canvas.drawCircle(p(0.5, 0.095), w * 0.085, paint);
    canvas.drawRRect(capsule(0.46, 0.16, 0.54, 0.24), paint);

    // Torso: shoulders → hips.
    final torso = Path()
      ..moveTo(0.33 * w, 0.23 * h)
      ..lineTo(0.67 * w, 0.23 * h)
      ..lineTo(0.62 * w, 0.57 * h)
      ..lineTo(0.38 * w, 0.57 * h)
      ..close();
    canvas.drawPath(torso, paint);

    // Arms.
    canvas.drawRRect(capsule(0.27, 0.25, 0.35, 0.54), paint);
    canvas.drawRRect(capsule(0.65, 0.25, 0.73, 0.54), paint);

    // Legs.
    canvas.drawRRect(capsule(0.40, 0.55, 0.485, 0.95), paint);
    canvas.drawRRect(capsule(0.515, 0.55, 0.60, 0.95), paint);
  }

  @override
  bool shouldRepaint(MannequinPainter old) => old.fill != fill;
}
