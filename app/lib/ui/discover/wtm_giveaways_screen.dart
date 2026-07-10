import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Giveaways (board 08, P9) — the community item-giveaway browse grid on
/// [giveawayBrowseProvider]. Tap → the detail (`?id=`), which is also the Inbox
/// Drops deep-link target.
class WtmGiveawaysScreen extends ConsumerWidget {
  const WtmGiveawaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayBrowseProvider);

    return WtmPage(
      title: l10n.wtmGiveawaysTitle,
      eyebrow: l10n.wtmDiscover,
      // Persistent "give an item away" action — wired to the real create flow.
      trailing: WtmIconButton(
        WtmGlyph.plus,
        semanticLabel: l10n.giveawayCreateTitle,
        onTap: () => context.push(AppRoute.wtmGiveawayCreate),
      ),
      children: async.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 120),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmGiveawaysErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(giveawayBrowseProvider),
          ),
        ],
        data: (items) => items.isEmpty
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmEmptyState(
                  glyph: WtmGlyph.gift,
                  title: l10n.wtmGiveawaysEmptyTitle,
                  message: l10n.wtmGiveawaysEmptyMessage,
                  ctaLabel: l10n.giveawayCreateTitle,
                  onCta: () => context.push(AppRoute.wtmGiveawayCreate),
                ),
              ]
            : [
                for (final (i, g) in items.indexed) ...[
                  if (i > 0) const SizedBox(height: WtmSpace.s10),
                  _GiveawayCard(giveaway: g),
                ],
              ],
      ),
    );
  }
}

class _GiveawayCard extends StatelessWidget {
  const _GiveawayCard({required this.giveaway});

  final Giveaway giveaway;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cover = giveaway.coverImageUrl;
    return Semantics(
      button: true,
      label: giveaway.title,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              context.push('${AppRoute.wtmGiveawayDetail}?id=${giveaway.id}'),
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s12),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  height: 100,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(WtmRadius.tile),
                    child: cover == null
                        ? const AuroraBox(
                            child: Center(
                              child: WtmIcon(WtmGlyph.gift,
                                  size: 22, color: WtmColors.gold),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: cover,
                            cacheKey: stableImageCacheKey(cover),
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const AuroraBox(),
                            errorWidget: (_, _, _) => const AuroraBox(),
                          ),
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EyebrowLabel(giveaway.isAvailable
                          ? l10n.wtmGiveawayOpen
                          : l10n.wtmGiveawayClosed),
                      const SizedBox(height: 6),
                      Text(giveaway.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.h2.copyWith(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        giveaway.ownerName ?? l10n.wtmGiveawayMember,
                        style: WtmType.micro,
                      ),
                      const SizedBox(height: WtmSpace.s6),
                      Text(l10n.wtmGiveawayInterested(giveaway.claimCount),
                          style: WtmType.micro.copyWith(color: WtmColors.gold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Giveaway detail (board §3.17, P9) — hero, item, status, then the pickup
/// flow: Request Item → owner's private Requests inbox → accept ONE → both
/// sides get the Secret Pickup Chat. Reached with `?id=`.
class WtmGiveawayDetailScreen extends ConsumerStatefulWidget {
  const WtmGiveawayDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<WtmGiveawayDetailScreen> createState() =>
      _WtmGiveawayDetailScreenState();
}

class _WtmGiveawayDetailScreenState
    extends ConsumerState<WtmGiveawayDetailScreen> {
  bool _busy = false;

  void _refreshAll() {
    ref.invalidate(giveawayDetailProvider(widget.id));
    ref.invalidate(giveawayClaimsProvider(widget.id));
    ref.invalidate(giveawayBrowseProvider);
    ref.invalidate(myGiveawaysProvider);
  }

  Future<void> _request() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(giveawayRepositoryProvider).claim(widget.id);
      await ref.read(analyticsProvider).track(AnalyticsEvents.giveawayClaimed);
      ref.invalidate(giveawayDetailProvider(widget.id));
      if (mounted) wtmSnack(context, l10n.wtmGiveawayEntered);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmGiveawaysErrorTitle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRequest() async {
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmGiveawayCancelRequestTitle,
      message: l10n.wtmGiveawayCancelRequestBody,
      confirmLabel: l10n.wtmGiveawayCancelRequest,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(giveawayRepositoryProvider).cancelClaim(widget.id);
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayClaimCancelled);
      _refreshAll();
      if (mounted) wtmSnack(context, l10n.wtmGiveawayRequestCancelled);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  Future<void> _decide(GiveawayClaim claim, bool accept) async {
    final l10n = AppLocalizations.of(context);
    if (accept) {
      final ok = await wtmConfirmDialog(
        context,
        title: l10n.wtmGiveawayAcceptTitle,
        message: l10n.wtmGiveawayAcceptBody,
        confirmLabel: l10n.wtmGiveawayAccept,
      );
      if (!ok || !mounted) return;
    }
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .decide(widget.id, claim.id, accept ? 'accepted' : 'declined');
      if (accept) {
        await ref
            .read(analyticsProvider)
            .track(AnalyticsEvents.giveawayClaimAccepted);
      }
      _refreshAll();
      if (mounted && !accept) wtmSnack(context, l10n.wtmGiveawayDeclinedNote);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  Future<void> _markGiven() async {
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmGiveawayMarkGivenTitle,
      message: l10n.wtmGiveawayMarkGivenBody,
      confirmLabel: l10n.wtmGiveawayMarkGiven,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .updateStatus(widget.id, 'claimed');
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayMarkedGiven);
      _refreshAll();
      if (mounted) wtmSnack(context, l10n.wtmGiveawayUpdated);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  void _openChat() {
    ref.read(analyticsProvider).track(AnalyticsEvents.giveawayChatOpened);
    context.push('${AppRoute.wtmGiveawayChat}?id=${widget.id}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayDetailProvider(widget.id));
    final chatOn =
        ref.watch(featureEnabledProvider(FeatureFlags.giveawayChat));

    return WtmPage(
      title: async.asData?.value.title ?? l10n.wtmGiveawaysTitle,
      eyebrow: l10n.wtmDiscover,
      children: async.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 180),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmGiveawaysErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(giveawayDetailProvider(widget.id)),
          ),
        ],
        data: (g) {
          final cover = g.coverImageUrl;
          return [
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WtmRadius.card),
                child: cover == null
                    ? const AuroraBox(
                        vignette: true,
                        child: Center(
                          child: WtmIcon(WtmGlyph.gift,
                              size: 40, color: WtmColors.gold),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: cover,
                        cacheKey: stableImageCacheKey(cover),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, _) =>
                            const AuroraBox(vignette: true),
                        errorWidget: (_, _, _) =>
                            const AuroraBox(vignette: true),
                      ),
              ),
            ),
            const SizedBox(height: WtmSpace.s14),
            Text(g.title,
                textAlign: TextAlign.center,
                style: WtmType.h2.copyWith(fontSize: 20)),
            const SizedBox(height: WtmSpace.s6),
            Text(
              [
                g.ownerName ?? l10n.wtmGiveawayMember,
                if ((g.areaLabel ?? '').isNotEmpty) g.areaLabel!,
              ].join(' · '),
              textAlign: TextAlign.center,
              style: WtmType.micro,
            ),
            if ((g.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: WtmSpace.s12),
              Text(g.description!.trim(),
                  style: WtmType.body.copyWith(fontSize: 12.5, height: 1.5)),
            ],
            const SizedBox(height: WtmSpace.s16),
            if (g.isMine)
              _OwnerPanel(
                giveaway: g,
                chatOn: chatOn,
                onDecide: _decide,
                onMarkGiven: _markGiven,
                onOpenChat: _openChat,
              )
            else
              _RequesterPanel(
                giveaway: g,
                busy: _busy,
                chatOn: chatOn,
                onRequest: _request,
                onCancel: _cancelRequest,
                onOpenChat: _openChat,
              ),
            const SizedBox(height: WtmSpace.s14),
            Text(l10n.wtmGiveawayRules,
                style: WtmType.micro.copyWith(height: 1.55)),
          ];
        },
      ),
    );
  }
}

