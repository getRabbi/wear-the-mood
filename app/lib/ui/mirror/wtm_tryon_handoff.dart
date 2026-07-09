import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/tryon/tryon_preselect.dart';

/// The WTM "Try This On" handoff (§2/§5): seed the MoodMirror outfit stack from
/// owned pieces, then open Step 2 — [WtmMirrorStep2Screen] consumes the
/// preselect on mount and pre-fills the draft. Reuses the shipped
/// [TryOnPreselect] engine (prefers each cutout, falls back to the original).
///
/// Returns false when none of [items] has a usable image yet (e.g. a freshly
/// added piece), so the caller can warn instead of leaving a dead "Try On" tap.
bool wtmTryOnWithItems(
  BuildContext context,
  WidgetRef ref,
  List<WardrobeItem> items,
) {
  final seeded = ref.read(tryOnPreselectProvider.notifier).setItems(items);
  if (!seeded) return false;
  context.push(AppRoute.wtmMirrorGarments);
  return true;
}
