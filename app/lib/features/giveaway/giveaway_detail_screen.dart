import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/app_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/share/share_service.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'giveaway_disclaimer.dart';

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

  Future<void> _close() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.lock_outline_rounded,
      title: l10n.giveawayClose,
      message: l10n.giveawayDisclaimer,
      confirmLabel: l10n.giveawayClose,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .updateStatus(widget.giveawayId, 'closed');
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      ref.invalidate(giveawayBrowseProvider);
      ref.invalidate(myGiveawaysProvider);
    } on ApiException {
      _snack(l10n.giveawayError);
    }
  }

  /// Share the giveaway — title + invite + install link (outbound only; opening
  /// the exact listing in-app would need deep links, a later piece).
  Future<void> _share(Giveaway g) async {
    final l10n = AppLocalizations.of(context);
    final text = '${g.title}\n\n${l10n.giveawayShareText}\n${AppLinks.androidStore}';
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
      await ref.read(socialRepositoryProvider).report(
            subjectType: 'giveaway',
            subjectId: widget.giveawayId,
          );
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
          loading: () => const Center(child: CircularProgressIndicator()),
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
              const SizedBox(height: AppSpace.xs),
              Text(
                '${g.ownerName ?? ''} · ${g.status}',
                style: text.bodySmall?.copyWith(color: AppColors.muted),
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
                Text(g.description!,
                    style: text.bodyMedium?.copyWith(height: 1.5)),
              ],
              const SizedBox(height: AppSpace.lg),
              if (g.isMine)
                _OwnerSection(giveawayId: g.id, onClose: _close, onDecide: _decide)
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
          color: (accepted ? AppColors.success : AppColors.lavender)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          accepted
              ? l10n.giveawayClaimAcceptedNote
              : l10n.giveawayClaimPending,
          style: text.bodyMedium,
        ),
      );
    }

    if (!giveaway.isAvailable) {
      return Text(l10n.giveawayEmptyMessage, style: text.bodySmall);
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

/// Owner view: the requests inbox (accept/decline) + close the listing.
class _OwnerSection extends ConsumerWidget {
  const _OwnerSection({
    required this.giveawayId,
    required this.onClose,
    required this.onDecide,
  });

  final String giveawayId;
  final VoidCallback onClose;
  final void Function(String claimId, String status) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final claims = ref.watch(giveawayClaimsProvider(giveawayId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: AppSpace.lg),
        GhostButton(
          label: l10n.giveawayClose,
          icon: Icons.lock_outline_rounded,
          onPressed: onClose,
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
                child: Text(claim.claimerName ?? '—',
                    style: text.titleMedium?.copyWith(fontSize: 14)),
              ),
              if (!pending)
                Text(claim.status,
                    style: text.bodySmall?.copyWith(color: AppColors.muted)),
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
