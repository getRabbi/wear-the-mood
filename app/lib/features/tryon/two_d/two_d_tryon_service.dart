import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The entire 2D try-on "engine": it composites the adjusted garment overlay onto
/// the body photo using native Flutter rendering and exports a PNG. No AI, no
/// network, no credits — this is what makes 2D free and instant.
class TwoDTryOnService {
  /// Captures the [RenderRepaintBoundary] behind [boundaryKey] (the body photo +
  /// the positioned garment overlay) to PNG bytes. Returns null if the boundary
  /// isn't ready. A higher [pixelRatio] preserves photo quality.
  Future<Uint8List?> capture(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.5,
  }) async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

final twoDTryOnServiceProvider = Provider<TwoDTryOnService>(
  (_) => TwoDTryOnService(),
);
