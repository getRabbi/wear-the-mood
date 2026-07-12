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
  });
}
