import 'package:flutter/foundation.dart';

import 'protected_action.dart';

/// What a guest was bounced away from, so the public screen they land on can
/// explain itself instead of silently swallowing the tap.
@immutable
class GuestIntercept {
  const GuestIntercept({required this.action, this.resourceId});

  final ProtectedAction action;

  /// The PUBLIC id carried by the blocked link (`?id=`), when it had one, so a
  /// resumed Save or giveaway entry returns to the right item.
  final String? resourceId;

  @override
  bool operator ==(Object other) =>
      other is GuestIntercept &&
      other.action == action &&
      other.resourceId == resourceId;

  @override
  int get hashCode => Object.hash(action, resourceId);
}

/// The router's outbox.
///
/// A `go_router` redirect must stay a pure function of location and state —
/// mutating a provider inside one throws ("modified during build") and, worse,
/// can loop. So the redirect drops a value here, on a plain [ValueNotifier] that
/// belongs to no provider graph, and the widget layer picks it up on the next
/// frame and raises the conversion sheet.
///
/// It is a single slot rather than a queue on purpose: a burst of blocked
/// navigations (a rapid double tap, a push arriving during a redirect) should
/// produce ONE sheet about the most recent thing, not a stack of them.
///
/// [take] clears as it reads, so a rebuild cannot re-show a sheet that has
/// already been answered.
final guestIntercepts = ValueNotifier<GuestIntercept?>(null);

/// Records a blocked navigation. Safe to call from inside a redirect: it only
/// writes to the notifier above, never to a provider.
void noteGuestIntercept(String location, {String? resourceId}) {
  guestIntercepts.value = GuestIntercept(
    action: ProtectedAction.forRoute(location),
    resourceId: resourceId,
  );
}

/// Reads and clears the pending intercept.
GuestIntercept? takeGuestIntercept() {
  final value = guestIntercepts.value;
  if (value != null) guestIntercepts.value = null;
  return value;
}
