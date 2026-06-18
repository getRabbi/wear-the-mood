import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/offer.dart';

void main() {
  test('Offer.fromJson maps snake_case fields', () {
    final offer = Offer.fromJson({
      'id': 'o1',
      'title': 'Up to 40% off knitwear',
      'brand': 'Studio Label',
      'image_url': null,
      'discount_label': '-40%',
      'affiliate_url': 'https://x.com/p?utm_source=fashionos',
      'topics': ['knitwear', 'sale'],
    });
    expect(offer.title, 'Up to 40% off knitwear');
    expect(offer.brand, 'Studio Label');
    expect(offer.discountLabel, '-40%');
    expect(offer.affiliateUrl, contains('utm_source=fashionos'));
    expect(offer.topics, ['knitwear', 'sale']);
    expect(offer.imageUrl, isNull);
  });
}
