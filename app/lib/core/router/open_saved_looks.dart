import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Open Saved Looks from a screen that sits ABOVE the persistent shell.
///
/// `/wtm/looks` lives inside a `StatefulShellRoute.indexedStack` branch. A
/// try-on result — 2D or AI — is a full-screen route pushed OVER that shell, and
/// pushing a branch path from up there puts the route on the ROOT navigator
/// instead of inside its branch. go_router matches the path, builds nothing the
/// branch can host, and the user gets a blank page with a working bottom nav.
///
/// Found exactly that way: "View looks" navigated to an empty screen. The app
/// already had the answer for the same problem in `openTryOnWithItems`, which
/// pops back to the shell before touching a branch — this is that, named, so
/// the next caller does not rediscover it.
///
/// The router is captured BEFORE the pop: after `popUntil` the calling widget's
/// context is defunct and `GoRouter.of` on it would throw.
void openSavedLooks(BuildContext context) {
  final router = GoRouter.of(context);
  Navigator.of(context).popUntil((route) => route.isFirst);
  router.push(AppRoute.wtmLooks);
}
