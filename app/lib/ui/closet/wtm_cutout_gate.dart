import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/feature_gates.dart';
import '../../data/models/wardrobe_item.dart';

/// Runtime view of the compile-time [kCutoutEditorEnabled] gate.
///
/// Production resolves straight to the const, so an un-flagged build still
/// compiles the whole affordance away exactly as before. Routing it through a
/// provider gives the rule one definition that screens *and* tests read, so the
/// two entry points can never drift apart again.
final cutoutEditorEnabledProvider = Provider<bool>(
  (ref) => kCutoutEditorEnabled,
);

/// THE eligibility rule for the free Erase/Restore editor, shared by the
/// garment detail screen and the add-garment confirm step: there has to be a
/// background-removed cutout to correct.
///
/// Deliberately platform-independent — and it always was. "Fix cutout"
/// appearing on one store build and not the other was never a UI condition;
/// only one build pipeline passed `--dart-define=CUTOUT_EDITOR_ENABLED=true`.
/// Keep the flag in `app/env/prod.json` (and in the codemagic `write_prod_env`
/// generator that rewrites it in CI) so every platform compiles the same rule.
bool canFixCutout(WardrobeItem? item, {required bool enabled}) =>
    enabled && item?.cutoutUrl != null;

/// Runtime view of the **Improve edges** gate.
///
/// Separate provider from [cutoutEditorEnabledProvider] because the two actions
/// are separate features with separate gates on both sides of the wire.
///
/// Reads [kLocalCutoutImproveEnabled], which is named after the backend's own
/// `LOCAL_CUTOUT_IMPROVE_ENABLED`. It used to read the master
/// `kLocalBgRemovalEnabled` instead, which is a DIFFERENT feature ("segment on
/// device"); enabling Android local background removal therefore showed this
/// button while the endpoint was still off, and every tap 404'd with "not
/// found" in production. The gate a button reads must be the gate the server
/// enforces.
final improveCutoutEnabledProvider = Provider<bool>(
  (ref) => kLocalCutoutImproveEnabled,
);

/// THE eligibility rule for **Improve edges** — the free automatic BiRefNet
/// re-run (local BG §6.4, §9.4).
///
/// Not to be confused with [canFixCutout]:
///   * **Improve edges** re-runs the AUTOMATIC cutout on the server. Free, async,
///     and the existing cutout stays visible while it works.
///   * **Fix cutout** opens the manual Erase/Restore EDITOR. Free, deterministic,
///     and entirely on-device until the user saves.
///
/// Requires something to improve ([WardrobeItem.cutoutUrl]) and no attempt already
/// in flight — offering it mid-attempt would invite the duplicate tap the server
/// then has to reject.
bool canImproveCutout(WardrobeItem? item, {required bool enabled}) {
  if (!enabled || item == null) return false;
  return item.cutoutUrl != null && !item.isProcessingCutout;
}
