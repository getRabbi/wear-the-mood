import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../shell/shell_providers.dart';
import 'tryon_preselect.dart';

/// The single entry point every "Try On" button uses (BUG 3 fix).
///
/// A "Try On" tap has to do three things, and the surfaces that forgot the third
/// one looked broken — the tab switched underneath a still-visible full-screen
/// route, so nothing appeared to happen:
///   1. seed the Try-On outfit stack (prefers each piece's cutout, falls back to
///      the original while a cutout is still processing — never a silent no-op),
///   2. switch the shell to the Try-On tab,
///   3. dismiss any full-screen route stacked OVER the shell so the Try-On page
///      is actually revealed. A closet card living inside a shell tab is already
///      on the shell, so the dismissal is a harmless no-op there; a pushed
///      drawer / detail / outfit-builder route is popped back to the shell.
///
/// Returns false when none of [items] has a usable image yet (e.g. a freshly
/// added piece whose original somehow didn't resolve), so the caller can tell
/// the user to try again shortly instead of leaving a dead tap.
bool openTryOnWithItems(
  BuildContext context,
  WidgetRef ref,
  List<WardrobeItem> items,
) {
  final seeded = ref.read(tryOnPreselectProvider.notifier).setItems(items);
  if (!seeded) return false;
  ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
  // Reveal the shell (now on the Try-On tab) by removing every route pushed above
  // it. `isFirst` is the shell route (`/`); from within a shell tab the current
  // route already IS first, so this is a no-op.
  Navigator.of(context).popUntil((route) => route.isFirst);
  return true;
}

/// Single-item convenience over [openTryOnWithItems].
bool openTryOnWithItem(
  BuildContext context,
  WidgetRef ref,
  WardrobeItem item,
) =>
    openTryOnWithItems(context, ref, [item]);
