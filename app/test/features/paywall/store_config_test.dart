import 'package:app/features/paywall/store_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('revenueCatKeyFor', () {
    test('picks the iOS key on iOS — never the Android key', () {
      expect(
        revenueCatKeyFor(
          TargetPlatform.iOS,
          iosKey: 'appl_public',
          androidKey: 'goog_public',
        ),
        'appl_public',
      );
    });

    test('picks the Android key on Android — never the iOS key', () {
      expect(
        revenueCatKeyFor(
          TargetPlatform.android,
          iosKey: 'appl_public',
          androidKey: 'goog_public',
        ),
        'goog_public',
      );
    });

    test('Android release uses the Play goog_ production key verbatim', () {
      // Production Android public SDK keys carry the Play `goog_` prefix (the
      // real key lives only in env/prod.json, never in source). The router
      // returns it unchanged on Android and never lets the iOS side inherit it,
      // so a release build can only transact with the live Play key — never a
      // RevenueCat Test Store key or the wrong platform's key.
      const googProd = 'goog_ExamplePlayProdKey';
      expect(googProd.startsWith('goog_'), isTrue);
      expect(
        revenueCatKeyFor(
          TargetPlatform.android,
          androidKey: googProd,
          iosKey: 'appl_public',
        ),
        googProd,
      );
      expect(
        revenueCatKeyFor(TargetPlatform.iOS, androidKey: googProd, iosKey: ''),
        isEmpty,
      );
    });

    test(
      'iOS with no iOS key stays unconfigured even when Android has one',
      () {
        // The silent-fallback-to-Android-key bug this design forbids.
        expect(
          revenueCatKeyFor(
            TargetPlatform.iOS,
            iosKey: '',
            androidKey: 'goog_public',
          ),
          isEmpty,
        );
      },
    );

    test('non-store platforms never get a key', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          revenueCatKeyFor(
            platform,
            iosKey: 'appl_public',
            androidKey: 'goog_public',
          ),
          isEmpty,
          reason: '$platform must stay in the not-configured state',
        );
      }
    });
  });

  group('hasRevenueCatConfigFor', () {
    test('is false everywhere in the test env (no dart-define keys)', () {
      expect(hasRevenueCatConfigFor(TargetPlatform.iOS), isFalse);
      expect(hasRevenueCatConfigFor(TargetPlatform.android), isFalse);
    });
  });

  group('manageSubscriptionUrlFor', () {
    test('iOS opens the App Store subscription manager', () {
      expect(
        manageSubscriptionUrlFor(TargetPlatform.iOS),
        'https://apps.apple.com/account/subscriptions',
      );
    });

    test('Android opens the Play subscription manager', () {
      expect(
        manageSubscriptionUrlFor(TargetPlatform.android),
        'https://play.google.com/store/account/subscriptions',
      );
    });
  });

  group('StorePackages', () {
    test('package ids match the shipped RevenueCat offering', () {
      expect(StorePackages.proMonthly, 'pro_monthly');
      expect(StorePackages.proMaxMonthly, 'pro_max_monthly');
    });

    test('top-up is a distinct product id, never a subscription package', () {
      expect(StorePackages.topUp40, 'topup_40');
      // The consumable must not collide with either subscription package — it is
      // bought outside the Offering and must never read as a premium plan.
      expect(StorePackages.topUp40, isNot(StorePackages.proMonthly));
      expect(StorePackages.topUp40, isNot(StorePackages.proMaxMonthly));
    });
  });
}
