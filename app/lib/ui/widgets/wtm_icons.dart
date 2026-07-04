import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';

/// The board's 1.5-stroke rounded icon language (UI_IMPLEMENTATION.md §4),
/// drawn from the HTML `<symbol>` paths on their 24-unit viewBox.
enum WtmGlyph {
  // Nav
  home,
  users,
  inbox,
  user,
  // Common chrome
  back,
  chevron,
  check,
  plus,
  bell,
  search,
  filter,
  dots,
  // Content & actions
  sparkle,
  camera,
  heart,
  comment,
  bookmark,
  hanger,
  shirt,
  image,
  store,
  coin,
  gift,
  sliders,
  shield,
  ruler,
  help,
  // Editor rail
  crop,
  rotate,
  erase,
  swap,
  wand,
  layers,
}

/// A single stroked glyph. [strokeWidth] is in viewBox units like the CSS
/// (`.ic` = 1.5, `.ic-xs` = 1.7) and scales with [size].
class WtmIcon extends StatelessWidget {
  const WtmIcon(
    this.glyph, {
    super.key,
    this.size = 19,
    this.color = WtmColors.text,
    this.strokeWidth = 1.5,
  });

  final WtmGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, color, strokeWidth),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color, this.strokeWidth);

  final WtmGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24; // viewBox → px
    canvas.scale(s);
    // The dots glyph is the board's one filled symbol.
    if (glyph == WtmGlyph.dots) {
      final fill = Paint()..color = color;
      canvas.drawCircle(const Offset(5, 12), 1.2, fill);
      canvas.drawCircle(const Offset(12, 12), 1.2, fill);
      canvas.drawCircle(const Offset(19, 12), 1.2, fill);
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in _paths(glyph)) {
      canvas.drawPath(path, paint);
    }
  }

  // Board `<symbol>` path data, 24-unit viewBox. Arcs use arcToPoint with the
  // SVG largeArc/sweep flags (sweep 1 → clockwise in y-down coords).
  static List<Path> _paths(WtmGlyph glyph) {
    switch (glyph) {
      case WtmGlyph.home: // M4 11 12 4l8 7v9h-5.5v-5h-5v5H4z
        return [
          Path()
            ..moveTo(4, 11)
            ..lineTo(12, 4)
            ..lineTo(20, 11)
            ..lineTo(20, 20)
            ..lineTo(14.5, 20)
            ..lineTo(14.5, 15)
            ..lineTo(9.5, 15)
            ..lineTo(9.5, 20)
            ..lineTo(4, 20)
            ..close(),
        ];
      case WtmGlyph.users:
        return [
          Path()..addOval(Rect.fromCircle(center: const Offset(9, 8.5), radius: 3)),
          Path()
            ..moveTo(3.5, 19)
            ..cubicTo(4.1, 15.6, 6.5, 14, 9, 14)
            ..cubicTo(11.5, 14, 13.9, 15.6, 14.5, 19),
          Path()
            ..addOval(Rect.fromCircle(center: const Offset(17, 9.5), radius: 2.3)),
          Path()
            ..moveTo(15.2, 14.7)
            ..cubicTo(17.7, 15.0, 19.5, 16.5, 20.1, 19.0),
        ];
      case WtmGlyph.inbox:
        return [
          Path()
            ..moveTo(3.5, 13)
            ..lineTo(6, 5.5)
            ..lineTo(18, 5.5)
            ..lineTo(20.5, 13)
            ..lineTo(20.5, 18.5)
            ..lineTo(3.5, 18.5)
            ..close(),
          Path()
            ..moveTo(3.5, 13)
            ..lineTo(8.5, 13)
            ..lineTo(9.9, 15.2)
            ..lineTo(14.1, 15.2)
            ..lineTo(15.5, 13)
            ..lineTo(20.5, 13),
        ];
      case WtmGlyph.user:
        return [
          Path()..addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 3.4)),
          Path()
            ..moveTo(5, 20)
            ..cubicTo(5.8, 16, 8.8, 14.4, 12, 14.4)
            ..cubicTo(15.2, 14.4, 18.2, 16, 19, 20),
        ];
      case WtmGlyph.back: // M14.5 5.5 8 12l6.5 6.5
        return [
          Path()
            ..moveTo(14.5, 5.5)
            ..lineTo(8, 12)
            ..lineTo(14.5, 18.5),
        ];
      case WtmGlyph.chevron: // m9.5 5.5 6.5 6.5-6.5 6.5
        return [
          Path()
            ..moveTo(9.5, 5.5)
            ..lineTo(16, 12)
            ..lineTo(9.5, 18.5),
        ];
      case WtmGlyph.check: // m5 12.5 5 5L19 7.5
        return [
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(10, 17.5)
            ..lineTo(19, 7.5),
        ];
      case WtmGlyph.plus: // M12 5v14M5 12h14
        return [
          Path()
            ..moveTo(12, 5)
            ..lineTo(12, 19),
          Path()
            ..moveTo(5, 12)
            ..lineTo(19, 12),
        ];
      case WtmGlyph.bell:
        return [
          Path()
            ..moveTo(6, 16)
            ..lineTo(6, 11)
            ..arcToPoint(const Offset(18, 11),
                radius: const Radius.circular(6), clockwise: true)
            ..lineTo(18, 16)
            ..lineTo(19.6, 18.2)
            ..lineTo(4.4, 18.2)
            ..close(),
          Path()
            ..moveTo(10.4, 20.4)
            ..arcToPoint(const Offset(13.6, 20.4),
                radius: const Radius.circular(1.8), clockwise: false),
        ];
      case WtmGlyph.search:
        return [
          Path()..addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 5.5)),
          Path()
            ..moveTo(15.4, 15.4)
            ..lineTo(20, 20),
        ];
      case WtmGlyph.filter: // M4 6.5h16M7.5 12h9M10.5 17.5h3
        return [
          Path()
            ..moveTo(4, 6.5)
            ..lineTo(20, 6.5),
          Path()
            ..moveTo(7.5, 12)
            ..lineTo(16.5, 12),
          Path()
            ..moveTo(10.5, 17.5)
            ..lineTo(13.5, 17.5),
        ];
      case WtmGlyph.dots:
        return const []; // filled — handled in paint()
      case WtmGlyph.sparkle:
        return [
          Path()
            ..moveTo(12, 3.5)
            ..lineTo(13.7, 8.3)
            ..lineTo(18.5, 10)
            ..lineTo(13.7, 11.7)
            ..lineTo(12, 16.5)
            ..lineTo(10.3, 11.7)
            ..lineTo(5.5, 10)
            ..lineTo(10.3, 8.3)
            ..close(),
          Path()
            ..moveTo(18.5, 15.5)
            ..lineTo(19.2, 17.3)
            ..lineTo(21, 18)
            ..lineTo(19.2, 18.7)
            ..lineTo(18.5, 20.5)
            ..lineTo(17.8, 18.7)
            ..lineTo(16, 18)
            ..lineTo(17.8, 17.3)
            ..close(),
        ];
      case WtmGlyph.camera:
        return [
          Path()
            ..moveTo(4, 8)
            ..lineTo(7.6, 8)
            ..lineTo(9.5, 5.5)
            ..lineTo(14.5, 5.5)
            ..lineTo(16.4, 8)
            ..lineTo(20, 8)
            ..lineTo(20, 19)
            ..lineTo(4, 19)
            ..close(),
          Path()
            ..addOval(Rect.fromCircle(center: const Offset(12, 13.3), radius: 3)),
        ];
      case WtmGlyph.heart:
        return [
          Path()
            ..moveTo(12, 20)
            ..cubicTo(12, 20, 5.2, 15.7, 3.3, 11.2)
            ..arcToPoint(const Offset(12, 8.2),
                radius: const Radius.circular(4.8), clockwise: true)
            ..arcToPoint(const Offset(20.7, 11.2),
                radius: const Radius.circular(4.8), clockwise: true)
            ..cubicTo(18.8, 15.7, 12, 20, 12, 20)
            ..close(),
        ];
      case WtmGlyph.comment: // M4 5.5h16v10.5H10L5 20v-4H4z
        return [
          Path()
            ..moveTo(4, 5.5)
            ..lineTo(20, 5.5)
            ..lineTo(20, 16)
            ..lineTo(10, 16)
            ..lineTo(5, 20)
            ..lineTo(5, 16)
            ..lineTo(4, 16)
            ..close(),
        ];
      case WtmGlyph.bookmark: // M7 4h10v16l-5-3.6L7 20z
        return [
          Path()
            ..moveTo(7, 4)
            ..lineTo(17, 4)
            ..lineTo(17, 20)
            ..lineTo(12, 16.4)
            ..lineTo(7, 20)
            ..close(),
        ];
      case WtmGlyph.hanger:
        return [
          Path()
            ..moveTo(12, 9.2)
            ..lineTo(12, 7.6)
            ..arcToPoint(const Offset(14.3, 5.3),
                radius: const Radius.circular(2.3),
                largeArc: true,
                clockwise: true),
          Path()
            ..moveTo(12, 9.2)
            ..lineTo(3.5, 15.6)
            ..lineTo(20.5, 15.6)
            ..close(),
        ];
      case WtmGlyph.shirt:
        return [
          Path()
            ..moveTo(8, 4)
            ..lineTo(12, 6)
            ..lineTo(16, 4)
            ..lineTo(20.5, 8)
            ..lineTo(17.5, 10.2)
            ..lineTo(17.5, 20)
            ..lineTo(6.5, 20)
            ..lineTo(6.5, 10.2)
            ..lineTo(3.5, 8)
            ..close(),
        ];
      case WtmGlyph.image:
        return [
          Path()
            ..addRRect(RRect.fromRectAndRadius(
                const Rect.fromLTWH(4, 5, 16, 14), const Radius.circular(2.5))),
          Path()..addOval(Rect.fromCircle(center: const Offset(9, 10), radius: 1.5)),
          Path()
            ..moveTo(5.5, 17)
            ..lineTo(9.8, 13.2)
            ..lineTo(12.8, 15.8)
            ..lineTo(16.2, 12.8)
            ..lineTo(18.5, 14.8),
        ];
      case WtmGlyph.store:
        return [
          Path()
            ..moveTo(4, 9)
            ..lineTo(5.6, 4.5)
            ..lineTo(18.4, 4.5)
            ..lineTo(20, 9),
          Path()
            ..moveTo(4.5, 9)
            ..lineTo(4.5, 19.5)
            ..lineTo(19.5, 19.5)
            ..lineTo(19.5, 9),
          Path()
            ..moveTo(9.5, 19.5)
            ..lineTo(9.5, 14.5)
            ..lineTo(14.5, 14.5)
            ..lineTo(14.5, 19.5),
        ];
      case WtmGlyph.coin:
        return [
          Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 7.5)),
          Path()
            ..moveTo(12, 8)
            ..lineTo(13, 10.6)
            ..lineTo(15.6, 11.6)
            ..lineTo(13, 12.6)
            ..lineTo(12, 15.2)
            ..lineTo(11, 12.6)
            ..lineTo(8.4, 11.6)
            ..lineTo(11, 10.6)
            ..close(),
        ];
      case WtmGlyph.gift:
        return [
          Path()
            ..moveTo(4.5, 9)
            ..lineTo(19.5, 9)
            ..lineTo(19.5, 12)
            ..lineTo(4.5, 12)
            ..close(),
          Path()
            ..moveTo(6, 12)
            ..lineTo(6, 20)
            ..lineTo(18, 20)
            ..lineTo(18, 12),
          Path()
            ..moveTo(12, 9)
            ..lineTo(12, 20),
          Path()
            ..moveTo(12, 9)
            ..cubicTo(10, 9, 7.6, 8.4, 7.6, 6.6)
            ..cubicTo(7.6, 5.2, 9, 4.6, 10, 5.2)
            ..cubicTo(11.3, 6, 12, 9, 12, 9)
            ..cubicTo(12, 9, 12.7, 6, 14, 5.2)
            ..cubicTo(15, 4.6, 16.4, 5.2, 16.4, 6.6)
            ..cubicTo(16.4, 8.4, 14, 9, 12, 9)
            ..close(),
        ];
      case WtmGlyph.sliders:
        return [
          Path()
            ..moveTo(4, 7.5)
            ..lineTo(20, 7.5),
          Path()
            ..moveTo(4, 12)
            ..lineTo(20, 12),
          Path()
            ..moveTo(4, 16.5)
            ..lineTo(20, 16.5),
          Path()..addOval(Rect.fromCircle(center: const Offset(15, 7.5), radius: 1.9)),
          Path()..addOval(Rect.fromCircle(center: const Offset(8.5, 12), radius: 1.9)),
          Path()..addOval(Rect.fromCircle(center: const Offset(13, 16.5), radius: 1.9)),
        ];
      case WtmGlyph.shield:
        return [
          Path()
            ..moveTo(12, 3.5)
            ..lineTo(19, 6.1)
            ..lineTo(19, 11.1)
            ..cubicTo(19, 15.6, 16.1, 18.5, 12, 20)
            ..cubicTo(7.9, 18.5, 5, 15.6, 5, 11.1)
            ..lineTo(5, 6.1)
            ..close(),
        ];
      case WtmGlyph.ruler:
        return [
          Path()
            ..moveTo(3.5, 15.5)
            ..lineTo(15.5, 3.5)
            ..lineTo(20.5, 8.5)
            ..lineTo(8.5, 20.5)
            ..close(),
          Path()
            ..moveTo(7.6, 13.4)
            ..lineTo(9.1, 14.9),
          Path()
            ..moveTo(10.6, 10.4)
            ..lineTo(12.1, 11.9),
          Path()
            ..moveTo(13.6, 7.4)
            ..lineTo(15.1, 8.9),
        ];
      case WtmGlyph.help:
        return [
          Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8.3)),
          Path()
            ..moveTo(9.7, 9.6)
            ..arcToPoint(const Offset(13.2, 11.7),
                radius: const Radius.circular(2.4),
                largeArc: true,
                clockwise: true)
            ..cubicTo(12.4, 12.1, 12, 12.7, 12, 13.5),
          Path()
            ..moveTo(12, 17)
            ..lineTo(12.02, 17),
        ];
      case WtmGlyph.crop: // M7 3v14h14M3 7h14v14
        return [
          Path()
            ..moveTo(7, 3)
            ..lineTo(7, 17)
            ..lineTo(21, 17),
          Path()
            ..moveTo(3, 7)
            ..lineTo(17, 7)
            ..lineTo(17, 21),
        ];
      case WtmGlyph.rotate:
        return [
          Path()
            ..moveTo(20, 12)
            ..arcToPoint(const Offset(17.6, 6.3),
                radius: const Radius.circular(8),
                largeArc: true,
                clockwise: true),
          Path()
            ..moveTo(18, 3.2)
            ..lineTo(18, 7.2)
            ..lineTo(14, 7.2),
        ];
      case WtmGlyph.erase:
        return [
          Path()
            ..moveTo(4.5, 15)
            ..lineTo(12.5, 6.5)
            ..lineTo(18, 11.7)
            ..lineTo(10, 20)
            ..lineTo(7, 20)
            ..close(),
          Path()
            ..moveTo(13.5, 20)
            ..lineTo(20, 20),
        ];
      case WtmGlyph.swap:
        return [
          Path()
            ..moveTo(7, 8.5)
            ..lineTo(18, 8.5)
            ..lineTo(14.8, 5.3),
          Path()
            ..moveTo(17, 15.5)
            ..lineTo(6, 15.5)
            ..lineTo(9.2, 18.7),
        ];
      case WtmGlyph.wand:
        return [
          Path()
            ..moveTo(5, 19)
            ..lineTo(14, 10),
          Path()
            ..moveTo(16.8, 3.5)
            ..lineTo(17.7, 5.6)
            ..lineTo(19.8, 6.5)
            ..lineTo(17.7, 7.4)
            ..lineTo(16.8, 9.5)
            ..lineTo(15.9, 7.4)
            ..lineTo(13.8, 6.5)
            ..lineTo(15.9, 5.6)
            ..close(),
          Path()
            ..moveTo(19, 13.5)
            ..lineTo(19.5, 14.7)
            ..lineTo(20.7, 15.2)
            ..lineTo(19.5, 15.7)
            ..lineTo(19, 16.9)
            ..lineTo(18.5, 15.7)
            ..lineTo(17.3, 15.2)
            ..lineTo(18.5, 14.7)
            ..close(),
        ];
      case WtmGlyph.layers:
        return [
          Path()
            ..moveTo(12, 4)
            ..lineTo(20, 8.4)
            ..lineTo(12, 12.8)
            ..lineTo(4, 8.4)
            ..close(),
          Path()
            ..moveTo(4.5, 13.6)
            ..lineTo(12, 17.8)
            ..lineTo(19.5, 13.6),
        ];
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
