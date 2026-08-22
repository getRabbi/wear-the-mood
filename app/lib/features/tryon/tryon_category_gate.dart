import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../../ui/closet/wtm_category_resolver.dart';

/// The one place a Try On tap stops to ask what an unidentified piece is.
///
/// Every "Try On" affordance in the app funnels through here before it seeds a
/// look, so no surface can forget — and none of them has to remember the order
/// either, because the order is the safety property and it lives in this file:
///
///   1. ask, with the real garment on screen,
///   2. wait for the SERVER to confirm the update,
///   3. only then continue the try-on, using the item the server returned.
///
/// Returning null means stop. Nothing has been seeded, no job exists and no
/// credit has moved — which is exactly what has to be true when somebody backs
/// out of the question or the update fails. Continuing anyway would submit a
/// piece the planner still cannot read, and the render it refuses is the one
/// this gate exists to prevent: a garment of unknown role painted onto somebody's
/// own photograph, charged for.
///
/// Pieces that are already identified pass through untouched and cost nothing —
/// the common case does no work and asks no questions.
Future<List<WardrobeItem>?> resolveCategoriesForTryOn(
  BuildContext context,
  WidgetRef ref,
  List<WardrobeItem> items,
) async {
  if (!items.any((item) => item.needsCategory)) return items;

  final resolved = <WardrobeItem>[];
  for (final item in items) {
    if (!item.needsCategory) {
      resolved.add(item);
      continue;
    }
    if (!context.mounted) return null;
    // One at a time, in the order they were picked, so a multi-piece look asks
    // about each unknown garment beside its own picture rather than presenting
    // one anonymous form for several.
    final updated = await showWtmCategoryResolver(context, item: item);
    if (updated == null) return null; // backed out, or the update failed
    resolved.add(updated);
  }
  return resolved;
}
