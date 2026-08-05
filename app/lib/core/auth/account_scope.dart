import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/profile_repository.dart';
import '../../features/discover/application/discover_providers.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/data/discover_feed_cache.dart';
import '../../features/discover/data/discover_local_store.dart';
import '../../features/collections/local_collections.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/profile/avatar_service.dart';
import '../../features/stylist/stylist_controller.dart';
import '../../features/tryon/tryon_preselect.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../data/repositories/tryon_photos_repository.dart';
import '../../ui/mirror/wtm_body_source.dart';
import '../../ui/mirror/wtm_mirror_flow.dart';

/// Wipe every provider that holds one user's data/selection, at an account
/// boundary (sign-in / sign-out / account switch). The backend + RLS is the real
/// security boundary — this is the CLIENT half: it stops Account A's in-memory
/// state (and A's images) from ever showing to Account B on the same device
/// (§11). Local collections already re-namespace on the id change; invalidating
/// them here forces an immediate reset and cancels any in-flight stale load.
///
/// Called from a single `ref.listen(authUserIdProvider)` in the app root, so it
/// covers ALL sign-out paths (profile, settings, 401 auto-logout) uniformly.
void clearUserScopedState(WidgetRef ref) {
  // Server-backed reads for the previous user (autoDispose — invalidating also
  // drops any in-flight response so it can't paint into the new session).
  ref.invalidate(wardrobeItemsProvider);
  ref.invalidate(wardrobeSearchQueryProvider);
  ref.invalidate(outfitsProvider);
  ref.invalidate(tryonPhotosProvider);
  ref.invalidate(profileProvider);
  ref.invalidate(avatarSignedUrlProvider);

  // Keep-alive in-memory state that would otherwise persist across the switch.
  ref.invalidate(stylistControllerProvider);

  // Selected garment / body / editor state — never inherit the last account's.
  ref.invalidate(wtmMirrorFlowProvider);
  ref.invalidate(wtmBodyChoiceProvider);
  ref.invalidate(tryOnPreselectProvider);

  // Device-local collections (favorites / saved looks). These re-namespace on
  // their own authUserId watch; invalidate for an immediate, synchronous reset.
  ref.invalidate(savedLookRecordsProvider);
  ref.invalidate(closetFavoritesProvider);
  ref.invalidate(savedLooksProvider);
  ref.invalidate(outfitFavoritesProvider);

  // Discover: in-memory feed, the region/profile stamp it was ranked under,
  // and the seen-story state.
  ref.invalidate(productFeedProvider);
  ref.invalidate(productFiltersProvider);
  ref.invalidate(discoverShoppingScopeProvider);
  ref.invalidate(discoverSeenStoriesProvider);

  // The ON-DISK Discover caches. The feed cache is already keyed by account, so
  // the previous user's page is unreadable the moment the id changes — but
  // "unreadable" is not "gone", and a cache is not worth leaving one account's
  // browsing on disk during another's session. Fire-and-forget: a delete that
  // fails must not block the account switch, and the key check still holds.
  unawaited(ref.read(discoverFeedCacheProvider).clear());
  unawaited(ref.read(discoverLocalStoreProvider).clearAll());
}
