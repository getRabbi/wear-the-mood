import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../paywall/billing_providers.dart';
import 'closet_drawer.dart';
import 'drawer_store.dart';

/// Freemium gating for closet drawers (CLAUDE.md §18).
///
/// Free users keep the seeded default drawers (always free) PLUS up to
/// [kFreeUserDrawerLimit] of their OWN drawers; beyond that, extra user drawers
/// render locked and creating another opens the paywall. Premium unlocks
/// everything.
///
/// IMPORTANT — where the "source of truth" lives: drawers are an on-device,
/// zero-cost organizational feature (see [ClosetDrawersStore] — local encrypted
/// storage, deliberately no backend table). There is therefore no server
/// resource to meter or protect, and nothing that costs money if a user exceeds
/// the local limit. The boundary that DOES gate money — "is this user premium?"
/// — is read from [isPremiumProvider], which reflects the BACKEND-VERIFIED
/// RevenueCat entitlement (`is_premium`). So this gate is layered on top of a
/// server-verified entitlement, not on raw client state. (If drawers ever become
/// server-persisted for cross-device sync, enforcement attaches there — that's a
/// data-model change to raise with the founder first.)
const kFreeUserDrawerLimit = 3;

/// The user-created (non-default) drawers, in stable creation order.
List<ClosetDrawer> userDrawers(List<ClosetDrawer> drawers) =>
    [for (final d in drawers) if (!d.isDefault) d]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// IDs of the drawers locked for a FREE user — their own drawers beyond the free
/// limit. Empty for premium users; default drawers are never locked.
Set<String> lockedDrawerIds(
  List<ClosetDrawer> drawers, {
  required bool isPremium,
}) {
  if (isPremium) return const {};
  final mine = userDrawers(drawers);
  if (mine.length <= kFreeUserDrawerLimit) return const {};
  return {for (final d in mine.skip(kFreeUserDrawerLimit)) d.id};
}

/// Whether the user may create another drawer right now (always true for premium).
bool canCreateDrawer(
  List<ClosetDrawer> drawers, {
  required bool isPremium,
}) =>
    isPremium || userDrawers(drawers).length < kFreeUserDrawerLimit;

/// The set of drawer ids the current (free) user cannot open without upgrading.
final lockedDrawerIdsProvider = Provider<Set<String>>((ref) {
  return lockedDrawerIds(
    ref.watch(closetDrawersProvider),
    isPremium: ref.watch(isPremiumProvider),
  );
});

/// Whether the current entitlement still allows creating a new drawer.
final canCreateDrawerProvider = Provider<bool>((ref) {
  return canCreateDrawer(
    ref.watch(closetDrawersProvider),
    isPremium: ref.watch(isPremiumProvider),
  );
});
