import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';

/// Board figure silhouettes (`fig-form` / `fig-body` symbols) — the gold
/// line-art placeholder drawn inside aurora imagery until real renders exist.
enum WtmFigureKind {
  /// Dress form on a stand, 200×320 viewBox (Home hero thumb, story tiles).
  form,

  /// Full body outline, 240×560 viewBox (MoodMirror portal, editor — P4).
  body,
}

/// Stroked gold figure with the board's soft gold glow
/// (`drop-shadow(0 0 12px rgba(217,190,149,.25))`). Scales to its box.
class WtmFigure extends StatelessWidget {
  const WtmFigure(
    this.kind, {
    super.key,
    this.opacity = 0.8,
    this.color = WtmColors.gold,
  });

  final WtmFigureKind kind;

  /// Board tiles vary this (.8 hero, .55/.45 minis).
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        painter: _FigurePainter(kind, color),
        size: kind == WtmFigureKind.form
            ? const Size(200, 320)
            : const Size(240, 560),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  const _FigurePainter(this.kind, this.color);

  final WtmFigureKind kind;
  final Color color;

  static const _glow = Color(0x40D9BE95); // rgba(217,190,149,.25)

  @override
  void paint(Canvas canvas, Size size) {
    final viewBox = kind == WtmFigureKind.form
        ? const Size(200, 320)
        : const Size(240, 560);
    final scale = (size.width / viewBox.width)
        .clamp(0.0, size.height / viewBox.height)
        .toDouble();
    canvas.translate(
      (size.width - viewBox.width * scale) / 2,
      (size.height - viewBox.height * scale) / 2,
    );
    canvas.scale(scale);

    final paths = kind == WtmFigureKind.form ? _formPaths() : _bodyPaths();
    // Glow pass, then crisp stroke (CSS drop-shadow approximation).
    final glowPaint = Paint()
      ..color = _glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final path in paths) {
      canvas.drawPath(path, glowPaint);
    }
    for (final path in paths) {
      canvas.drawPath(path, strokePaint);
    }
  }

  // fig-form: dress form on a stand (200×320).
  static List<Path> _formPaths() {
    return [
      Path()..addOval(Rect.fromCircle(center: const Offset(100, 24), radius: 8)),
      Path()
        ..moveTo(100, 32)
        ..lineTo(100, 42),
      Path()
        ..moveTo(74, 50)
        ..cubicTo(74, 44, 86, 42, 100, 42)
        ..cubicTo(114, 42, 126, 44, 126, 50)
        ..lineTo(131, 94)
        ..cubicTo(133, 114, 124, 130, 122, 146)
        ..cubicTo(120, 162, 129, 180, 131, 198)
        ..cubicTo(133, 222, 118, 236, 100, 236)
        ..cubicTo(82, 236, 67, 222, 69, 198)
        ..cubicTo(71, 180, 80, 162, 78, 146)
        ..cubicTo(76, 130, 67, 114, 69, 94)
        ..close(),
      Path()
        ..moveTo(100, 236)
        ..lineTo(100, 276),
      Path()
        ..moveTo(100, 262)
        ..lineTo(76, 278),
      Path()
        ..moveTo(100, 262)
        ..lineTo(124, 278),
    ];
  }

  // fig-body: full body outline (240×560) — used from P4 (MoodMirror portal).
  static List<Path> _bodyPaths() {
    return [
      Path()..addOval(Rect.fromCircle(center: const Offset(120, 56), radius: 24)),
      Path()
        ..moveTo(120, 82)
        ..lineTo(120, 102),
      Path()
        ..moveTo(66, 122)
        ..cubicTo(88, 102, 152, 102, 174, 122),
      Path()
        ..moveTo(66, 122)
        ..cubicTo(56, 168, 54, 214, 60, 252)
        ..cubicTo(62, 262, 66, 268, 72, 270),
      Path()
        ..moveTo(174, 122)
        ..cubicTo(184, 168, 186, 214, 180, 252)
        ..cubicTo(178, 262, 174, 268, 168, 270),
      Path()
        ..moveTo(94, 118)
        ..cubicTo(88, 162, 96, 196, 90, 232),
      Path()
        ..moveTo(146, 118)
        ..cubicTo(152, 162, 144, 196, 150, 232),
      Path()
        ..moveTo(90, 232)
        ..cubicTo(78, 274, 84, 300, 88, 322)
        ..cubicTo(92, 372, 96, 430, 98, 486),
      Path()
        ..moveTo(150, 232)
        ..cubicTo(162, 274, 156, 300, 152, 322)
        ..cubicTo(148, 372, 144, 430, 142, 486),
      Path()
        ..moveTo(120, 330)
        ..lineTo(120, 486),
      Path()
        ..moveTo(90, 490)
        ..lineTo(106, 490),
      Path()
        ..moveTo(134, 490)
        ..lineTo(150, 490),
    ];
  }

  @override
  bool shouldRepaint(_FigurePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
