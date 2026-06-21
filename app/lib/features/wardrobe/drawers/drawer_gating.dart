import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../paywall/billing_providers.dart';
import 'closet_drawer.dart';
import 'drawer_store.dart';

/// Freemium gating for closet drawers (CLAUDE.md §18).
///
/// Free users get [kFreeUserDrawerLimit] drawers TOTAL — the first few in
/// display order (seeded defaults first, then their own). Every drawer beyond
/// that renders locked; opening one or creating another opens the paywall.
/// Premium unlocks everything. (This drives upgrades — a free user sees the
/// extra drawers but must go premium to use them.)
///
/// Money boundary: "is this user premium?" comes from [isPremiumProvider], which
/// reflects the BACKEND-VERIFIED RevenueCat entitlement (`is_premium`). Drawers
/// themselves are on-device (local encrypted storage, no backend table), so this
/// is a UX gate layered on a server-verified entitlement. (If drawers ever become
/// server-persisted, enforcement attaches there — a data-model change to raise
/// with the founder first.)
const kFreeUserDrawerLimit = 3;

/// All drawers in display order: seeded defaults first (by sortOrder), then the
/// user's own. The free tier keeps the first [kFreeUserDrawerLimit] of these.
List<ClosetDrawer> orderedDrawers(List<ClosetDrawer> drawers) =>
    [...drawers]..sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });

/// The user-created (non-default) drawers, in stable creation order.
List<ClosetDrawer> userDrawers(List<ClosetDrawer> drawers) =>
    [for (final d in drawers) if (!d.isDefault) d]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// IDs of the drawers locked for a FREE user — every drawer beyond the first
/// [kFreeUserDrawerLimit] (default or custom). Empty for premium users.
Set<String> lockedDrawerIds(
  List<ClosetDrawer> drawers, {
  required bool isPremium,
}) {
  if (isPremium) return const {};
  final ordered = orderedDrawers(drawers);
  if (ordered.length <= kFreeUserDrawerLimit) return const {};
  return {for (final d in ordered.skip(kFreeUserDrawerLimit)) d.id};
}

/// Whether the user may create another drawer right now (always true for premium;
/// a free user is capped at [kFreeUserDrawerLimit] drawers total).
bool canCreateDrawer(
  List<ClosetDrawer> drawers, {
  required bool isPremium,
}) =>
    isPremium || drawers.length < kFreeUserDrawerLimit;

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
