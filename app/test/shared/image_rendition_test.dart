import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/utils/image_rendition.dart';

/// What the Newsroom, the Discover rail and the editorial cards actually ask
/// the network for.
///
/// The defect these pin: every one of those surfaces rendered a news item's
/// `image_url` straight from its RSS feed, and for the ingested sources that
/// URL is the untouched editorial master. Production, 2026-08-14 — 1 283 of the
/// 1 503 articles with images come from `assets.vogue.com`, and three sampled
/// masters measured 717 KB (3000×4500), 1.72 MB (3024×4032) and 7.94 MB
/// (3586×4482). The 7.94 MB one filled a 96×112 dp list thumbnail.
///
/// `memCacheWidth` never helped: it caps the DECODE, so the master still
/// crossed the network in full. These tests are about the URL, which is the
/// thing that decides how many bytes move.
void main() {
  const master =
      'https://assets.vogue.com/photos/6a7df3c57c43c883a806bf32/master/pass/'
      'tapestry-vogue-business-story.jpg';

  group('a publisher that publishes a size, gets asked for one', () {
    test('the master transform is replaced with the drawn width', () {
      expect(
        imageRenditionUrl(master, width: 320),
        'https://assets.vogue.com/photos/6a7df3c57c43c883a806bf32/master/'
        'w_320,c_limit/tapestry-vogue-business-story.jpg',
      );
    });

    test('c_limit, so an already-small asset is never upscaled', () {
      // Verified against the live CDN: w_320 on a 3000×4500 master returns
      // 320×480, and the same request on a narrower asset returns it as it is.
      expect(imageRenditionUrl(master, width: 320), contains('c_limit'));
    });

    test('the file name survives, escaping and all', () {
      const escaped =
          'https://assets.vogue.com/photos/6a72/master/pass/14%20(2)%20copy.png';
      final resolved = imageRenditionUrl(escaped, width: 640);
      expect(resolved, contains('/master/w_640,c_limit/'));
      expect(resolved, endsWith('14%20(2)%20copy.png'));
    });

    test('a wider slot asks for a wider rendition', () {
      expect(imageRenditionUrl(master, width: 900), contains('w_960,c_limit'));
      expect(imageRenditionUrl(master, width: 320), contains('w_320,c_limit'));
    });
  });

  group('widths land on a ladder, not on the exact pixel count', () {
    test('rounds UP, so nothing is drawn soft', () {
      expect(renditionWidth(1), 320);
      expect(renditionWidth(320), 320);
      expect(renditionWidth(321), 480);
      expect(renditionWidth(500), 640);
      expect(renditionWidth(900), 960);
    });

    test('caps at the top rung rather than asking for a master again', () {
      expect(renditionWidth(4000), 1280);
      expect(imageRenditionUrl(master, width: 4000), contains('w_1280'));
    });

    test('two nearby cards share one cached object', () {
      // The whole point of a ladder: a 300px and a 318px slot must not mint two
      // downloads of the same picture.
      expect(
        imageRenditionUrl(master, width: 300),
        imageRenditionUrl(master, width: 318),
      );
    });
  });

  group('everything else is left exactly alone', () {
    test('an unknown host is never rewritten', () {
      // Fashionista is why this caution exists. Its feed URLs already carry
      // `?profile=rss`, which IS the small rendition — measured, adding a
      // width parameter returned an image nearly 3x LARGER.
      const fashionista =
          'https://fashionista.com/.image/NTg6MDAwMDAwMDAwNzkyMzg2/'
          'a-view-of-the-side-entrance.jpg?profile=rss';
      expect(imageRenditionUrl(fashionista, width: 320), fashionista);
    });

    test('first-party signed media passes through byte for byte', () {
      // A closet cutout already arrives as the backend's 512px WebP thumbnail,
      // and its signature must not be touched.
      const signed =
          'https://acct.r2.cloudflarestorage.com/wtm-private/u1/cutout/thumb/'
          'abc.webp?X-Amz-Expires=3600&X-Amz-Signature=deadbeef';
      expect(imageRenditionUrl(signed, width: 320), signed);
    });

    test('a transform the publisher already chose is respected', () {
      // Only `pass` — "serve the master" — is replaced. A deliberate crop is
      // editorial intent, not something to overwrite.
      const cropped =
          'https://assets.vogue.com/photos/6a7d/master/w_1600,c_limit/x.jpg';
      expect(imageRenditionUrl(cropped, width: 320), cropped);
    });

    test('an unexpected path shape on a known host is left alone', () {
      const odd = 'https://assets.vogue.com/pass/x.jpg';
      expect(imageRenditionUrl(odd, width: 320), odd);
    });

    test('empty, relative and non-http values are returned unchanged', () {
      expect(imageRenditionUrl('', width: 320), '');
      expect(imageRenditionUrl('   ', width: 320), '   ');
      expect(
        imageRenditionUrl('/local/asset.png', width: 320),
        '/local/asset.png',
      );
      expect(
        imageRenditionUrl('data:image/png;base64,AAAA', width: 320),
        'data:image/png;base64,AAAA',
      );
    });
  });

  group('the resolver is stable, so caches hit', () {
    test('resolving twice gives the same URL', () {
      expect(
        imageRenditionUrl(master, width: 320),
        imageRenditionUrl(master, width: 320),
      );
    });

    test('resolving an already-resolved URL changes nothing further', () {
      final once = imageRenditionUrl(master, width: 320);
      expect(imageRenditionUrl(once, width: 320), once);
    });
  });
}
