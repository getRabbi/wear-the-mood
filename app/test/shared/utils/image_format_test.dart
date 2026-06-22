import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/utils/image_format.dart';

void main() {
  group('imageContentType', () {
    test('detects WebP from RIFF/WEBP magic', () {
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0,
      ]);
      expect(imageContentType(webp), 'image/webp');
    });

    test('detects PNG', () {
      expect(
        imageContentType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])),
        'image/png',
      );
    });

    test('defaults to JPEG', () {
      expect(
        imageContentType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        'image/jpeg',
      );
    });
  });

  group('stableImageCacheKey', () {
    test('strips the signed query so the path is the key', () {
      expect(
        stableImageCacheKey('https://r2/b/u/x.webp?X-Amz-Signature=abc'),
        'https://r2/b/u/x.webp',
      );
    });

    test('keeps a public (query-less) url whole', () {
      expect(stableImageCacheKey('https://cdn/u/x.webp'), 'https://cdn/u/x.webp');
    });

    test('two refreshed signed urls for the same object share a key', () {
      expect(
        stableImageCacheKey('https://r2/b/u/x.webp?token=1'),
        stableImageCacheKey('https://r2/b/u/x.webp?token=2'),
      );
    });
  });

  group('extForImageContentType', () {
    test('maps content types to extensions', () {
      expect(extForImageContentType('image/webp'), '.webp');
      expect(extForImageContentType('image/png'), '.png');
      expect(extForImageContentType('image/jpeg'), '.jpg');
      expect(extForImageContentType('anything/else'), '.jpg');
    });
  });
}
