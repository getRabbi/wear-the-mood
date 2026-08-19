import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/widgets/aspect_safe_media.dart';

/// Issue 1 regression: a photograph's proportions must survive presentation.
///
/// The shipped defect was NOT a stretch — every stage of the upload pipeline
/// preserves the ratio exactly. It was a fixed near-square container plus
/// `BoxFit.contain`, which turned an ordinary 9:16 phone photo into a ribbon
/// down the middle of the arch, and `BoxFit.cover` elsewhere, which paid for a
/// filled frame with the subject's head and feet.
///
/// So these tests assert the two things that actually failed on a device:
///
///  * the painted media keeps the SOURCE ratio (never distorted), and
///  * it uses a real share of the available width (never a ribbon),
///
/// across the exact source geometries the QA matrix names.

/// One real camera/gallery geometry from the required matrix.
class _Fixture {
  const _Fixture(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;

  double get ratio => width / height;

  /// The same shape at a decodable size.
  ///
  /// `createTestImage` builds its pixel buffer with
  /// `List<int>.filled(width * height * 4, 0)` — 64-bit elements before the
  /// `Uint8List` copy — so a genuine 3024x4032 fixture asks for ~390 MB and
  /// stalls the runner outright (it did: every widget case reported "did not
  /// complete"). Reducing by the GCD keeps the ratio EXACT, which is the only
  /// property under test here; the full-size numbers above are still what the
  /// pure-geometry cases assert against, and those decode nothing.
  int get _divisor => _gcd(width, height);
  int get probeWidth => width ~/ _divisor;
  int get probeHeight => height ~/ _divisor;

  @override
  String toString() => '$label (${width}x$height)';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// The required matrix. The EXIF case is the post-decode geometry on purpose:
/// `image_picker` bakes the camera rotation in and the backend applies
/// `ImageOps.exif_transpose` exactly once, so by the time any widget sees the
/// image a rotated portrait IS a portrait. Asserting the rotated dimensions is
/// what pins "orientation is normalised once, and presentation trusts it".
const _fixtures = <_Fixture>[
  _Fixture('tall phone portrait 9:16', 1080, 1920),
  _Fixture('iPhone portrait 3:4', 3024, 4032),
  _Fixture('DSLR portrait 3:4', 3000, 4000),
  _Fixture('square', 1024, 1024),
  _Fixture('landscape 4:3', 4032, 3024),
  _Fixture('EXIF-rotated portrait', 3024, 4032),
];

/// Ratio drift we will tolerate between source and painted media. Tight enough
/// that a genuine stretch cannot hide inside it.
const _tolerance = 0.002;

/// The old MoodMirror step 1 geometry, kept as the thing being beaten.
const _legacyBoxWidth = 320.0;
const _legacyBoxHeight = 322.0;

/// An [ImageProvider] over an ALREADY-DECODED image of known pixel dimensions.
///
/// The image is created and awaited by the test before it gets here, so the
/// stream resolves synchronously and the framework never sees a leaked future.
class _FixedSizeImage extends ImageProvider<_FixedSizeImage> {
  const _FixedSizeImage(this.image, this.width, this.height);

  final ui.Image image;
  final int width;
  final int height;

  @override
  Future<_FixedSizeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FixedSizeImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FixedSizeImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _FixedSizeImage &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// A provider that never yields an image — a dead publisher URL, a purged cache
/// file, an offline device.
class _BrokenImage extends ImageProvider<_BrokenImage> {
  const _BrokenImage();

  @override
  Future<_BrokenImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_BrokenImage>(this);

  @override
  ImageStreamCompleter loadImage(_BrokenImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(Exception('unreachable')),
    );
  }

  @override
  bool operator ==(Object other) => other is _BrokenImage;

  @override
  int get hashCode => runtimeType.hashCode;
}

void main() {
  group('aspectSafeBoxSize derives height, never chooses it', () {
    for (final f in _fixtures) {
      test('${f.label}: box ratio tracks the source', () {
        final box = aspectSafeBoxSize(width: 320, sourceAspectRatio: f.ratio);
        // Inside the default bounds every fixture keeps its own shape exactly,
        // which is what makes `contain` a no-op rather than a letterbox.
        expect(box.width, 320);
        expect(box.width / box.height, closeTo(f.ratio, _tolerance));
      });
    }

    test('width is never altered — only height is derived', () {
      for (final f in _fixtures) {
        expect(aspectSafeBoxSize(width: 411, sourceAspectRatio: f.ratio).width, 411);
      }
    });

    test('an absurdly tall source is bounded, not obeyed', () {
      // 1:4 — a stitched screenshot. Without the clamp this is a 1280dp tower
      // that pushes every control off the screen.
      final box = aspectSafeBoxSize(width: 320, sourceAspectRatio: 0.25);
      expect(
        box.height,
        lessThanOrEqualTo(320 / AspectSafeMedia.defaultMinAspectRatio),
      );
      expect(box.height / box.width, lessThan(2.0));
    });

    test('an absurdly wide source is bounded, not obeyed', () {
      final box = aspectSafeBoxSize(width: 320, sourceAspectRatio: 8);
      expect(box.height, greaterThan(0));
      expect(box.width / box.height, lessThanOrEqualTo(AspectSafeMedia.defaultMaxAspectRatio + _tolerance));
    });

    test('maxHeight clamps a tall photo without touching its pixels', () {
      final box = aspectSafeBoxSize(
        width: 320,
        sourceAspectRatio: 9 / 16,
        maxHeight: 460,
      );
      expect(box.height, 460);
      // The clamp bit, so `contain` letterboxes — but symmetrically, and the
      // media still keeps its own ratio.
      final drawn = containedMediaSize(
        box: box,
        source: const Size(1080, 1920),
      );
      expect(drawn.width / drawn.height, closeTo(9 / 16, _tolerance));
      expect(drawn.height, lessThanOrEqualTo(460));
    });

    test('minHeight keeps a landscape photo from collapsing to a band', () {
      final box = aspectSafeBoxSize(
        width: 320,
        sourceAspectRatio: 16 / 9,
        minHeight: 220,
      );
      expect(box.height, 220);
    });

    test('degenerate input falls back instead of producing NaN', () {
      expect(aspectSafeBoxSize(width: 0, sourceAspectRatio: 0.75), Size.zero);
      final box = aspectSafeBoxSize(width: 320, sourceAspectRatio: 0);
      expect(box.height.isFinite, isTrue);
      expect(box.height, greaterThan(0));
    });
  });

  group('painted media keeps the source ratio', () {
    for (final f in _fixtures) {
      test('${f.label}: no distortion', () {
        final box = aspectSafeBoxSize(width: 320, sourceAspectRatio: f.ratio);
        final drawn = containedMediaSize(
          box: box,
          source: Size(f.width.toDouble(), f.height.toDouble()),
        );
        expect(
          drawn.width / drawn.height,
          closeTo(f.ratio, _tolerance),
          reason: '$f must not be geometrically deformed',
        );
      });
    }
  });

  group('the ribbon is gone', () {
    // The acceptance number. In the shipped 320x322 arch a 9:16 photo painted
    // ~170dp wide — 53% of the column, with dead space either side. That is the
    // "abnormally long/narrow" the founder saw.
    test('legacy fixed box turned a 9:16 photo into a ribbon', () {
      final drawn = containedMediaSize(
        box: const Size(_legacyBoxWidth, _legacyBoxHeight),
        source: const Size(1080, 1920),
      );
      expect(drawn.width / _legacyBoxWidth, lessThan(0.6));
    });

    for (final f in _fixtures) {
      test('${f.label}: uses the column instead of a sliver', () {
        final box = aspectSafeBoxSize(
          width: 320,
          sourceAspectRatio: f.ratio,
          maxHeight: 460,
        );
        final drawn = containedMediaSize(
          box: box,
          source: Size(f.width.toDouble(), f.height.toDouble()),
        );
        expect(
          drawn.width / 320,
          greaterThan(0.75),
          reason: '$f should use most of the available width',
        );
      });
    }
  });

  group('AspectSafeMedia widget', () {
    // Decoded ONCE, outside the fake-async zone. `createTestImage` hands its
    // result back through the platform decode callback, which the automated
    // binding never pumps — awaiting it inside `testWidgets` deadlocks the
    // runner rather than failing (observed: every case "did not complete").
    final decoded = <String, ui.Image>{};
    setUpAll(() async {
      for (final f in _fixtures) {
        decoded[f.label] = await createTestImage(
          width: f.probeWidth,
          height: f.probeHeight,
        );
      }
    });

    Future<Size> boxOf(
      WidgetTester tester,
      _Fixture f, {
      double? maxHeight,
    }) async {
      final provider = _FixedSizeImage(
        decoded[f.label]!,
        f.probeWidth,
        f.probeHeight,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: AspectSafeMedia(
                  image: provider,
                  maxHeight: maxHeight,
                  child: Image(image: provider, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(AspectSafeMedia));
    }

    for (final f in _fixtures) {
      testWidgets('${f.label}: the box takes the image\'s shape', (tester) async {
        final size = await boxOf(tester, f);
        expect(size.width, 320);
        expect(size.width / size.height, closeTo(f.ratio, _tolerance));
      });
    }

    testWidgets('a tall photo is bounded by maxHeight, not by a crop', (
      tester,
    ) async {
      final size = await boxOf(tester, _fixtures.first, maxHeight: 400);
      expect(size.height, 400);
    });

    testWidgets('paints with contain, so nothing is ever cropped', (
      tester,
    ) async {
      await boxOf(tester, _fixtures.first);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.fit,
        BoxFit.contain,
        reason: 'cover would throw away head and feet',
      );
    });

    testWidgets('an unresolvable image keeps the fallback shape', (
      tester,
    ) async {
      // A broken URL must leave the surface's rhythm intact rather than
      // collapsing the slot to nothing — the error face belongs to the child.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: AspectSafeMedia(
                image: const _BrokenImage(),
                fallbackAspectRatio: 3 / 4,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final size = tester.getSize(find.byType(AspectSafeMedia));
      expect(size.width, 320);
      expect(size.width / size.height, closeTo(3 / 4, _tolerance));
    });
  });
}
