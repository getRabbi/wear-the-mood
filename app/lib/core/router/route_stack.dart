/// Reading and unwinding go_router's PAGE stack.
///
/// Everything here exists because `GoRouterState.matchedLocation` and
/// `currentConfiguration.uri` answer a different question than the one screens
/// keep asking. Both describe the location the router was last *navigated* to
/// declaratively; an imperative `push` appends an `ImperativeRouteMatch` and
/// deliberately leaves the list's `uri` alone. So after
///
/// ```dart
/// context.go('/wtm/discover');
/// context.push('/wtm/mirror/garments');
/// ```
///
/// `currentConfiguration.uri.path` is still `/wtm/discover`. Any code that
/// compared it against a route constant to answer "am I already there?" was
/// answering "no" forever — which is how the Try On double-tap guard came to
/// be a guard that never fired.
///
/// These helpers read the real page list instead, so "what is on top" and "how
/// deep is the flow I am in" are answerable facts rather than guesses.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Every page currently on the stack, bottom to top.
///
/// Shell branches are flattened: a page inside the selected branch is a page on
/// the stack, which is what Back actually walks. A pushed page contributes the
/// FULL location it was pushed with, query string included, because that is
/// what identifies it (`/wtm/discover/product?id=p1` is not
/// `/wtm/discover/product`).
List<String> routeStack(BuildContext context) =>
    routeStackOf(GoRouter.of(context));

/// [routeStack] for a router held directly — the form tests and pure helpers
/// use, where there is no element to look the router up from.
List<String> routeStackOf(GoRouter router) {
  final locations = <String>[];

  void walk(List<RouteMatchBase> matches) {
    for (final match in matches) {
      switch (match) {
        // A shell contributes no page of its own; its selected branch does.
        case ShellRouteMatch(:final matches):
          walk(matches);
        // An imperative push carries the location it was pushed with.
        case ImperativeRouteMatch(:final matches):
          locations.add(matches.uri.toString());
        case RouteMatch(:final matchedLocation):
          locations.add(matchedLocation);
        default:
          break;
      }
    }
  }

  walk(router.routerDelegate.currentConfiguration.matches);
  return locations;
}

/// The location of the page the user is looking at, or null on an empty stack.
String? topRoute(BuildContext context) => routeStack(context).lastOrNull;

/// Whether [path] is already the page on top.
///
/// The re-entrancy guard every "open X" affordance needs: two taps of one
/// control are one intention, and `context.push` updates the page stack
/// synchronously, so the second tap sees what the first one installed.
///
/// Compares PATHS, so a destination that carries query parameters still
/// recognises itself.
bool isTopRoute(BuildContext context, String path) {
  final top = topRoute(context);
  if (top == null) return false;
  return Uri.parse(top).path == Uri.parse(path).path;
}

/// Swaps a finished multi-step flow for the screen that concludes it.
///
/// The wizard's completed steps come off the stack and [destination] goes on in
/// their place, so the conclusion sits directly on whatever the flow was
/// STARTED from. Everything that goes back then goes back there: the screen's
/// own control, the Android system button, and the iOS edge swipe alike. That
/// is why the stack is repaired here, at the moment the run finishes, rather
/// than intercepted later in a `PopScope` — an interceptor can only catch the
/// affordances it knows about, and it buys them by disabling the iOS gesture.
///
/// Returns the number of steps left behind, which is what a test can assert on.
///
/// The count is worked out BEFORE anything is popped: go_router settles its
/// match list during the next frame, so a loop that popped and re-read would
/// read the same stack forever. Consecutive pops are safe — each is applied to
/// the Navigator's history immediately.
int replaceCompletedFlow(
  BuildContext context, {
  required String destination,
  required bool Function(String location) isStep,
}) {
  final router = GoRouter.of(context);
  final popped = _popCompletedSteps(router, isStep);
  router.push(destination);
  return popped;
}

/// Pops the trailing pages [isStep] claims, never the bottom-most one — that is
/// the shell branch's own destination and is not a pushed page. Returns how
/// many came off.
int _popCompletedSteps(GoRouter router, bool Function(String) isStep) {
  final stack = routeStackOf(router);
  var steps = 0;
  for (var i = stack.length - 1; i > 0; i--) {
    if (!isStep(stack[i])) break;
    steps++;
  }
  var popped = 0;
  while (popped < steps && router.canPop()) {
    router.pop();
    popped++;
  }
  return popped;
}

/// Leaves a finished multi-step flow, taking its completed steps with it.
///
/// Pops the current page and every page under it that [isStep] still claims, so
/// Back from what comes next cannot walk back INTO a wizard the user has
/// already finished. When the flow reaches the bottom of the stack with nothing
/// underneath it — a deep link straight into the flow, or a cold start — it
/// lands on [fallback] rather than popping the app away.
///
/// The pop count is worked out BEFORE anything is popped, because go_router
/// settles the match list during the next frame: a loop that popped and then
/// re-read the stack would read the same stack every time and never stop.
/// Consecutive pops are safe — the Navigator applies each one to its own
/// history immediately.
void leaveCompletedFlow(
  BuildContext context, {
  required bool Function(String location) isStep,
  required String fallback,
}) {
  final router = GoRouter.of(context);
  if (_popCompletedSteps(router, isStep) > 0) return;

  // Nothing of the flow was on the stack, or it IS the bottom page — a deep
  // link or a cold start straight into it. Behave like an ordinary back, and
  // land on [fallback] rather than popping the app away.
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}

/// The MoodMirror wizard's own pages: Step 1, Garments, Mode, Generating,
/// Result and the adjust editor all live under one path prefix.
///
/// Used to recognise a FINISHED run's steps so they can be left behind
/// together. It deliberately does not include the body-photo manager: that is a
/// settings-ish destination reachable from outside the flow, and leaving it on
/// the stack is correct.
bool isMirrorFlowStep(String location) =>
    location == AppRoute.wtmMirror ||
    location.startsWith('${AppRoute.wtmMirror}/');
