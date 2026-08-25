import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_required.dart';
import '../../core/auth/guest_session.dart';
import '../../core/auth/protected_action.dart';
import 'wtm_guest_conversion_sheet.dart';

/// The UI layer of the guest gate — the one call every protected entry point
/// makes before it does anything.
///
/// ```dart
/// if (!await ensureAccount(context, ref, ProtectedAction.tryOn)) return;
/// // ...only now may a picker open, a permission be asked for, or a call fire
/// ```
///
/// Returns true only when a real authenticated session already exists. For
/// anyone else it shows the conversion sheet and returns **false** — including
/// when the sign-in inside the sheet succeeds.
///
/// That last part is deliberate. A successful sign-in re-enters the flow
/// through the pending-intent resume (`guest_auth_resume.dart`), so there is
/// exactly ONE path back into a protected action instead of two that can
/// disagree about whether it already ran. It also means no caller is left
/// holding a `BuildContext` from before the identity changed, on a screen the
/// account switch has since torn down and rebuilt.
///
/// [AppSessionState.unknown] and [AppSessionState.signedOut] also return false.
/// The router keeps a signed-in user off these screens, so neither should be
/// reachable here — but if one ever is, denying is the correct answer.
Future<bool> ensureAccount(
  BuildContext context,
  WidgetRef ref,
  ProtectedAction action, {

  /// A PUBLIC resource id (product, giveaway) to return to after sign-in.
  /// Never a photo, a draft or anything private.
  String? resourceId,
}) async {
  if (ref.read(appSessionProvider).canPerformProtectedActions) return true;
  await showGuestConversionSheet(
    context,
    ref,
    action: action,
    resourceId: resourceId,
  );
  return false;
}

/// Runs [body] only for an authenticated user, converting a guest instead.
///
/// The service-layer guard still runs inside [body] — this is convenience, not
/// the security boundary. Both exist on purpose: this one keeps the UI honest
/// (nothing starts), the guard keeps it safe (nothing escapes). The `catch`
/// closes the gap between them: a session can die between the check and the
/// call — expiry, sign-out, deletion on another device — and when it does the
/// user gets the same sheet rather than a crash or a raw backend string.
Future<void> runProtected(
  BuildContext context,
  WidgetRef ref,
  ProtectedAction action,
  Future<void> Function() body, {
  String? resourceId,
}) async {
  if (!ref.read(appSessionProvider).canPerformProtectedActions) {
    await showGuestConversionSheet(
      context,
      ref,
      action: action,
      resourceId: resourceId,
    );
    return;
  }
  try {
    await body();
  } on AuthRequiredException catch (error) {
    if (!context.mounted) return;
    await showGuestConversionSheet(
      context,
      ref,
      action: error.action,
      resourceId: resourceId,
    );
  }
}

/// Maps an [AuthRequiredException] escaping a controller/service onto the same
/// sheet, so both enforcement layers present identically to the user.
///
/// Use it in a `catch` around a protected command. Anything that is NOT an
/// auth-required failure is rethrown untouched — a network outage must keep
/// reading as a network outage, never as "please sign in".
Future<void> handleAuthRequired(
  BuildContext context,
  WidgetRef ref,
  Object error, {
  String? resourceId,
}) async {
  if (error is! AuthRequiredException) throw error;
  if (!context.mounted) return;
  await showGuestConversionSheet(
    context,
    ref,
    action: error.action,
    resourceId: resourceId,
  );
}
