import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/models/wardrobe_item.dart';

/// Which rendition a card asks for.
///
/// THIRD-party editorial media is handled by `imageRenditionUrl`, which asks the
/// publisher's CDN for a size. FIRST-party media cannot be resized on the way
/// out — an R2 object is whatever bytes were stored — so the small version has
/// to exist as its own object and the card has to ask for it by name.
///
/// The gap these pin: `displayImageUrl` leads with the AI-enhanced cover, which
/// is a full-resolution generated composition and had no rendition of its own,
/// so Today's Look drew it at roughly 80 dp; and a try-on result — the largest
/// image the app stores per user — filled a three-across history tile at full
/// size. `memCacheWidth` capped the decode on both and neither download shrank.
void main() {
  const cover = 'https://r2.test/u1/enhance/cover.png?X-Amz-Signature=a';
  const coverThumb =
      'https://r2.test/u1/enhance/thumb/cover.webp?X-Amz-Signature=b';
  const cutout = 'https://r2.test/u1/cutout/piece.png?X-Amz-Signature=c';
  const cutoutThumb =
      'https://r2.test/u1/cutout/thumb/piece.webp?X-Amz-Signature=d';
  const original = 'https://r2.test/u1/wardrobe/photo.jpg?X-Amz-Signature=e';

  group('a closet card asks for the rendition, not the render', () {
    test('an AI-enhanced item asks for the COVER thumbnail', () {
      const item = WardrobeItem(
        id: 'w1',
        cutoutStatus: 'done',
        imageUrl: original,
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
        coverImageUrl: cover,
        coverThumbnailUrl: coverThumb,
        aiEnhanced: true,
      );

      expect(item.cardImageUrl, coverThumb);
      expect(
        item.cardImageUrl,
        isNot(cover),
        reason: 'this is the defect — a full generated render at ~80 dp',
      );
      expect(
        item.cardImageUrl,
        isNot(cutoutThumb),
        reason: "the cutout's thumbnail is a picture of something else",
      );
    });

    test('the detail view still gets the full cover', () {
      const item = WardrobeItem(
        id: 'w1',
        coverImageUrl: cover,
        coverThumbnailUrl: coverThumb,
      );
      expect(item.displayImageUrl, cover);
    });

    test('an ordinary item asks for the cutout thumbnail', () {
      const item = WardrobeItem(
        id: 'w1',
        cutoutStatus: 'done',
        imageUrl: original,
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
      );
      expect(item.cardImageUrl, cutoutThumb);
      expect(item.cardImageUrl, isNot(cutout));
      expect(item.cardImageUrl, isNot(original));
    });

    test('a cover with no rendition yet falls back to the cover', () {
      // Pre-backfill, and every legacy Supabase cover. Never a blank card.
      const item = WardrobeItem(
        id: 'w1',
        cutoutStatus: 'done',
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
        coverImageUrl: cover,
      );
      expect(item.cardImageUrl, cover);
    });

    test(
      'an item with no media at all still resolves to nothing, not a throw',
      () {
        const item = WardrobeItem(id: 'w1');
        expect(item.cardImageUrl, isNull);
        expect(item.displayImageUrl, isNull);
      },
    );

    test('the card and the detail always show the SAME picture', () {
      // Different sizes of one image, never two different images — otherwise a
      // tap would appear to open something else.
      const withCover = WardrobeItem(
        id: 'w1',
        cutoutStatus: 'done',
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
        coverImageUrl: cover,
        coverThumbnailUrl: coverThumb,
      );
      const withoutCover = WardrobeItem(
        id: 'w2',
        cutoutStatus: 'done',
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
      );

      // Both members of each pair come from the same source object.
      expect(withCover.cardImageUrl, coverThumb);
      expect(withCover.displayImageUrl, cover);
      expect(withoutCover.cardImageUrl, cutoutThumb);
      expect(withoutCover.displayImageUrl, cutoutThumb);
    });

    test('cutout presentation is unchanged by the card/detail split', () {
      // `displaysCutout` decides whether the decorative tile face is drawn
      // behind a transparent PNG. Both getters share one precedence, so it
      // describes either.
      const enhanced = WardrobeItem(
        id: 'w1',
        cutoutStatus: 'done',
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
        coverImageUrl: cover,
        coverThumbnailUrl: coverThumb,
      );
      expect(
        enhanced.displaysCutout,
        isFalse,
        reason: 'a cover is a photograph',
      );

      const plain = WardrobeItem(
        id: 'w2',
        cutoutStatus: 'done',
        cutoutUrl: cutout,
        thumbnailUrl: cutoutThumb,
      );
      expect(plain.displaysCutout, isTrue);
    });
  });

  group('a history tile asks for the rendition, not the render', () {
    test('a result with a thumbnail asks for it', () {
      const result = TryonResult(
        id: 'j1',
        resultImageUrl: 'https://r2.test/u1/result/look.png?X-Amz-Signature=a',
        thumbnailUrl:
            'https://r2.test/u1/result/thumb/look.webp?X-Amz-Signature=b',
      );
      expect(result.cardImageUrl, result.thumbnailUrl);
      expect(result.cardImageUrl, isNot(result.resultImageUrl));
    });

    test('a result without one still draws, at full size', () {
      const result = TryonResult(
        id: 'j1',
        resultImageUrl: 'https://r2.test/u1/result/look.png?X-Amz-Signature=a',
      );
      expect(result.cardImageUrl, result.resultImageUrl);
    });

    test('a result with no image at all resolves to null', () {
      const result = TryonResult(id: 'j1');
      expect(result.cardImageUrl, isNull);
    });
  });

  group('the wire contract', () {
    test('cover_thumbnail_url is read off the response', () {
      final item = WardrobeItem.fromJson(const {
        'id': 'w1',
        'cover_image_url': cover,
        'cover_thumbnail_url': coverThumb,
        'ai_enhanced': true,
      });
      expect(item.coverThumbnailUrl, coverThumb);
      expect(item.cardImageUrl, coverThumb);
    });

    test('an older backend that omits it still parses', () {
      // The field is additive; a client ahead of the server must not crash, it
      // must simply keep drawing the full cover.
      final item = WardrobeItem.fromJson(const {
        'id': 'w1',
        'cover_image_url': cover,
      });
      expect(item.coverThumbnailUrl, isNull);
      expect(item.cardImageUrl, cover);
    });

    test('thumbnail_url is read off a try-on result', () {
      final result = TryonResult.fromJson(const {
        'id': 'j1',
        'result_image_url': 'https://r2.test/full.png',
        'thumbnail_url': 'https://r2.test/thumb.webp',
      });
      expect(result.cardImageUrl, 'https://r2.test/thumb.webp');
    });
  });
}
