import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/core/share/watermark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A solid-color PNG of the given size, used as a stand-in try-on result.
Future<Uint8List> _solidPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF334455),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<({int w, int h})> _dimensions(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  return (w: frame.image.width, h: frame.image.height);
}

void main() {
  // dart:ui image encoding runs on real platform threads, so these must run
  // inside tester.runAsync (outside the widget-test fake-async zone).
  testWidgets('addWatermark returns a valid PNG at the source size', (tester) async {
    await tester.runAsync(() async {
      final src = await _solidPng(400, 600);
      final out = await addWatermark(src); // defaults: "Wear The Mood" + "AI Try-On"

      expect(out, isNotEmpty);
      final dim = await _dimensions(out);
      expect(dim.w, 400);
      expect(dim.h, 600);
    });
  });

  testWidgets('addWatermark falls back to the original bytes on bad input', (tester) async {
    await tester.runAsync(() async {
      final junk = Uint8List.fromList([0, 1, 2, 3, 4]); // not a decodable image
      final out = await addWatermark(junk);
      expect(out, equals(junk)); // never throws; returns the source so sharing works
    });
  });
}
