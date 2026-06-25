import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/utils/public_name.dart';

void main() {
  group('containsEmail', () {
    test('detects an email anywhere in the text', () {
      expect(containsEmail('wearthemood24@gmail.com'), isTrue);
      expect(containsEmail('reach me at a@b.com please'), isTrue);
    });

    test('is false for clean text / empty / null', () {
      expect(containsEmail('loved this fit today'), isFalse);
      expect(containsEmail(''), isFalse);
      expect(containsEmail(null), isFalse);
    });
  });

  test('returns a plain name unchanged (trimmed)', () {
    expect(publicName('Mim'), 'Mim');
    expect(publicName('  Nadia  '), 'Nadia');
  });

  test('drops a bare email so it never shows publicly', () {
    expect(publicName('wearthemood24@gmail.com'), isNull);
  });

  test('drops a name that embeds an email', () {
    expect(publicName('me wearthemood24@gmail.com'), isNull);
  });

  test('drops empty / blank values', () {
    expect(publicName(null), isNull);
    expect(publicName(''), isNull);
    expect(publicName('   '), isNull);
  });

  test('falls back to the second candidate when the first is unsafe', () {
    expect(publicName('user@example.com', 'stylequeen'), 'stylequeen');
    expect(publicName(null, 'stylequeen'), 'stylequeen');
  });

  test('returns null when every candidate is unsafe', () {
    expect(publicName('a@b.com', '   '), isNull);
  });
}
