import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/share/ai_disclosure_watermark.dart';
import 'package:app/core/share/tryon_share_service.dart';

/// WHAT ACTUALLY LEAVES THE APP.
///
/// A watermark asserted on a widget proves nothing — the widget does not
/// travel. These tests read back the BYTES handed to the share sheet, decode
/// them, and compare them against the source, so "the disclosure is burned in"
/// is a statement about pixels rather than about intent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ios = PlatformCapabilities(platform: TargetPlatform.iOS);
  const android = PlatformCapabilities(platform: TargetPlatform.android);

  // `path_provider` has no implementation on a test host, so the app's own
  // temporary directory is stubbed to a real one this suite owns and cleans up.
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wtm-share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => temp.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    try {
      if (temp.existsSync()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Housekeeping, not an assertion.
    }
  });

  /// A plain mid-grey PNG, big enough for the watermark to have somewhere to go.
  Future<Uint8List> source({int w = 256, int h = 384}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF808080),
    );
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Decodes to raw RGBA so two images can be compared pixel for pixel.
  Future<({int width, int height, ByteData pixels})> decode(
    Uint8List bytes,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (width: image.width, height: image.height, pixels: data!);
    image.dispose();
    return result;
  }

  /// How many sampled pixels differ from the source, in a given band.
  Future<int> changedIn(
    Uint8List before,
    Uint8List after, {
    required double topFraction,
    required double bottomFraction,
  }) async {
    final a = await decode(before);
    final b = await decode(after);
    expect(b.width, a.width);
    expect(b.height, a.height);
    var changed = 0;
    final y0 = (a.height * topFraction).floor();
    final y1 = (a.height * bottomFraction).floor();
    for (var y = y0; y < y1; y++) {
      for (var x = 0; x < a.width; x++) {
        final i = (y * a.width + x) * 4;
        if (a.pixels.getUint32(i) != b.pixels.getUint32(i)) changed++;
      }
    }
    return changed;
  }

  group('the disclosure is burned into the pixels', () {
    test('the exported image differs from the source', () async {
      final src = await source();
      final out = await burnAiDisclosure(
        src,
        label: 'Wear The Mood',
        aiTag: 'AI-generated',
      );
      expect(out, isNot(equals(src)));
    });

    test('the footer band is marked', () async {
      final src = await source();
      final out = await burnAiDisclosure(
        src,
        label: 'Wear The Mood',
        aiTag: 'AI-generated',
      );
      final changed = await changedIn(
        src,
        out,
        topFraction: 0.88,
        bottomFraction: 1.0,
      );
      expect(changed, greaterThan(0), reason: 'the readable footer is present');
    });

    test('a CROP that removes the footer still carries a mark', () async {
      // The whole reason the lattice exists. Every horizontal band of the
      // image — including the top third, which survives the most aggressive
      // share-preview crop — must contain some of the disclosure.
      final src = await source(w: 512, h: 768);
      final out = await burnAiDisclosure(
        src,
        label: 'Wear The Mood',
        aiTag: 'AI-generated',
      );
      for (final band in const [
        (top: 0.0, bottom: 0.25),
        (top: 0.25, bottom: 0.5),
        (top: 0.5, bottom: 0.75),
      ]) {
        final changed = await changedIn(
          src,
          out,
          topFraction: band.top,
          bottomFraction: band.bottom,
        );
        expect(
          changed,
          greaterThan(0),
          reason: 'band ${band.top}-${band.bottom} must survive a crop',
        );
      }
    });

    test('the output keeps the source dimensions', () async {
      final src = await source(w: 300, h: 500);
      final out = await burnAiDisclosure(
        src,
        label: 'Wear The Mood',
        aiTag: 'AI-generated',
      );
      final decoded = await decode(out);
      expect(decoded.width, 300);
      expect(decoded.height, 500);
    });

    test('undecodable input FAILS rather than sharing an unmarked image', () {
      // Deliberately unlike the brand badge, which falls back to the original.
      // An undisclosed share is the one outcome this function exists to stop.
      expect(
        () => burnAiDisclosure(
          Uint8List.fromList([1, 2, 3]),
          label: 'Wear The Mood',
          aiTag: 'AI-generated',
        ),
        throwsA(anything),
      );
    });
  });

  group('the share service', () {
    late List<List<XFile>> shared;
    late List<String?> texts;
    late List<Uint8List> bytesAtShareTime;
    late List<String> pathsAtShareTime;

    /// Reads the bytes AT SHARE TIME, exactly as a receiving app would. The
    /// service deletes its temporary file once the sheet returns, so reading
    /// afterwards would prove nothing about what was actually sent.
    Future<void> record(List<XFile> files, {String? text}) async {
      shared.add(files);
      texts.add(text);
      for (final f in files) {
        bytesAtShareTime.add(await f.readAsBytes());
        pathsAtShareTime.add(f.path);
      }
    }

    setUp(() {
      shared = [];
      texts = [];
      bytesAtShareTime = [];
      pathsAtShareTime = [];
    });

    Future<Uint8List> sharedBytes() async {
      expect(shared, hasLength(1));
      return bytesAtShareTime.single;
    }

    test('iOS exports a WATERMARKED derivative', () async {
      final service = TryOnShareService(ios, share: record);
      final src = await source();
      await service.shareResult(
        src,
        text: 'Styled with Wear The Mood',
        watermarkLabel: 'Wear The Mood',
        watermarkAiTag: 'AI-generated',
      );

      expect(service.watermarks, isTrue);
      final out = await sharedBytes();
      expect(out, isNot(equals(src)), reason: 'the source must never be sent');
      final changed = await changedIn(
        src,
        out,
        topFraction: 0.0,
        bottomFraction: 1.0,
      );
      expect(changed, greaterThan(0));
      expect(texts.single, 'Styled with Wear The Mood');
    });

    test('iOS writes an app-private temp file and deletes it afterwards', () async {
      final service = TryOnShareService(ios, share: record);
      await service.shareResult(
        await source(),
        text: 't',
        watermarkLabel: 'Wear The Mood',
        watermarkAiTag: 'AI-generated',
      );
      final path = pathsAtShareTime.single;
      // Written inside the app's own temporary directory...
      expect(path, startsWith(temp.path));
      // ...and gone once the sheet returned.
      expect(File(path).existsSync(), isFalse);
    });

    test('ANDROID shares the exact source bytes, unchanged', () async {
      final service = TryOnShareService(android, share: record);
      final src = await source();
      await service.shareResult(
        src,
        text: 'Styled with Wear The Mood',
        watermarkLabel: 'Wear The Mood',
        watermarkAiTag: 'AI-generated',
      );

      expect(service.watermarks, isFalse);
      expect(await sharedBytes(), equals(src));
    });

    test('no other platform starts watermarking', () {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        expect(
          TryOnShareService(
            PlatformCapabilities(platform: platform),
            share: record,
          ).watermarks,
          isFalse,
          reason: platform.name,
        );
      }
    });

    test('exactly one file is handed to the sheet, per share', () async {
      final service = TryOnShareService(ios, share: record);
      await service.shareResult(
        await source(),
        text: 't',
        watermarkLabel: 'Wear The Mood',
        watermarkAiTag: 'AI-generated',
      );
      expect(shared.single, hasLength(1));
    });
  });
}
