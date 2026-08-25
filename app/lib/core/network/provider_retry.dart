import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_required.dart';
import 'api_exception.dart';

/// The app-wide provider retry policy.
///
/// Riverpod 3 retries a failed provider automatically: ten attempts, backing
/// off 200ms, 400ms, 800ms … capped at 6.4s — about 38 seconds of trying. That
/// is the right behaviour for a dropped request on a train, and it is why this
/// only narrows the policy rather than replacing it.
///
/// It is the wrong behaviour for **"you are not signed in"**. That is not a
/// transient fault; it is a statement about who is asking, and it will answer
/// the same way ten times in a row. Retrying it costs a guest a request storm
/// for every protected provider that happens to be on screen, and — the part
/// that was actually reported — leaves the provider graph mid-backoff at the
/// exact moment the person signs in.
///
/// What that looked like on a device: browse as a guest, sign in, and the
/// Closet sat there until "Try again" was tapped while everything else trickled
/// in over the next half minute. The providers were not broken. They were
/// waiting out timers scheduled for a condition that had already changed.
///
/// An identity change rebuilds `dioProvider`, which rebuilds every repository,
/// which rebuilds every provider that reads one — so a refused provider is
/// re-run the moment there IS a session. Nothing is lost by not retrying; the
/// retry was never the thing that recovered it.
Duration? appProviderRetry(int retryCount, Object error) {
  if (isAuthenticationFailure(error)) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

/// Whether [error] means "this needs an account" rather than "this went wrong".
///
/// Deliberately narrow. Only the two shapes that carry an authentication
/// verdict qualify; a timeout, a 5xx, a parse failure and a dropped connection
/// are all still retried, because those are exactly what retrying is for.
bool isAuthenticationFailure(Object error) {
  // The service-layer guest gate (`requireAuthenticatedUser`).
  if (error is AuthRequiredException) return true;
  if (error is ApiException) {
    // 401 from the guest network guard, from a genuinely expired session, or
    // from the backend itself; 403 is a permission decision, equally settled.
    return error.code == ApiErrorCode.unauthenticated ||
        error.code == ApiErrorCode.forbidden;
  }
  return false;
}
