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
}

/// The set of enabled feature flags from the backend. Empty while loading or on
/// error — so every flagged feature is OFF until the backend definitively says
/// it's on (CLAUDE.md §16). Auto-refreshes when invalidated.
final enabledFeatureFlagsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(featureFlagsRepositoryProvider).getEnabled();
});

/// Whether a given feature flag is enabled right now (false unless definitively
/// on). Use to gate UI: `ref.watch(featureEnabledProvider(FeatureFlags.postEdit))`.
final featureEnabledProvider = Provider.family<bool, String>((ref, key) {
  return ref.watch(enabledFeatureFlagsProvider).asData?.value.contains(key) ??
      false;
});
