import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store_config.dart';
import 'subscription_service.dart';

/// The real RevenueCat client — the ONLY place `purchases_flutter` is imported.
/// Lazily configures the SDK on first use with THIS platform's public env key
/// (iOS and Android each have their own — [currentRevenueCatKey]) and the
/// Supabase user id as the RevenueCat app_user_id (so the backend webhook keys
/// match, §18). Never called when the platform key is missing, and always
/// swapped for a fake in tests.
class PurchasesRevenueCatClient implements RevenueCatClient {
  PurchasesRevenueCatClient();

  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    final key = currentRevenueCatKey();
    if (key.isEmpty) {
      throw StateError(
        'RevenueCat is not configured for this platform (no public key).',
      );
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    await Purchases.configure(PurchasesConfiguration(key)..appUserID = userId);
    _configured = true;
  }

  @override
  Future<List<SubscriptionOffer>> offers() async {
    await _ensureConfigured();
    final current = (await Purchases.getOfferings()).current;
    if (current == null) return const [];
    return [
      for (final p in current.availablePackages)
        SubscriptionOffer(
          id: p.identifier,
          title: p.storeProduct.title,
          priceString: p.storeProduct.priceString,
          isAnnual: p.packageType == PackageType.annual,
        ),
    ];
  }

  @override
  Future<SubscriptionResult> purchase(String offerId) async {
    try {
      await _ensureConfigured();
      final pkg = (await Purchases.getOfferings()).current?.getPackage(offerId);
      if (pkg == null) return SubscriptionResult.error;
      await Purchases.purchase(PurchaseParams.package(pkg));
      return SubscriptionResult.success;
    } on PlatformException catch (e) {
      return PurchasesErrorHelper.getErrorCode(e) ==
              PurchasesErrorCode.purchaseCancelledError
          ? SubscriptionResult.cancelled
          : SubscriptionResult.error;
    } catch (_) {
      return SubscriptionResult.error;
    }
  }

  @override
  Future<SubscriptionResult> restore() async {
    try {
      await _ensureConfigured();
      await Purchases.restorePurchases();
      return SubscriptionResult.success;
    } catch (_) {
      return SubscriptionResult.error;
    }
  }

  @override
  Future<void> logIn(String userId) async {
    await _ensureConfigured();
    // Identify as the Supabase UUID — the webhook ignores non-UUID app_user_ids.
    await Purchases.logIn(userId);
  }

  @override
  Future<void> logOut() async {
    // Nothing to clear if the SDK was never configured (RevenueCat.logOut throws
    // when unconfigured) — a signed-out launch that never opened billing.
    if (!_configured) return;
    await Purchases.logOut();
  }

  @override
  Future<SubscriptionResult> purchaseTopUp(String productId) async {
    try {
      await _ensureConfigured();
      // Top-up is a consumable IN-APP product, NOT a package in the Offering —
      // fetch it directly (nonSubscription so Android looks up an INAPP, not a
      // sub) and purchase the store product.
      final products = await Purchases.getProducts(
        [productId],
        productCategory: ProductCategory.nonSubscription,
      );
      if (products.isEmpty) return SubscriptionResult.error;
      await Purchases.purchase(PurchaseParams.storeProduct(products.first));
      return SubscriptionResult.success;
    } on PlatformException catch (e) {
      return PurchasesErrorHelper.getErrorCode(e) ==
              PurchasesErrorCode.purchaseCancelledError
          ? SubscriptionResult.cancelled
          : SubscriptionResult.error;
    } catch (_) {
      return SubscriptionResult.error;
    }
  }
}