/// Non-owner: request → requested → accepted (secret chat) / not selected /
/// given. A cancelled request can be re-sent while the listing is open.
class _RequesterPanel extends StatelessWidget {
  const _RequesterPanel({
    required this.giveaway,
    required this.busy,
    required this.chatOn,
    required this.onRequest,
    required this.onCancel,
    required this.onOpenChat,
  });

  final Giveaway giveaway;
  final bool busy;
  final bool chatOn;
  final VoidCallback onRequest;
  final VoidCallback onCancel;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final given = giveaway.status == 'claimed';

    switch (giveaway.myClaimStatus) {
      case 'accepted':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GoldPill(
                label: given
                    ? l10n.wtmGiveawayGivenPill
                    : l10n.wtmGiveawayAcceptedPill,
                icon: const WtmIcon(WtmGlyph.check,
                    size: 12, color: WtmColors.gold),
              ),
            ),
            if (chatOn) ...[
              const SizedBox(height: WtmSpace.s12),
              GradientCta(
                label: l10n.wtmGiveawayOpenChat,
                icon: const WtmIcon(WtmGlyph.comment,
                    size: 15, color: WtmColors.ctaText),
                onPressed: onOpenChat,
              ),
            ],
          ],
        );
      case 'requested':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GoldPill(
                label: l10n.wtmGiveawayEnteredPill,
                icon: const WtmIcon(WtmGlyph.check,
                    size: 12, color: WtmColors.gold),
              ),
            ),
            const SizedBox(height: WtmSpace.s12),
            GhostButton(
              label: l10n.wtmGiveawayCancelRequest,
              onPressed: onCancel,
            ),
          ],
        );
      case 'declined' || 'not_selected' || 'expired':
        return Center(
          child: Text(l10n.wtmGiveawayNotSelected, style: WtmType.sub),
        );
      default: // no request yet, or a cancelled one (re-request allowed)
        if (given) {
          return Center(
            child: Text(l10n.wtmGiveawayGivenPill, style: WtmType.micro),
          );
        }
        if (!giveaway.isAvailable) {
          return Center(
            child: Text(l10n.wtmGiveawayClosed, style: WtmType.micro),
          );
        }
        return GradientCta(
          label: l10n.wtmGiveawayEnter,
          icon:
              const WtmIcon(WtmGlyph.gift, size: 15, color: WtmColors.ctaText),
          onPressed: busy ? null : onRequest,
        );
    }
  }
}

