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
