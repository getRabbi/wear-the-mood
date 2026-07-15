import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entitlement.dart';
import '../../data/repositories/billing_repository.dart';
import 'account_status.dart';

/// The user's current entitlement (CLAUDE.md §18).
final entitlementProvider = FutureProvider<Entitlement>((ref) {
  return ref.read(billingRepositoryProvider).getEntitlement();
});

/// Whether the user is premium right now. The server entitlement is the
/// authority, but a just-completed store purchase reflects IMMEDIATELY via the
/// optimistic tier / local RevenueCat entitlement snapshot so the UI never waits
/// on the webhook (§18). Both optimistic sources come from a real, SDK-signed
/// store purchase — not a forgeable client claim — and the backend still gates
/// every paid action server-side. Defaults to false while loading.
final isPremiumProvider = Provider<bool>((ref) {
  final serverActive =
      ref.watch(entitlementProvider).asData?.value.active ?? false;
  final localActive = ref.watch(localStoreEntitlementProvider)?.active ?? false;
  final optimisticPaid = ref.watch(optimisticTierProvider)?.isPaid ?? false;
  return serverActive || localActive || optimisticPaid;
});
