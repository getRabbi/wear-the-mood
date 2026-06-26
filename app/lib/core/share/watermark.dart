import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Brand watermark for shared try-on images (CLAUDE.md Phase 1 — "watermarked
/// share"; removed for HD/premium per the paywall promise). Composites a small,
/// tasteful pill in the bottom-right via `dart:ui` — no extra dependency.
///
/// Shows the brand [label] with an optional smaller [tagline] beneath it.
///
/// Returns PNG bytes the size of the source. On any decode/encode failure it
/// returns the ORIGINAL bytes so sharing never breaks (the caller still shares
/// something).
Future<Uint8List> addWatermark(
  Uint8List source, {
  String label = 'Wear The Mood',
  String? tagline = 'AI Try-On',
}) async {
  try {
    final codec = await ui.instantiateImageCodec(source);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(image, Offset.zero, Paint());

    // Scale the badge to the image so it reads on any resolution.
    final fontSize = (w * 0.040).clamp(16.0, 56.0);
    final padX = fontSize * 0.7;
    final padY = fontSize * 0.45;
    final margin = fontSize * 0.7;
    final hasTag = tagline != null && tagline.isNotEmpty;

    final tp = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          shadows: [
            Shadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (hasTag)
            TextSpan(
              text: '\n$tagline',
              style: TextStyle(
                fontSize: fontSize * 0.72,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    )..layout();

    final pillW = tp.width + padX * 2;
    final pillH = tp.height + padY * 2;
    final left = w - pillW - margin;
    final top = h - pillH - margin;
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, pillW, pillH),
      Radius.circular(fontSize * 0.7),
    );
    canvas.drawRRect(pill, Paint()..color = const Color(0x66000000));
    tp.paint(canvas, Offset(left + padX, top + padY));

    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    out.dispose();
    if (data == null) return source;
    return data.buffer.asUint8List();
  } catch (_) {
    return source; // never let a watermark failure block the share
  }
}
