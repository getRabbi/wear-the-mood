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
