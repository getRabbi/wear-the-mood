import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/feature_flags_repository.dart';

/// Known feature-flag keys — mirror the backend `feature_flags` table (§16).
/// Each new feature ships behind its own key, OFF by default.
abstract class FeatureFlags {
  static const postEdit = 'feature_post_edit';
  static const postPolls = 'feature_post_polls';
  static const styleQuiz = 'feature_style_quiz';
  static const dailyGuide = 'feature_daily_guide';
  static const dailyOffers = 'feature_daily_offers';
  static const giveaway = 'feature_giveaway';

  /// Kill-switch for the secret pickup chat (0037). Seeded ON — the chat is
  /// the safe replacement for off-app contact swaps — but ops can disable it
  /// remotely without touching the rest of the giveaway flow.
  static const giveawayChat = 'feature_giveaway_chat';

  /// Gates the whole WTM community surface (feed, posts, public profiles,
  /// follow, report/block). OFF by default so it can stay off for iOS v1 until
  /// UGC compliance is signed off (UI_IMPLEMENTATION.md §6).
  static const community = 'feature_community';

  // ---- Discover (DISCOVER spec §14) ----
  // Every key below is absent from the backend `feature_flags` table on
  // purpose. [featureEnabledProvider] answers false for an unknown key, so all
  // of these are OFF for every already-installed build and every environment
  // until ops inserts the row and flips it — the staged rollout the spec asks
  // for, with no migration seeding Discover on in production.

  /// Master switch for the Discover tab. OFF → the nav item keeps its Social
  /// label and glyph and the branch keeps rendering the existing community
  /// surface: byte-for-byte today's behaviour, never a blank screen. This is
  /// also the instant rollback lever (§30).
  static const discover = 'feature_discover';

  /// The affiliate product catalog, feed and Product Details (§8, §12).
  /// Independent of [discover] so shopping can be dark-launched, or killed,
  /// without taking the whole tab down.
  static const shopping = 'feature_shopping';

  /// The Discover Stories rail and its viewer (§6, §7). Separate from
  /// [discover] so the rail can be disabled while the feed below it stays up.
  static const discoverStories = 'feature_discover_stories';

  /// Public create-post. OFF hides the composer entry points while the
  /// `/wtm/social/compose` route, the compose screen and every posting
  /// endpoint stay wired (§14 "hidden, not deleted").
  ///
  /// Deliberately its own key rather than riding on [community]: the two
  /// answer different questions — whether anyone may READ the feed, and
  /// whether anyone may WRITE to it — and the spec hides posting first.
  static const communityPosting = 'feature_community_posting';

  /// Community discovery notifications (new follower suggestions, feed
  /// activity digests). OFF while the feed is hidden so the app never pushes a
  /// user toward a surface they cannot open.
  static const communityNotifications = 'feature_community_notifications';

  /// Fallback switch for the OLD Home modules (the `Giveaways / Offers /
  /// Newsroom` shortcut row and `Inspiration for You`). Phase 6 removes them
  /// only once Discover is proven; until then this is the lever that brings
  /// them back without a binary release (§30).
  static const legacyHomeDiscover = 'feature_legacy_home_discover';

  /// Keys that render ON while we have not yet heard from the backend.
  ///
  /// Discover is no longer a staged rollout — it IS the design, and Social is
  /// retired. With the default OFF, every cold launch drew tab 1 as Social
  /// until the flags request landed and then swapped it to Discover: a visible
  /// flash of a surface that is not supposed to exist any more, and the whole
  /// tab reverting to Social whenever the flags call failed.
  ///
  /// This does NOT defeat the kill-switch (§16, DISCOVER §30). The default
  /// applies only while the answer is unknown — loading or error. Once the
  /// backend answers definitively, its answer wins in both directions, so
  /// flipping `feature_discover` off in `feature_flags` still pulls Discover
  /// for every client on the next refresh.
  static const onUntilBackendSaysOtherwise = {discover, discoverStories};
}

/// The set of enabled feature flags from the backend. Empty while loading or on
/// error — so every flagged feature is OFF until the backend definitively says
/// it's on (CLAUDE.md §16). Auto-refreshes when invalidated.
final enabledFeatureFlagsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(featureFlagsRepositoryProvider).getEnabled();
});

/// Whether a given feature flag is enabled right now. Use to gate UI:
/// `ref.watch(featureEnabledProvider(FeatureFlags.postEdit))`.
///
/// A definitive answer from the backend always wins. Only when there is no
/// answer yet — still loading, or the request failed — does the key's own
/// default decide, and all but [FeatureFlags.onUntilBackendSaysOtherwise]
/// default OFF (§16: a new feature is off until the backend says otherwise).
final featureEnabledProvider = Provider.family<bool, String>((ref, key) {
  final flags = ref.watch(enabledFeatureFlagsProvider);
  final answered = flags.asData;
  if (answered != null) return answered.value.contains(key);
  return FeatureFlags.onUntilBackendSaysOtherwise.contains(key);
});
