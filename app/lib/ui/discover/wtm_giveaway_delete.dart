import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../widgets/widgets.dart';

/// What a delete attempt actually did, so the caller can navigate honestly.
enum GiveawayDeleteOutcome {
  /// The owner backed out of the confirmation. Nothing was sent.
  cancelled,

  /// The server confirmed. The listing, its claims and its chat are gone.
  deleted,

  /// The server refused or the request failed. The listing is still there.
  failed,
}

/// Confirm and PERMANENTLY delete the caller's own giveaway.
///
/// One implementation for every entry point — the detail screen's action, its
/// overflow menu, and the owner's own card. The first delete shipped on a
/// screen production never renders, so the lesson is baked in here: the surface
/// that offers the action is allowed to vary, the behaviour behind it is not.
///
/// Deliberately hard: the listing, every claim on it and the pickup chat go for
/// all participants, and there is no undo. That is the established Giveaway
/// lifecycle, so the confirmation says exactly that rather than softening it.
///
/// Ownership is enforced SERVER-side. A non-owner gets the same 404 as a
/// missing listing — showing or hiding a button is presentation, never
/// authorization.
///
/// Nothing is removed from the client until the server has answered, because a
/// failed delete must leave the listing exactly where it was. Callers own the
/// in-flight latch (taken BEFORE calling, so two fast taps cannot open two
/// confirmations) and any navigation afterwards.
Future<GiveawayDeleteOutcome> confirmAndDeleteGiveaway(
  BuildContext context,
  WidgetRef ref,
  String giveawayId,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(giveawayRepositoryProvider);

  final confirmed = await wtmConfirmDialog(
    context,
    title: l10n.giveawayDeleteConfirmTitle,
    message: l10n.giveawayDeleteConfirmBody,
    confirmLabel: l10n.giveawayDeleteConfirmAction,
    danger: true,
  );
  if (!confirmed) return GiveawayDeleteOutcome.cancelled;
  if (!context.mounted) return GiveawayDeleteOutcome.cancelled;

  try {
    await repo.delete(giveawayId);
  } on ApiException catch (e) {
    if (context.mounted) wtmSnack(context, e.message);
    return GiveawayDeleteOutcome.failed;
  } catch (_) {
    if (context.mounted) wtmSnack(context, l10n.giveawayDeleteFailed);
    return GiveawayDeleteOutcome.failed;
  }

  await ref.read(analyticsProvider).track(AnalyticsEvents.giveawayDeleted);
  refreshGiveawayLists(ref);
  return GiveawayDeleteOutcome.deleted;
}

/// Every list and counter that can still be showing the listing.
///
/// Includes the requester-side list on purpose: deletion takes their pickup
/// away too, and leaving `requestedGiveawaysProvider` stale is how the two
/// sides end up disagreeing about whether the giveaway exists.
void refreshGiveawayLists(WidgetRef ref, {String? id}) {
  ref.invalidate(giveawayBrowseProvider);
  ref.invalidate(myGiveawaysProvider);
  ref.invalidate(requestedGiveawaysProvider);
  if (id != null) {
    ref.invalidate(giveawayDetailProvider(id));
    ref.invalidate(giveawayClaimsProvider(id));
  }
}

/// The owner's overflow menu for one giveaway.
///
/// Only ever built for `giveaway.isMine`, so a public card stays uncluttered
/// and a non-owner is never offered an action the server would refuse anyway.
Future<void> showGiveawayOwnerMenu(
  BuildContext context, {
  required String title,
  required VoidCallback onDelete,
}) {
  final l10n = AppLocalizations.of(context);
  return showWtmSheet(
    context,
    title: title,
    subtitle: l10n.giveawayOwnerMenuSubtitle,
    children: [
      GhostButton(
        key: const Key('wtm-giveaway-menu-delete'),
        label: l10n.giveawayDelete,
        icon: const WtmIcon(WtmGlyph.erase, size: 15, color: WtmColors.danger),
        foregroundColor: WtmColors.danger,
        borderColor: WtmColors.danger,
        onPressed: () {
          Navigator.of(context).pop();
          onDelete();
        },
      ),
      const SizedBox(height: WtmSpace.s10),
    ],
  );
}
