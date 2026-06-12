import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entitlement.dart';
import '../../data/repositories/billing_repository.dart';

/// The user's current entitlement (CLAUDE.md §18).
final entitlementProvider = FutureProvider<Entitlement>((ref) {
  return ref.read(billingRepositoryProvider).getEntitlement();
});

/// Whether the user is premium right now. Defaults to false while loading or on
/// error — premium is only ever asserted on a definitive active entitlement.
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(entitlementProvider).asData?.value.active ?? false;
});