/// Owner: the PRIVATE requests inbox (accept ONE / decline), the accepted
/// pickup card with the secret chat, and Mark as Given.
class _OwnerPanel extends ConsumerWidget {
  const _OwnerPanel({
    required this.giveaway,
    required this.chatOn,
    required this.onDecide,
    required this.onMarkGiven,
    required this.onOpenChat,
  });

  final Giveaway giveaway;
  final bool chatOn;
  final void Function(GiveawayClaim claim, bool accept) onDecide;
  final VoidCallback onMarkGiven;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final claims = ref.watch(giveawayClaimsProvider(giveaway.id));
    final given = giveaway.status == 'claimed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (given)
          Center(
            child: GoldPill(
              label: l10n.wtmGiveawayGivenPill,
              icon:
                  const WtmIcon(WtmGlyph.check, size: 12, color: WtmColors.gold),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(child: EyebrowLabel(l10n.wtmGiveawayRequestsTitle)),
            ],
          ),
          const SizedBox(height: WtmSpace.s4),
          Text(l10n.wtmGiveawayRequestsPrivate, style: WtmType.micro),
          const SizedBox(height: WtmSpace.s10),
          claims.when(
            loading: () =>
                const LoadingShimmer(width: double.infinity, height: 64),
            error: (_, _) =>
                Text(l10n.wtmGiveawayRequestsError, style: WtmType.sub),
            data: (list) {
              final accepted =
                  list.where((c) => c.status == 'accepted').toList();
              final pending =
                  list.where((c) => c.status == 'requested').toList();
              if (accepted.isEmpty && pending.isEmpty) {
                return Text(l10n.wtmGiveawayNoRequests, style: WtmType.sub);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in accepted) ...[
                    _AcceptedCard(
                      claim: c,
                      chatOn: chatOn,
                      onOpenChat: onOpenChat,
                      onMarkGiven: onMarkGiven,
                    ),
                    const SizedBox(height: WtmSpace.s10),
                  ],
                  for (final c in pending) ...[
                    _RequestTile(claim: c, onDecide: onDecide),
                    const SizedBox(height: WtmSpace.s10),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// One pending request — name + private note + Accept / Decline.
class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.claim, required this.onDecide});

  final GiveawayClaim claim;
  final void Function(GiveawayClaim claim, bool accept) onDecide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(claim.claimerName ?? l10n.wtmGiveawayMember,
              style: WtmType.labelMedium),
          if ((claim.message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: WtmSpace.s4),
            Text(claim.message!.trim(), style: WtmType.sub),
          ],
          const SizedBox(height: WtmSpace.s10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GoldPill(
                label: l10n.wtmGiveawayDecline,
                onTap: () => onDecide(claim, false),
              ),
              const SizedBox(width: WtmSpace.s8),
              GoldPill(
                label: l10n.wtmGiveawayAccept,
                icon: const WtmIcon(WtmGlyph.check,
                    size: 12, color: WtmColors.gold),
                onTap: () => onDecide(claim, true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The accepted requester — pickup in progress: open the secret chat, then
/// Mark as Given once handed over.
class _AcceptedCard extends StatelessWidget {
  const _AcceptedCard({
    required this.claim,
    required this.chatOn,
    required this.onOpenChat,
    required this.onMarkGiven,
  });

  final GiveawayClaim claim;
  final bool chatOn;
  final VoidCallback onOpenChat;
  final VoidCallback onMarkGiven;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        gradient: WtmGradients.assistFill,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.assistBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.wtmGiveawayPickupWith(
                      claim.claimerName ?? l10n.wtmGiveawayMember),
                  style: WtmType.labelMedium,
                ),
              ),
              GoldPill(label: l10n.wtmGiveawayAcceptedPill),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          if (chatOn) ...[
            GradientCta(
              label: l10n.wtmGiveawayOpenChat,
              icon: const WtmIcon(WtmGlyph.comment,
                  size: 15, color: WtmColors.ctaText),
              onPressed: onOpenChat,
            ),
            const SizedBox(height: WtmSpace.s8),
          ],
          GhostButton(
            label: l10n.wtmGiveawayMarkGiven,
            icon: const WtmIcon(WtmGlyph.check,
                size: 15, color: WtmColors.gold),
            foregroundColor: WtmColors.gold,
            onPressed: onMarkGiven,
          ),
        ],
      ),
    );
  }
}
