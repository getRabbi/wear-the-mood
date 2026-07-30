import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/shared/utils/image_format.dart';
import 'package:app/theme/wtm_colors.dart';
import 'package:app/ui/widgets/fabric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cutout presentation (Android ML Kit regression, 2026-07-30).
///
/// A correct, genuinely transparent PNG cutout was being drawn over three OPAQUE
/// decorative layers — swatch colorway, radial shade and diagonal sheen — so every
/// removed pixel was filled back in and the garment appeared on a glossy grey
/// panel. ML Kit, the mask, the backend and R2 were all provably correct; only the
/// presentation made the feature look dead. These tests pin the fix so it cannot
/// silently return.
void main() {
  /// Does the tree contain a decorative layer painted with [gradient]?
  bool hasGradient(WidgetTester tester, Gradient gradient) => tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .any((box) => (box.decoration as BoxDecoration).gradient == gradient);

  Future<void> pump(WidgetTester tester, {required bool isCutout}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                // imageUrl stays null on purpose: the decoration decision is
                // independent of loading, and it keeps the test off the network.
                child: FabricTile(swatchIndex: 3, isCutout: isCutout),
              ),
            ),
          ),
        ),
      );

  group('FabricTile decoration', () {
    testWidgets('a cutout omits all three opaque decorative layers', (
      tester,
    ) async {
      await pump(tester, isCutout: true);

      expect(
        hasGradient(tester, WtmSwatch.at(3)),
        isFalse,
        reason: 'the swatch colorway would fill in the removed background',
      );
      expect(
        hasGradient(tester, WtmGradients.swatchShadeRadial),
        isFalse,
        reason: 'the radial shade would fill in the removed background',
      );
      expect(
        hasGradient(tester, WtmGradients.sheen),
        isFalse,
        reason: 'the diagonal sheen is the gloss stripe seen over the cutout',
      );
    });

    testWidgets('a cutout sits on one flat neutral surface', (tester) async {
      await pump(tester, isCutout: true);

      final surfaces = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color == WtmColors.bg);
      expect(surfaces, isNotEmpty);
    });

    testWidgets('a normal photo keeps the full editorial tile face', (
      tester,
    ) async {
      await pump(tester, isCutout: false);

      expect(hasGradient(tester, WtmSwatch.at(3)), isTrue);
      expect(hasGradient(tester, WtmGradients.swatchShadeRadial), isTrue);
      expect(hasGradient(tester, WtmGradients.sheen), isTrue);
    });

    testWidgets('defaults to the decorated face when unspecified', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 200, child: FabricTile())),
          ),
        ),
      );
      // Every non-wardrobe caller relies on this default staying decorative.
      expect(hasGradient(tester, WtmGradients.sheen), isTrue);
    });
  });

  group('cache identity', () {
    test('a cutout and an original never share a cache key', () {
      const url = 'https://example.test/a/b.png?sig=abc';
      final cutout = renditionImageCacheKey(url, isCutout: true);
      final photo = renditionImageCacheKey(url, isCutout: false);

      expect(cutout, isNot(photo));
      // Expiring signature params still must not bust the cache.
      expect(
        renditionImageCacheKey(
          'https://example.test/a/b.png?sig=zzz',
          isCutout: true,
        ),
        cutout,
      );
    });

    test('the key keeps the stable path and drops the query', () {
      expect(
        renditionImageCacheKey('https://x.test/p.webp?e=1', isCutout: true),
        'cutout:https://x.test/p.webp',
      );
      expect(
        renditionImageCacheKey('https://x.test/p.jpg', isCutout: false),
        'photo:https://x.test/p.jpg',
      );
    });
  });

  group('WardrobeItem.displaysCutout — the authoritative rule', () {
    WardrobeItem item({
      String? cutoutStatus,
      String? cutoutUrl,
      String? thumbnailUrl,
      String? coverImageUrl,
      String? imageUrl = 'https://x.test/original.jpg',
    }) => WardrobeItem(
      id: 'i1',
      cutoutStatus: cutoutStatus,
      cutoutUrl: cutoutUrl,
      thumbnailUrl: thumbnailUrl,
      coverImageUrl: coverImageUrl,
      imageUrl: imageUrl,
    );

    test('done with a WebP thumbnail is a cutout', () {
      // The server thumbnail is encoded from the cutout with RGBA preserved.
      expect(
        item(
          cutoutStatus: 'done',
          thumbnailUrl: 'https://x.test/t.webp',
          cutoutUrl: 'https://x.test/c.png',
        ).displaysCutout,
        isTrue,
      );
    });

    test('done with only a cutout URL is a cutout', () {
      expect(
        item(cutoutStatus: 'done', cutoutUrl: 'https://x.test/c.png')
            .displaysCutout,
        isTrue,
      );
    });

    test('an AI-enhanced cover is a photograph, not a cutout', () {
      // coverImageUrl wins in displayImageUrl and is a full composition.
      expect(
        item(
          cutoutStatus: 'done',
          cutoutUrl: 'https://x.test/c.png',
          thumbnailUrl: 'https://x.test/t.webp',
          coverImageUrl: 'https://x.test/cover.jpg',
        ).displaysCutout,
        isFalse,
      );
    });

    test('queued, processing and failed all still show the original', () {
      for (final status in ['queued', 'processing', 'failed', null]) {
        expect(
          item(cutoutStatus: status, cutoutUrl: 'https://x.test/c.png')
              .displaysCutout,
          isFalse,
          reason: 'status=$status',
        );
      }
    });

    test('a legacy done row with no cutout asset shows the original', () {
      // displayImageUrl falls through to imageUrl, which is an opaque JPEG.
      expect(item(cutoutStatus: 'done').displaysCutout, isFalse);
    });

    test('the rule agrees with what displayImageUrl actually picks', () {
      final cutout = item(
        cutoutStatus: 'done',
        thumbnailUrl: 'https://x.test/t.webp',
      );
      expect(cutout.displayImageUrl, 'https://x.test/t.webp');
      expect(cutout.displaysCutout, isTrue);

      final pending = item(cutoutStatus: 'processing');
      expect(pending.displayImageUrl, 'https://x.test/original.jpg');
      expect(pending.displaysCutout, isFalse);
    });
  });
}
