import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's single page-transition implementation (CLAUDE.md §4).
///
/// It is installed once on [ThemeData.pageTransitionsTheme], so every route
/// pushed through go_router's default page picks it up and **no screen needs a
/// bespoke `pageBuilder`**. Adding a one-off `CustomTransitionPage` somewhere
/// re-introduces exactly the inconsistency this replaced.
///
/// Both builders subclass the framework's *native* builders instead of
/// hand-rolling a slide. That is deliberate: the iOS interactive
/// edge-swipe-back detector and Android's predictive-back handoff live inside
/// private framework widgets that a custom [PageTransitionsBuilder] cannot
/// reuse, so writing one would silently drop both gestures. Subclassing keeps
/// them and still lets the motion timing come from [AppMotion].
///
/// Note what a transition deliberately does *not* do: paint a page background.
/// The framework's iOS transition never has, and while it runs the route
/// underneath is still being painted. Opaque page backgrounds are the page's
/// own responsibility — see `WtmBackdrop`.
abstract final class AppTransitions {
  /// Push/pop timing for every route — quicker than both platform defaults
  /// (iOS 500ms, Android 450ms), which read as sluggish on a real device.
  static const routeDuration = AppMotion.base; // 280ms

  /// Drop-in for [ThemeData.pageTransitionsTheme]. Platforms we don't ship
  /// (Windows/Linux) fall through to the framework default.
  static const theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.iOS: _CupertinoPageTransitions(),
      TargetPlatform.macOS: _CupertinoPageTransitions(),
      TargetPlatform.android: _PredictiveBackPageTransitions(),
      TargetPlatform.fuchsia: _PredictiveBackPageTransitions(),
    },
  );
}

/// iOS/macOS: the native parallax push, retimed. Keeps the interactive
/// edge-swipe back gesture that `CupertinoRouteTransitionMixin` installs.
class _CupertinoPageTransitions extends CupertinoPageTransitionsBuilder {
  const _CupertinoPageTransitions();

  @override
  Duration get transitionDuration => AppTransitions.routeDuration;
}

/// Android: the native predictive-back transition, retimed. Falls back to the
/// platform's fade-forwards motion when predictive back isn't available.
class _PredictiveBackPageTransitions
    extends PredictiveBackPageTransitionsBuilder {
  const _PredictiveBackPageTransitions();

  @override
  Duration get transitionDuration => AppTransitions.routeDuration;
}
