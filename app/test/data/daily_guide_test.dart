import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/daily_guide.dart';

void main() {
  test('DailyGuide.fromJson maps date, topics and CTAs (snake_case)', () {
    final guide = DailyGuide.fromJson({
      'id': 'g1',
      'date': '2026-06-18',
      'title': 'Transitional layering',
      'summary': 'Lightweight layers.',
      'body': 'Long body...',
      'image_url': null,
      'topics': ['layering', 'transitional'],
      'cta': [
        {'label': 'Build a look', 'action': 'tryon'},
        {'label': 'Shop', 'action': 'news', 'target': '/news'},
      ],
      'created_at': '2026-06-18T08:00:00Z',
    });

    expect(guide.title, 'Transitional layering');
    expect(guide.date.year, 2026);
    expect(guide.topics, ['layering', 'transitional']);
    expect(guide.cta.length, 2);
    expect(guide.cta.first.action, 'tryon');
    expect(guide.cta[1].target, '/news');
    expect(guide.imageUrl, isNull);
  });
}
