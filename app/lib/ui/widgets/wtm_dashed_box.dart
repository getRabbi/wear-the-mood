import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';

/// Dashed hairline round-rect — the Outfit Maker's empty slot canvas (board
/// §3.19). Paints a `.line`-toned dashed border over an optional [child].
class WtmDashedBox extends StatelessWidget {
  const WtmDashedBox({super.key, this.child, this.radius = WtmRadius.tile});

  final Widget? child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashPainter(radius: radius),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WtmColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
