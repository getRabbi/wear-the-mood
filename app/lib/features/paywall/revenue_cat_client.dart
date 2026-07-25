import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_status.dart';
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
  bool _listenerAdded = false;
  void Function(StoreEntitlement)? _onEntitlement;

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
    _attachSdkListener();
  }

  /// Register the SDK CustomerInfo listener EXACTLY once. It forwards each
  /// snapshot to the app-level callback set via [bindEntitlementListener].
  void _attachSdkListener() {
    if (_listenerAdded) return;
    _listenerAdded = true;
    Purchases.addCustomerInfoUpdateListener((info) {
      _onEntitlement?.call(_mapCustomerInfo(info));
    });
  }

  /// Map RevenueCat's [CustomerInfo] to the app's SDK-agnostic snapshot. Active
  /// when any entitlement or subscription is live; the product id prefers the
  /// active entitlement's product (so the tier hint is accurate), falling back
  /// to the first active subscription id.
  StoreEntitlement _mapCustomerInfo(CustomerInfo info) {
    final active =
        info.entitlements.active.isNotEmpty ||
        info.activeSubscriptions.isNotEmpty;
    String? productId;
    if (info.entitlements.active.isNotEmpty) {
      productId = info.entitlements.active.values.first.productIdentifier;
    }
    productId ??= info.activeSubscriptions.isNotEmpty
        ? info.activeSubscriptions.first
        : null;
    return StoreEntitlement(active: active, productId: productId);
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
  Future<StorePurchaseResult> purchase(String offerId) async {
    try {
      await _ensureConfigured();
      final pkg = (await Purchases.getOfferings()).current?.getPackage(offerId);
      if (pkg == null) {
        return const StorePurchaseResult.status(SubscriptionResult.error);
      }
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      return StorePurchaseResult(
        SubscriptionResult.success,
        entitlement: _mapCustomerInfo(result.customerInfo),
      );
    } on PlatformException catch (e) {
      return StorePurchaseResult.status(
        PurchasesErrorHelper.getErrorCode(e) ==
                PurchasesErrorCode.purchaseCancelledError
            ? SubscriptionResult.cancelled
            : SubscriptionResult.error,
      );
    } catch (_) {
      return const StorePurchaseResult.status(SubscriptionResult.error);
    }
  }

  @override
  Future<StorePurchaseResult> restore() async {
    try {
      await _ensureConfigured();
      final info = await Purchases.restorePurchases();
      return StorePurchaseResult(
        SubscriptionResult.success,
        entitlement: _mapCustomerInfo(info),
      );
    } catch (_) {
      return const StorePurchaseResult.status(SubscriptionResult.error);
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
  Future<StorePurchaseResult> purchaseTopUp(String productId) async {
    try {
      await _ensureConfigured();
      // Top-up is a consumable IN-APP product, NOT a package in the Offering —
      // fetch it directly (nonSubscription so Android looks up an INAPP, not a
      // sub) and purchase the store product.
      final products = await Purchases.getProducts(
        [productId],
        productCategory: ProductCategory.nonSubscription,
      );
      if (products.isEmpty) {
        return const StorePurchaseResult.status(SubscriptionResult.error);
      }
      final result = await Purchases.purchase(
        PurchaseParams.storeProduct(products.first),
      );
      // A top-up confers NO tier — we still surface the snapshot for consistency,
      // but the service only refreshes credits (never premium) for a top-up.
      return StorePurchaseResult(
        SubscriptionResult.success,
        entitlement: _mapCustomerInfo(result.customerInfo),
      );
    } on PlatformException catch (e) {
      return StorePurchaseResult.status(
        PurchasesErrorHelper.getErrorCode(e) ==
                PurchasesErrorCode.purchaseCancelledError
            ? SubscriptionResult.cancelled
            : SubscriptionResult.error,
      );
    } catch (_) {
      return const StorePurchaseResult.status(SubscriptionResult.error);
    }
  }

  @override
  Future<String?> topUpPriceString(String productId) async {
    try {
      await _ensureConfigured();
      // Same nonSubscription lookup as the purchase path, so the price shown is
      // exactly the product the user will buy.
      final products = await Purchases.getProducts(
        [productId],
        productCategory: ProductCategory.nonSubscription,
      );
      if (products.isEmpty) return null;
      return products.first.priceString;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoreEntitlement?> customerInfo() async {
    if (!_configured && currentRevenueCatKey().isEmpty) return null;
    try {
      await _ensureConfigured();
      return _mapCustomerInfo(await Purchases.getCustomerInfo());
    } catch (_) {
      return null;
    }
  }

  @override
  void bindEntitlementListener(void Function(StoreEntitlement) onUpdate) {
    _onEntitlement = onUpdate;
    // If the SDK is already configured, the listener is live and will forward to
    // the new callback; otherwise it attaches on first configure.
  }
}
