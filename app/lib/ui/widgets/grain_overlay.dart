import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Film-grain overlay (UI_IMPLEMENTATION.md §1.1 aurora recipe) — tiles
/// `assets/textures/grain.png` (140px noise) over whatever is beneath it with
/// `BlendMode.overlay` at 9% opacity, matching the board's `.grain` layer
/// (`mix-blend-mode: overlay; opacity: .09`).
///
/// Purely decorative and static (no motion, nothing to reduce), ignores
/// pointers, and paints nothing until the shared texture decodes (one decode
/// per app run — all instances reuse it). Place inside a clipped Stack; it
/// fills its parent.
class GrainOverlay extends StatefulWidget {
  const GrainOverlay({
    super.key,
    this.opacity = 0.09,
    this.blendMode = BlendMode.overlay,
  });

  /// Grain strength — board default .09.
  final double opacity;

  /// Board default overlay; `BlendMode.srcOver` gives a brighter, chalkier
  /// grain if a surface ever needs it.
  final BlendMode blendMode;

  @override
  State<GrainOverlay> createState() => _GrainOverlayState();
}

class _GrainOverlayState extends State<GrainOverlay> {
  static const _asset = 'assets/textures/grain.png';
  static ui.Image? _grain;
  static Future<ui.Image>? _loading;

  @override
  void initState() {
    super.initState();
    if (_grain == null) {
      (_loading ??= _decode()).then((image) {
        _grain = image;
        if (mounted) setState(() {});
      });
    }
  }

  static Future<ui.Image> _decode() async {
    final data = await rootBundle.load(_asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  @override
  Widget build(BuildContext context) {
    final grain = _grain;
    if (grain == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _GrainPainter(grain, widget.opacity, widget.blendMode),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.image, this.opacity, this.blendMode);

  final ui.Image image;
  final double opacity;
  final BlendMode blendMode;

  @override
  void paint(Canvas canvas, Size size) {
    // The texture tiles at its native 140px (logical px — same scale as the
    // board's CSS `background-image`). With a shader set, the paint color's
    // alpha modulates the shader output, giving the 9% grain opacity.
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      )
      ..blendMode = blendMode
      ..color = Color.fromRGBO(0xFF, 0xFF, 0xFF, opacity);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.opacity != opacity ||
      oldDelegate.blendMode != blendMode;
}
