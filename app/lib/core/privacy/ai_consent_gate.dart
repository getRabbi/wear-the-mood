import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/widgets/widgets.dart';
import 'ai_consent_controller.dart';
import 'ai_disclosure_sheet.dart';
import 'ai_input_privacy.dart';

/// The single gate every remote AI operation passes through before a personal
/// image is transmitted (§10, Apple 5.1.1(i)).
///
/// There is deliberately ONE of these rather than a `showDialog` in each screen.
/// Consent scattered across call sites is consent that a new screen forgets, and
/// the failure mode of forgetting is a user's face reaching a third party
/// without permission — which is the rejection this exists to fix.
///
/// Call it AFTER validation and the credit/entitlement check, and BEFORE the
/// job is submitted. Returns true only when the request may proceed.
///
/// ```dart
/// if (!await ensureAiConsent(context, ref, privacy: AiInputPrivacy.personalImage)) {
///   return; // nothing charged, nothing sent, selections untouched
/// }
/// ```
Future<bool> ensureAiConsent(
  BuildContext context,
  WidgetRef ref, {
  required AiInputPrivacy privacy,
}) async {
  // Local-only and non-personal work is never gated. This is the branch that
  // keeps 2D free of friction and stops a studio-model render asking permission
  // to share a photo that is ours, not the user's.
  if (!privacy.requiresPersonalImageConsent) return true;

  final controller = ref.read(aiConsentProvider.notifier);
  final l10n = AppLocalizations.of(context);

  // Already allowed at the version the server requires → straight through, no
  // sheet. This is the normal path for every render after the first.
  try {
    if ((await controller.current()).isCurrent) return true;
  } catch (_) {
    // We could not find out. Fall through to ask rather than assume: an
    // unreachable consent API must never become an implied permission. If the
    // network really is down, the grant below fails too and we stop cleanly
    // without charging or sending anything.
  }

  if (!context.mounted) return false;
  final choice = await showAiDisclosureSheet(context);
  if (choice != AiDisclosureChoice.allow) return false;

  // Record the grant BEFORE proceeding, and only continue on a confirmed server
  // write. Proceeding optimistically would let a failed write become a render
  // the user's account has no record of authorising.
  try {
    final state = await controller.grant();
    if (!state.isCurrent) return false;
    return true;
  } catch (_) {
    if (context.mounted) wtmSnack(context, l10n.aiDisclosureSaveError);
    return false;
  }
}
