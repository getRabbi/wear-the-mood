import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/app_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/share/share_service.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'giveaway_disclaimer.dart';
import 'giveaway_status.dart';

/// A giveaway listing in full (FEATURES_COMMUNITY_PLUS · Giveaway): images +
/// details, and either the claim flow (non-owners) or the owner's requests inbox
/// + close. Contact stays in-app; report/close are always available.
class GiveawayDetailScreen extends ConsumerStatefulWidget {
  const GiveawayDetailScreen({super.key, required this.giveawayId});

  final String giveawayId;

  @override
  ConsumerState<GiveawayDetailScreen> createState() =>
      _GiveawayDetailScreenState();
}

class _GiveawayDetailScreenState extends ConsumerState<GiveawayDetailScreen> {
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.giveawayViewed);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _claim() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final msg = _message.text.trim();
      await ref
          .read(giveawayRepositoryProvider)
          .claim(widget.giveawayId, message: msg.isEmpty ? null : msg);
      await ref.read(analyticsProvider).track(AnalyticsEvents.giveawayClaimed);
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      if (mounted) _snack(l10n.giveawayClaimed);
    } on ApiException {
      _snack(l10n.giveawayClaimError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String claimId, String status) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .decide(widget.giveawayId, claimId, status);
      if (status == 'accepted') {
        await ref
            .read(analyticsProvider)
            .track(AnalyticsEvents.giveawayClaimAccepted);
      }
      ref.invalidate(giveawayClaimsProvider(widget.giveawayId));
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
    } on ApiException {
      _snack(l10n.giveawayError);
    }
  }

  /// Owner transitions the listing between the four states (available / reserved
  /// = pending pickup / claimed = given away / closed = cancelled). Cancelling is
  /// confirmed; the rest apply directly. Uses the existing owner-scoped endpoint.
  Future<void> _setStatus(String status) async {
    final l10n = AppLocalizations.of(context);
    if (status == 'closed') {
      final ok = await showConfirmSheet(
        context,
        icon: Icons.cancel_outlined,
        title: l10n.giveawayCancel,
        message: l10n.giveawayDisclaimer,
        confirmLabel: l10n.giveawayCancel,
        cancelLabel: l10n.commonCancel,
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .updateStatus(widget.giveawayId, status);
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      ref.invalidate(giveawayBrowseProvider);
      ref.invalidate(myGiveawaysProvider);
      if (mounted) _snack(l10n.giveawayStatusUpdated);
    } on ApiException {
      _snack(l10n.giveawayError);
    }
  }

  /// PERMANENTLY delete the owner's own listing.
  ///
  /// Deliberately separate from [_setStatus]: `closed` cancels the giveaway but
  /// keeps the post and its history, which is a reversible product state. This
  /// destroys the listing, its requests, its pickup chat and its public media,
  /// so it is confirmed first and the confirmation says exactly what goes.
  ///
  /// Nothing is removed locally before the server succeeds — on failure the post
  /// stays on screen and the error says so, because a list that optimistically
  /// drops a row the server still has is worse than a visible failure.
  Future<void> _delete(Giveaway g) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_forever_outlined,
      title: l10n.giveawayDeleteConfirmTitle,
      message: l10n.giveawayDeleteConfirmBody,
      confirmLabel: l10n.giveawayDeleteConfirmAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(giveawayRepositoryProvider).delete(widget.giveawayId);
    } on ApiException {
      // The listing is untouched; say so rather than a generic failure.
      if (mounted) _snack(l10n.giveawayDeleteFailed);
      return;
    }
    // Only after the server confirmed. Every surface that could still be showing
    // this listing is dropped: browse, the owner's own list, the requester-side
    // list, and the per-listing detail/claims caches.
    ref.invalidate(giveawayBrowseProvider);
    ref.invalidate(myGiveawaysProvider);
    ref.invalidate(requestedGiveawaysProvider);
    ref.invalidate(giveawayDetailProvider(widget.giveawayId));
    ref.invalidate(giveawayClaimsProvider(widget.giveawayId));
    if (!mounted) return;
    _snack(l10n.giveawayDeleted);
    // Leave the detail we just destroyed. Falling back to the giveaways list
    // matters for the notification-tap entry point, which has nothing to pop to.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoute.wtmGiveaways);
    }
  }

  /// Share the giveaway — title + invite + install link (outbound only; opening
  /// the exact listing in-app would need deep links, a later piece).
  Future<void> _share(Giveaway g) async {
    final l10n = AppLocalizations.of(context);
    final text =
        '${g.title}\n\n${l10n.giveawayShareText}\n${AppLinks.androidStore}';
    try {
      await ref.read(shareServiceProvider).shareText(text);
    } catch (_) {
      _snack(l10n.shareFailed);
    }
  }

  Future<void> _report() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.flag_outlined,
      title: l10n.giveawayReport,
      message: l10n.reportBody,
      confirmLabel: l10n.reportConfirm,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref
          .read(socialRepositoryProvider)
          .report(subjectType: 'giveaway', subjectId: widget.giveawayId);
      _snack(l10n.reported);
    } on ApiException {
      _snack(l10n.giveawayError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayDetailProvider(widget.giveawayId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: l10n.giveawayReport,
            icon: const Icon(Icons.flag_outlined),
            onPressed: _report,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => PremiumLogoLoader(label: l10n.commonLoading),
          error: (_, _) => ErrorState(
            title: l10n.giveawayError,
            onRetry: () =>
                ref.invalidate(giveawayDetailProvider(widget.giveawayId)),
          ),
          data: (g) => _body(context, g),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Giveaway g) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final chips = <String>[
      if (g.size != null && g.size!.isNotEmpty) g.size!,
      if (g.category != null && g.category!.isNotEmpty) g.category!,
      if (g.condition != null && g.condition!.isNotEmpty) g.condition!,
      if (g.areaLabel != null && g.areaLabel!.isNotEmpty) g.areaLabel!,
    ];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (g.images.isNotEmpty)
          SizedBox(
            height: 280,
            child: PageView(
              children: [
                for (final url in g.images)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.mist),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(g.title, style: text.headlineSmall)),
                  IconButton(
                    onPressed: () => _share(g),
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: l10n.commonShare,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  GiveawayStatusBadge(status: g.status),
                  if ((g.ownerName ?? '').isNotEmpty) ...[
                    const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(
                        g.ownerName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ),
                  ],
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [for (final c in chips) AppChip(label: c)],
                ),
              ],
              if (g.description != null && g.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Text(
                  g.description!,
                  style: text.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              if (g.isMine)
                _OwnerSection(
                  giveaway: g,
                  onStatus: _setStatus,
                  onDecide: _decide,
                  onDelete: () => _delete(g),
                )
              else
                _ClaimSection(
                  giveaway: g,
                  controller: _message,
                  busy: _busy,
                  onClaim: _claim,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Non-owner view: claim with an optional private message, or the claim status.
class _ClaimSection extends StatelessWidget {
  const _ClaimSection({
    required this.giveaway,
    required this.controller,
    required this.busy,
    required this.onClaim,
  });

  final Giveaway giveaway;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    if (giveaway.hasClaimed) {
      final accepted = giveaway.myClaimStatus == 'accepted';
      return Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: (accepted ? AppColors.success : AppColors.lavender).withValues(
            alpha: 0.12,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          accepted ? l10n.giveawayClaimAcceptedNote : l10n.giveawayClaimPending,
          style: text.bodyMedium,
        ),
      );
    }

    // Closed / given-away / pending: viewable, but requests are off.
    if (!giveaway.isAvailable) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.muted.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(l10n.giveawayClosedNote, style: text.bodySmall),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GiveawayDisclaimer(),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: l10n.giveawayClaimMessage,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        // Privacy guidance sits right next to the contact field (§10).
        Text(
          l10n.giveawayPrivacyNote,
          style: text.bodySmall?.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: AppSpace.md),
        PrimaryButton(
          label: l10n.giveawayClaimSend,
          icon: Icons.pan_tool_alt_outlined,
          isLoading: busy,
          onPressed: onClaim,
        ),
      ],
    );
  }
}

/// Owner view: status management, the requests inbox (accept/decline) + cancel.
class _OwnerSection extends ConsumerWidget {
  const _OwnerSection({
    required this.giveaway,
    required this.onStatus,
    required this.onDecide,
    required this.onDelete,
  });

  final Giveaway giveaway;
  final void Function(String status) onStatus;
  final void Function(String claimId, String status) onDecide;

  /// Permanent deletion. Only ever reached from this owner-only section, and the
  /// server re-checks ownership regardless — the UI gate is convenience, not the
  /// security boundary.
  final VoidCallback onDelete;

  /// The status transitions offered for the CURRENT status (label → target).
  List<({String label, IconData icon, String status, bool danger})> _actions(
    AppLocalizations l10n,
  ) {
    final markPending = (
      label: l10n.giveawayMarkPending,
      icon: Icons.schedule_rounded,
      status: 'reserved',
      danger: false,
    );
    final markGiven = (
      label: l10n.giveawayMarkGiven,
      icon: Icons.card_giftcard_rounded,
      status: 'claimed',
      danger: false,
    );
    final reopen = (
      label: l10n.giveawayReopen,
      icon: Icons.refresh_rounded,
      status: 'available',
      danger: false,
    );
    final cancel = (
      label: l10n.giveawayCancel,
      icon: Icons.cancel_outlined,
      status: 'closed',
      danger: true,
    );
    switch (giveaway.status) {
      case 'available':
        return [markPending, markGiven, cancel];
      case 'reserved':
        return [markGiven, reopen, cancel];
      case 'claimed':
        return [reopen, cancel];
      case 'closed':
        return [reopen];
      default:
        return [cancel];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final claims = ref.watch(giveawayClaimsProvider(giveaway.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── status management ──────────────────────────────────────────────
        Text(l10n.giveawayManageStatus, style: text.titleMedium),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final a in _actions(l10n))
              OutlinedButton.icon(
                onPressed: () => onStatus(a.status),
                icon: Icon(
                  a.icon,
                  size: 18,
                  color: a.danger ? AppColors.danger : null,
                ),
                label: Text(
                  a.label,
                  style: a.danger
                      ? const TextStyle(color: AppColors.danger)
                      : null,
                ),
              ),
            // PERMANENT deletion, deliberately alongside the reversible status
            // actions but visually distinct. It is NOT one of `_actions`: those
            // all PATCH a status and can be undone with Reopen, whereas this
            // destroys the listing. Labelled plainly rather than hidden behind
            // status wording, because "Cancel giveaway" already means something
            // else here and conflating them is how people delete by accident.
            OutlinedButton.icon(
              key: const Key('giveaway-delete'),
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_forever_outlined,
                size: 18,
                color: AppColors.danger,
              ),
              label: Text(
                l10n.giveawayDelete,
                style: const TextStyle(color: AppColors.danger),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        // ── requests inbox ─────────────────────────────────────────────────
        Text(l10n.giveawayClaimsTitle, style: text.titleMedium),
        const SizedBox(height: AppSpace.sm),
        claims.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpace.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Text(l10n.giveawayError, style: text.bodySmall),
          data: (list) => list.isEmpty
              ? Text(l10n.giveawayNoClaims, style: text.bodySmall)
              : Column(
                  children: [
                    for (final c in list)
                      _ClaimTile(claim: c, onDecide: onDecide),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim, required this.onDecide});

  final GiveawayClaim claim;
  final void Function(String claimId, String status) onDecide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final pending = claim.status == 'requested';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  claim.claimerName ?? '—',
                  style: text.titleMedium?.copyWith(fontSize: 14),
                ),
              ),
              if (!pending)
                Text(
                  claim.status,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
            ],
          ),
          if (claim.message != null && claim.message!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(claim.message!, style: text.bodySmall),
          ],
          if (pending) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onDecide(claim.id, 'declined'),
                  child: Text(l10n.giveawayDecline),
                ),
                const SizedBox(width: AppSpace.sm),
                FilledButton(
                  onPressed: () => onDecide(claim.id, 'accepted'),
                  child: Text(l10n.giveawayAccept),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
