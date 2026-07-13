import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/paywall/account_status.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../closet/wtm_add_garment_screen.dart' show WtmGoldProgress;
import 'wtm_buttons.dart';
import 'wtm_icons.dart';

/// Which purchase just completed — drives the confirmation copy + whether a
/// "View membership" action is offered (subscriptions only).
enum PurchaseSuccessKind { pro, proMax, topUp }

/// Immediate, in-app post-purchase confirmation (NEVER a system push, §20). Runs
/// [runSync] (the bounded backend reconcile) in the background: shows a calm
/// "syncing" state until it settles, the fresh credit total once it does, or a
/// non-error "still syncing" fallback with a Refresh action if the webhook is
/// slow. Returns true only if the user tapped "View membership".
///
/// Backend stays authoritative for credit balances — this reads them from
/// [accountStatusProvider], never granting anything locally.
Future<bool> showWtmPurchaseSuccess(
  BuildContext context, {
  required PurchaseSuccessKind kind,
  required Future<bool> Function() runSync,
  int topUpAmount = 40,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0xB3050308),
    builder: (_) => _PurchaseSuccessDialog(
      kind: kind,
      runSync: runSync,
      topUpAmount: topUpAmount,
    ),
  );
  return result ?? false;
}

enum _SyncPhase { syncing, synced, pending }

class _PurchaseSuccessDialog extends ConsumerStatefulWidget {
  const _PurchaseSuccessDialog({
    required this.kind,
    required this.runSync,
    required this.topUpAmount,
  });

  final PurchaseSuccessKind kind;
  final Future<bool> Function() runSync;
  final int topUpAmount;

  @override
  ConsumerState<_PurchaseSuccessDialog> createState() =>
      _PurchaseSuccessDialogState();
}

class _PurchaseSuccessDialogState
    extends ConsumerState<_PurchaseSuccessDialog> {
  _SyncPhase _phase = _SyncPhase.syncing;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    if (mounted) setState(() => _phase = _SyncPhase.syncing);
    final synced = await widget.runSync();
    // The dialog may have been dismissed while the poll ran — the poll itself
    // is owned by the service/providers and completes regardless.
    if (!mounted) return;
    setState(() => _phase = synced ? _SyncPhase.synced : _SyncPhase.pending);
  }

  bool get _isSubscription => widget.kind != PurchaseSuccessKind.topUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(accountStatusProvider);

    final (title, body) = switch (widget.kind) {
      PurchaseSuccessKind.pro => (l10n.wtmSuccessProTitle, l10n.wtmSuccessProBody),
      PurchaseSuccessKind.proMax => (
        l10n.wtmSuccessProMaxTitle,
        l10n.wtmSuccessProMaxBody,
      ),
      PurchaseSuccessKind.topUp => (
        l10n.wtmSuccessTopupTitle(widget.topUpAmount),
        l10n.wtmSuccessTopupBody,
      ),
    };

    return Dialog(
      backgroundColor: WtmColors.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WtmRadius.card),
        side: const BorderSide(color: WtmColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WtmSpace.s18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SuccessBadge(),
            const SizedBox(height: WtmSpace.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WtmType.h1.copyWith(fontSize: 20),
            ),
            const SizedBox(height: WtmSpace.s8),
            Text(body, textAlign: TextAlign.center, style: WtmType.sub),
            const SizedBox(height: WtmSpace.s14),
            _StatusArea(
              phase: _phase,
              totalAvailable: status.totalAvailable,
              onRefresh: _startSync,
            ),
            const SizedBox(height: WtmSpace.s16),
            GradientCta(
              label: l10n.wtmSuccessContinue,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            if (_isSubscription) ...[
              const SizedBox(height: WtmSpace.s10),
              GhostButton(
                label: l10n.wtmSuccessViewMembership,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The confirmation status line: a calm syncing indicator, the fresh credit
/// total once synced, or a reassuring "still syncing" fallback + Refresh.
class _StatusArea extends StatelessWidget {
  const _StatusArea({
    required this.phase,
    required this.totalAvailable,
    required this.onRefresh,
  });

  final _SyncPhase phase;
  final int totalAvailable;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (phase) {
      case _SyncPhase.syncing:
        return Column(
          children: [
            Text(
              l10n.wtmSuccessSyncing,
              textAlign: TextAlign.center,
              style: WtmType.micro,
            ),
            const SizedBox(height: WtmSpace.s10),
            const WtmGoldProgress(),
          ],
        );
      case _SyncPhase.synced:
        // The fresh, server-authoritative total.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: WtmColors.pillBg,
            borderRadius: BorderRadius.circular(WtmRadius.chip),
            border: Border.all(color: WtmColors.pillBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WtmIcon(WtmGlyph.coin, size: 15, color: WtmColors.gold),
              const SizedBox(width: WtmSpace.s6),
              Flexible(
                child: Text(
                  l10n.wtmSuccessCreditsAvailable(totalAvailable),
                  textAlign: TextAlign.center,
                  style: WtmType.labelMedium.copyWith(color: WtmColors.gold),
                ),
              ),
            ],
          ),
        );
      case _SyncPhase.pending:
        return Column(
          children: [
            Text(
              l10n.wtmSuccessPending,
              textAlign: TextAlign.center,
              style: WtmType.micro,
            ),
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: l10n.wtmSuccessRefresh,
              icon: const WtmIcon(
                WtmGlyph.shield,
                size: 14,
                color: WtmColors.text,
              ),
              onPressed: onRefresh,
            ),
          ],
        );
    }
  }
}

/// A gold success ring + check that scales/fades in once (tasteful, not bouncy).
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
      ),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: WtmColors.pillBg,
          border: Border.all(color: WtmColors.pillBorder),
        ),
        alignment: Alignment.center,
        child: const WtmIcon(WtmGlyph.check, size: 26, color: WtmColors.gold),
      ),
    );
  }
}
