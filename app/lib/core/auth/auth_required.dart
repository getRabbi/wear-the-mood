import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/app_env.dart';
import 'auth_providers.dart';
import 'guest_session.dart';
import 'protected_action.dart';

/// Thrown when a protected command is invoked without a real authenticated
/// user — the CONTROLLER/SERVICE layer of the guest gate.
///
/// Typed on purpose. The UI needs to tell "you need an account" apart from
/// "the network is down" and from "the server said no", because showing the
/// wrong one of those three is its own bug: a guest who is offline must not be
/// told to sign in, and a signed-in user whose token expired must not be shown
/// a raw backend string.
///
/// It carries no message of its own — the caller maps [action] to localized
/// copy — and no user data, so it is safe to log.
@immutable
class AuthRequiredException implements Exception {
  const AuthRequiredException(this.action);

  /// What the caller was trying to do, so the conversion sheet can be specific.
  final ProtectedAction action;

  @override
  String toString() => 'AuthRequiredException(${action.analyticsName})';
}

/// The service-layer guard. Call this FIRST in any command with a side effect —
/// before an upload, a job, a credit movement, a write, or a provider call.
///
/// Throws [AuthRequiredException] unless a real authenticated session exists.
/// A guard, not an accessor: it deliberately does not hand back a user id,
/// because an id that travels as an argument is an id that can be wrong, and
/// every layer below already derives the identity from the verified token
/// itself (CLAUDE.md §11).
///
/// It fails closed on [AppSessionState.unknown]: a session still being
/// restored, an expired token, or an offline start is NOT permission to act.
void requireAuthenticatedUser(Ref ref, ProtectedAction action) {
  if (!ref.read(appSessionProvider).canPerformProtectedActions) {
    throw AuthRequiredException(action);
  }
  _requireStableIdentity(ref.read(authUserIdProvider), action);
}

/// Same guard for call sites holding a [WidgetRef] rather than a [Ref].
void requireAuthenticatedUserFor(WidgetRef ref, ProtectedAction action) {
  if (!ref.read(appSessionProvider).canPerformProtectedActions) {
    throw AuthRequiredException(action);
  }
  _requireStableIdentity(ref.read(authUserIdProvider), action);
}

/// Belt and braces on top of the session state: "authenticated with no user id"
/// is not a state that should exist, and if it ever does it must not be the one
/// that lets a write out.
///
/// Skipped where no auth system is configured at all, because there is no id to
/// read there and nothing to guard — the same build in which
/// [appSessionProvider] stands aside, and for the same reason (see its note).
void _requireStableIdentity(String? userId, ProtectedAction action) {
  if (!AppEnv.hasSupabaseConfig) return;
  if (userId == null || userId.isEmpty) throw AuthRequiredException(action);
}

/// Non-throwing form, for places that want to branch rather than catch.
bool canPerform(Ref ref) =>
    ref.read(appSessionProvider).canPerformProtectedActions;
