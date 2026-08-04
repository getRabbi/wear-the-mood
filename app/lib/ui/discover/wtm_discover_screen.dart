import 'package:flutter/material.dart';

import '../community/wtm_social_screen.dart';

/// The Discover tab destination (DISCOVER spec §5) — and, for now, only the
/// seam that later phases fill in.
///
/// Phase 1 is navigation work: the tab is renamed, the Discover-owned routes
/// move into this branch, and `/wtm/social` becomes an alias pointing here.
/// None of that should change what a user actually sees, so the destination
/// stays the existing community surface, which already handles its own
/// loading / empty / error states and its own `feature_community` gate. That
/// satisfies the spec's hard rule that a disabled Discover shows the existing
/// safe fallback and never a blank screen (§24, §31).
///
/// Phase 2 replaces the body below with the real Discover — header, Stories
/// rail, feed — behind [FeatureFlags.discover], keeping this same fallback for
/// the flag-off arm. Routing to it does not have to change again.
class WtmDiscoverScreen extends StatelessWidget {
  const WtmDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) => const WtmSocialScreen();
}
