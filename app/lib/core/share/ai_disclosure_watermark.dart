import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Burns an AI-generation disclosure into a rendered try-on image.
///
/// This is NOT the existing brand badge in `watermark.dart`. That one is a
/// paywall device — a corner pill that HD/premium shares deliberately omit.
/// This one is a disclosure, so it is required on every iOS share regardless
/// of tier, and it is built to survive the thing a corner pill does not: an
/// ordinary crop.
///
/// Two marks, doing different jobs:
///
///  * a **legible footer band** across the bottom, which is what a person
///    actually reads; and
///  * a **repeating diagonal lattice** at low opacity across the whole frame,
///    so that cropping away the footer — at the system share preview, in
///    Photos, in any downstream editor — still leaves the disclosure in the
///    surviving pixels. One mark in one corner is one crop away from a
///    silently undisclosed AI image.
///
/// Returns PNG bytes the size of the source. Unlike the brand badge, a failure
/// here does NOT fall back to the original: an undisclosed share is the exact
/// outcome this function exists to prevent, so it rethrows and lets the caller
/// tell the user the share could not be prepared.
Future<Uint8List> burnAiDisclosure(
  Uint8List source, {
  required String label,
  required String aiTag,
}) async {
  final codec = await ui.instantiateImageCodec(source);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(image, Offset.zero, Paint());

    final text = '$aiTag • $label';
    // Scaled to the shorter edge so the mark reads the same on a 864x1296
    // render and on a square crop of one.
    final base = math.min(w, h);

    _paintLattice(canvas, w, h, base, text);
    _paintFooter(canvas, w, h, base, text);

    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('watermark encode produced no bytes');
      }
      return data.buffer.asUint8List();
    } finally {
      out.dispose();
      picture.dispose();
    }
  } finally {
    image.dispose();
  }
}

/// The crop-resistant half: the disclosure repeated on a rotated grid, faint
/// enough not to fight the render and dense enough that no plausible crop of a
/// person-sized subject can exclude every copy.
void _paintLattice(Canvas canvas, double w, double h, double base, String text) {
  final fontSize = (base * 0.030).clamp(11.0, 34.0);
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: fontSize * 0.05,
        color: Colors.white.withValues(alpha: 0.20),
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: fontSize * 0.18,
          ),
        ],
      ),
    ),
  )..layout();

  // Diagonal spacing chosen so a crop down to a quarter of each edge — a
  // heavier crop than a share sheet offers — still contains a full copy.
  final stepX = painter.width + base * 0.10;
  final stepY = painter.height + base * 0.16;
  final diagonal = math.sqrt(w * w + h * h);

  canvas.save();
  canvas.translate(w / 2, h / 2);
  canvas.rotate(-math.pi / 9); // ~-20°, so it never parallels a garment edge
  canvas.translate(-diagonal / 2, -diagonal / 2);
  for (var y = 0.0; y < diagonal; y += stepY) {
    // Offset alternate rows so the copies form a lattice rather than columns
    // with clear vertical corridors between them.
    final rowOffset = ((y / stepY).floor().isEven) ? 0.0 : stepX / 2;
    for (var x = -stepX; x < diagonal; x += stepX) {
      painter.paint(canvas, Offset(x + rowOffset, y));
    }
  }
  canvas.restore();
}

/// The legible half: a solid band the reader actually reads.
void _paintFooter(Canvas canvas, double w, double h, double base, String text) {
  final fontSize = (base * 0.042).clamp(15.0, 52.0);
  final painter = TextPainter(
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: fontSize * 0.03,
        color: Colors.white,
      ),
    ),
  )..layout(maxWidth: w * 0.92);

  final padY = fontSize * 0.55;
  final bandH = painter.height + padY * 2;
  final top = h - bandH;

  // A graded band rather than a flat bar: opaque enough under the text to be
  // readable on a white dress and a black suit alike, fading upward so it does
  // not look like a sticker slapped over the render.
  canvas.drawRect(
    Rect.fromLTWH(0, top, w, bandH),
    Paint()
      ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, h), [
        const Color(0x00000000),
        const Color(0xB3000000),
        const Color(0xD9000000),
      ], [0.0, 0.45, 1.0]),
  );
  painter.paint(canvas, Offset((w - painter.width) / 2, top + padY));
}
