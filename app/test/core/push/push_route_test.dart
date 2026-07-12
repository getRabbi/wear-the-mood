import 'package:app/core/push/push_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidPushRoute', () {
    test('accepts in-app absolute routes', () {
      expect(isValidPushRoute('/'), isTrue);
      expect(isValidPushRoute('/community/post/123'), isTrue);
      expect(isValidPushRoute('/wtm/giveaways'), isTrue);
    });

    test('rejects empty and relative payloads', () {
      expect(isValidPushRoute(''), isFalse);
      expect(isValidPushRoute('community/post/123'), isFalse);
    });

    test('rejects full URLs and scheme-relative payloads', () {
      expect(isValidPushRoute('https://evil.example/phish'), isFalse);
      expect(isValidPushRoute('com.fashionos.app://login-callback'), isFalse);
      expect(isValidPushRoute('//evil.example'), isFalse);
      expect(isValidPushRoute('/ok/but?next=https://evil.example'), isFalse);
    });
  });
}
