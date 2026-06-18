import 'package:animations/animations.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

/// A go_router page that enters with a Material **shared-axis** transition — the
/// cohesive forward/back motion for sibling page pushes (CLAUDE.md §4). Honors
/// reduce-motion by rendering the page with no transition.
///
/// Use in a route's `pageBuilder`:
/// ```dart
/// pageBuilder: (context, state) => appSharedAxisPage(child: const FooScreen()),
/// ```
CustomTransitionPage<T> appSharedAxisPage<T>({
  required Widget child,
  LocalKey? key,
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.base,
    reverseTransitionDuration: AppMotion.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: type,
        fillColor: const Color(0x00000000), // transparent — don't flash a bg
        child: child,
      );
    },
    child: child,
  );
}
