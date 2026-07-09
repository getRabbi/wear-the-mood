import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';

void main() {
  group('WardrobeItem AI Enhance', () {
    test('displayImageUrl prefers the enhanced cover when present', () {
      const item = WardrobeItem(
        id: 'w1',
        imageUrl: 'https://x/original.jpg',
        cutoutUrl: 'https://x/cutout.png',
        thumbnailUrl: 'https://x/thumb.png',
        coverImageUrl: 'https://x/enhanced.png',
        aiEnhanced: true,
        aiStatus: 'done',
      );
      expect(item.displayImageUrl, 'https://x/enhanced.png');
    });

    test('falls back to thumbnail/cutout/original without a cover', () {
      const item = WardrobeItem(
        id: 'w1',
        imageUrl: 'https://x/original.jpg',
        cutoutUrl: 'https://x/cutout.png',
        thumbnailUrl: 'https://x/thumb.png',
      );
      expect(item.displayImageUrl, 'https://x/thumb.png');
    });

    test('isEnhancing tracks queued/processing only', () {
      expect(
        const WardrobeItem(id: 'a', aiStatus: 'queued').isEnhancing,
        isTrue,
      );
      expect(
        const WardrobeItem(id: 'a', aiStatus: 'processing').isEnhancing,
        isTrue,
      );
      expect(
        const WardrobeItem(id: 'a', aiStatus: 'done').isEnhancing,
        isFalse,
      );
      expect(const WardrobeItem(id: 'a').isEnhancing, isFalse);
    });

    test('parses the backend ai-enhance fields', () {
      final item = WardrobeItem.fromJson(const {
        'id': 'w1',
        'cover_image_url': 'https://x/enhanced.png',
        'ai_enhanced': true,
        'ai_status': 'done',
      });
      expect(item.coverImageUrl, 'https://x/enhanced.png');
      expect(item.aiEnhanced, isTrue);
      expect(item.aiStatus, 'done');
    });
  });
}
