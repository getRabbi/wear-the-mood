import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/utils/link_launcher.dart';

/// Every outbound link the app opens comes from somewhere it does not control:
/// a syndicated news feed, a merchant's affiliate URL, a row in the offers
/// table. `launchUrl` will dispatch whatever scheme it is handed to whatever
/// app claims it, so the gate is here.
void main() {
  group('LinkLauncher.isSafe', () {
    test('accepts a plain https link', () {
      expect(LinkLauncher.isSafe('https://shop.example/product/1'), isTrue);
      expect(LinkLauncher.isSafe('  https://shop.example/a?b=c  '), isTrue);
    });

    test('refuses every non-https scheme', () {
      for (final url in [
        'http://shop.example/x', // an affiliate hop in the clear
        'javascript:alert(1)',
        'intent://scan/#Intent;scheme=zxing;end',
        'file:///data/data/com.fashionos.app/databases/app.db',
        'tel:+8801700000000',
        'market://details?id=com.fashionos.app',
        'wtm://deeplink',
      ]) {
        expect(LinkLauncher.isSafe(url), isFalse, reason: url);
      }
    });

    test('refuses embedded userinfo, which disguises the real host', () {
      // Reads as the merchant in a preview, resolves to the attacker.
      expect(
        LinkLauncher.isSafe('https://real.shop@evil.test/checkout'),
        isFalse,
      );
    });

    test('refuses a hostless or unparseable link', () {
      expect(LinkLauncher.isSafe('https:///nohost'), isFalse);
      expect(LinkLauncher.isSafe(''), isFalse);
      expect(LinkLauncher.isSafe('   '), isFalse);
      expect(LinkLauncher.isSafe('::::'), isFalse);
    });

    test('open() refuses without touching the platform', () async {
      // No platform channel in a unit test — a launch attempt would throw, so
      // returning false proves the guard ran first.
      expect(await const LinkLauncher().open('javascript:alert(1)'), isFalse);
      expect(await const LinkLauncher().open('http://shop.example'), isFalse);
    });
  });
}
