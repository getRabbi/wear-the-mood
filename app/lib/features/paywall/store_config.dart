/// Central store/billing platform mapping — the ONLY place that decides which
/// RevenueCat public key, package ids, and store URLs apply on this device.
/// Keys stay env-driven (never hardcoded, §11/§18); the pure `…For` functions
/// exist so tests can pin a [TargetPlatform] without touching global state.
library;

import 'package:flutter/foundation.dart';

import '../../core/env/app_env.dart';

/// RevenueCat **package identifiers** inside the current Offering. They are
/// platform-neutral: the RevenueCat dashboard attaches the Play products (live
/// today) and the App Store Connect products (owner action — see
/// docs/IOS_APPSTORE_READINESS.md) to these same packages, so the paywall code
/// never branches per store.
abstract final class StorePackages {
  static const proMonthly = 'pro_monthly';
  static const proMaxMonthly = 'pro_max_monthly';
}

/// The RevenueCat public SDK key for [platform] — Android and iOS each use
/// their own app key from the SAME RevenueCat project (cross-platform
/// entitlements). Anything else (tests on desktop, web) gets an empty key,
/// which keeps billing in the safe "not configured" state. The Android key is
/// NEVER substituted on iOS or vice versa.
String revenueCatKeyFor(
  TargetPlatform platform, {
  String iosKey = AppEnv.revenueCatIosKey,
  String androidKey = AppEnv.revenueCatAndroidKey,
}) => switch (platform) {
  TargetPlatform.iOS => iosKey,
  TargetPlatform.android => androidKey,
  _ => '',
};

/// The key for the device this code is running on.
String currentRevenueCatKey() => revenueCatKeyFor(defaultTargetPlatform);

/// True once THIS platform has its own RevenueCat public key. Gates the
/// purchase/restore flow; until then the paywall is informational.
bool hasRevenueCatConfigFor(TargetPlatform platform) =>
    revenueCatKeyFor(platform).isNotEmpty;

/// Where "Manage subscription" lives for [platform] — the store's own
/// subscription manager (App Store guideline 3.1.1: never a web checkout).
String manageSubscriptionUrlFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => 'https://apps.apple.com/account/subscriptions',
  _ => 'https://play.google.com/store/account/subscriptions',
};
