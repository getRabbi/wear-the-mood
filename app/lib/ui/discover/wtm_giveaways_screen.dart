import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wtm_discover_artwork.dart';
import 'wtm_giveaway_delete.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Giveaways (board 08, P9) — the community item-giveaway browse grid on
/// [giveawayBrowseProvider]. Tap → the detail (`?id=`), which is also the Inbox
/// Drops deep-link target.
///
/// The **My requests** tab is not decoration: browse only lists `available`
/// listings, so the instant an owner accepts a requester the listing flips to
/// `reserved` and vanishes from the only view that requester had. Without this
/// tab their accepted state and pickup chat are reachable only through a
/// notification. [requestedGiveawaysProvider] restores it from the database.
class WtmGiveawaysScreen extends ConsumerStatefulWidget {
  const WtmGiveawaysScreen({super.key});

  @override
  ConsumerState<WtmGiveawaysScreen> createState() => _WtmGiveawaysScreenState();
}

class _WtmGiveawaysScreenState extends ConsumerState<WtmGiveawaysScreen> {
  bool _mine = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = _mine
        ? requestedGiveawaysProvider
        : giveawayBrowseProvider;
    final async = ref.watch(provider);

    return WtmPage(
      title: l10n.wtmGiveawaysTitle,
      eyebrow: l10n.wtmDiscover,
      // Persistent "give an item away" action — wired to the real create flow.
      trailing: WtmIconButton(
        WtmGlyph.plus,
        semanticLabel: l10n.giveawayCreateTitle,
        onTap: () => context.push(AppRoute.wtmGiveawayCreate),
      ),
      children: [
        WtmChipRow(
          children: [
            WtmChip(
              label: l10n.giveawayBrowseTab,
              on: !_mine,
              onTap: () => setState(() => _mine = false),
            ),
            WtmChip(
              label: l10n.giveawayMyRequests,
              on: _mine,
              onTap: () => setState(() => _mine = true),
            ),
          ],
        ),
        const SizedBox(height: WtmSpace.s14),
        ...async.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => const [
            LoadingShimmer(width: double.infinity, height: 120),
          ],
          error: (_, _) => [
            WtmErrorState(
              title: l10n.wtmGiveawaysErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(provider),
            ),
          ],
          data: (items) => items.isEmpty
              ? [
                  const SizedBox(height: WtmSpace.s22),
                  if (_mine)
                    WtmEmptyState(
                      glyph: WtmGlyph.gift,
                      title: l10n.giveawayMyRequests,
                      message: l10n.giveawayNoRequestsYet,
                      ctaLabel: l10n.giveawayBrowseTab,
                      onCta: () => setState(() => _mine = false),
                    )
                  else
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
      ],
    );
  }
}

/// One listing in the browse grid.
///
/// Browse returns the caller's OWN listings alongside everyone else's, so this
/// is the owner's real "my giveaway" surface — and the place a destructive
/// action belongs. The three-dot menu is built only for `isMine`, so a public
/// card carries no owner chrome at all.
class _GiveawayCard extends ConsumerStatefulWidget {
  const _GiveawayCard({required this.giveaway});

  final Giveaway giveaway;

  @override
  ConsumerState<_GiveawayCard> createState() => _GiveawayCardState();
}

class _GiveawayCardState extends ConsumerState<_GiveawayCard> {
  /// Taken before the confirmation opens, so two fast taps cannot produce two
  /// dialogs or two DELETEs.
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _deleting = true);

    final outcome = await confirmAndDeleteGiveaway(
      context,
      ref,
      widget.giveaway.id,
    );
    if (!mounted) return;
    if (outcome != GiveawayDeleteOutcome.deleted) {
      setState(() => _deleting = false);
      return;
    }
    // The invalidated lists rebuild without this card, so there is nothing to
    // pop and no optimistic removal to roll back — the row simply stops
    // existing once the refetch lands.
    wtmSnack(context, l10n.giveawayDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final giveaway = widget.giveaway;
    final l10n = AppLocalizations.of(context);
    final cover = giveaway.coverImageUrl;

    // The card and the owner's menu are SIBLINGS, not nested. Nesting the menu
    // inside the card's ExcludeSemantics would hide a destructive action from
    // every screen reader, and inside its GestureDetector every menu tap would
    // also open the detail.
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: giveaway.title,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push(
                    '${AppRoute.wtmGiveawayDetail}?id=${giveaway.id}',
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(WtmRadius.tile),
                          child: WtmDiscoverArtwork(
                            url: cover,
                            seed: giveaway.id,
                            glyph: wtmGarmentGlyph(giveaway.category),
                            decodeWidth: 260,
                            glyphScale: 0.46,
                          ),
                        ),
                      ),
                      const SizedBox(width: WtmSpace.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // A requester's own row leads with THEIR state
                            // (accepted / requested), which is the thing they
                            // came back to check; browse rows keep the
                            // listing's open/closed state.
                            EyebrowLabel(switch (giveaway.myClaimStatus) {
                              'accepted' => l10n.wtmGiveawayAcceptedPill,
                              'requested' => l10n.wtmGiveawayEnteredPill,
                              'declined' ||
                              'not_selected' ||
                              'expired' => l10n.wtmGiveawayNotSelected,
                              _ =>
                                giveaway.isAvailable
                                    ? l10n.wtmGiveawayOpen
                                    : l10n.wtmGiveawayClosed,
                            }),
                            const SizedBox(height: 6),
                            Text(
                              giveaway.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: WtmType.h2.copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              giveaway.ownerName ?? l10n.wtmGiveawayMember,
                              style: WtmType.micro,
                            ),
                            const SizedBox(height: WtmSpace.s6),
                            Text(
                              l10n.wtmGiveawayInterested(giveaway.claimCount),
                              style: WtmType.micro.copyWith(
                                color: WtmColors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Owner-only, so a public card carries no owner chrome at all.
          if (giveaway.isMine)
            WtmIconButton(
              WtmGlyph.dots,
              key: const Key('wtm-giveaway-card-menu'),
              semanticLabel: l10n.giveawayOwnerMenuLabel,
              onTap: _deleting
                  ? null
                  : () => showGiveawayOwnerMenu(
                      context,
                      title: giveaway.title,
                      onDelete: _delete,
                    ),
            ),
        ],
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
  bool _deleting = false;

  void _refreshAll() {
    ref.invalidate(giveawayDetailProvider(widget.id));
    ref.invalidate(giveawayClaimsProvider(widget.id));
    ref.invalidate(giveawayBrowseProvider);
    ref.invalidate(myGiveawaysProvider);
    // The requester's own list changes on every accept/decline/cancel too —
    // leaving it stale is how the two sides end up disagreeing.
    ref.invalidate(requestedGiveawaysProvider);
  }

  Future<void> _request() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(giveawayRepositoryProvider).claim(widget.id);
      await ref.read(analyticsProvider).track(AnalyticsEvents.giveawayClaimed);
      _refreshAll(); // the listing now belongs in "My requests" too
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

  /// Permanently delete the owner's own listing.
  ///
  /// Unlike every other owner action here this is not a status change and there
  /// is no Reopen: the post, its requests, the pickup chat and the public media
  /// go for good. So nothing leaves the client until the server has actually
  /// answered — a failed delete must leave the listing exactly where it was.
  Future<void> _delete() async {
    if (_deleting) return;
    final l10n = AppLocalizations.of(context);
    // Latched BEFORE the dialog, not after it: two fast taps would otherwise
    // open two confirmations and each could send its own DELETE.
    setState(() => _deleting = true);

    final outcome = await confirmAndDeleteGiveaway(context, ref, widget.id);
    if (!mounted) return;
    if (outcome != GiveawayDeleteOutcome.deleted) {
      // Cancel is a true no-op; a failure left the listing exactly where it
      // was and already said so. Either way the action must be usable again.
      setState(() => _deleting = false);
      return;
    }

    // Server confirmed. Only now is it safe to drop the listing.
    _refreshAll();
    // An explicit destination rather than pop(): this detail route now points
    // at a deleted id, and popping can land straight back on it from a deep
    // link or a notification.
    context.go(AppRoute.wtmGiveaways);
    // Shown after navigating — the root ScaffoldMessenger outlives the route,
    // so the confirmation is still on screen once the detail is gone.
    wtmSnack(context, l10n.giveawayDeleted);
  }

  /// The owner's three-dot menu. Same delete, second doorway — an overflow menu
  /// is where people look for a destructive action on a thing they own.
  void _openOwnerMenu(Giveaway g) {
    showGiveawayOwnerMenu(context, title: g.title, onDelete: _delete);
  }

  void _openChat() {
    ref.read(analyticsProvider).track(AnalyticsEvents.giveawayChatOpened);
    context.push('${AppRoute.wtmGiveawayChat}?id=${widget.id}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayDetailProvider(widget.id));
    final chatOn = ref.watch(featureEnabledProvider(FeatureFlags.giveawayChat));
    // Owner-only, and only once the listing has actually loaded — an overflow
    // menu on a screen that might turn out to be someone else's (or a 404) is
    // worse than no menu at all.
    final owned = async.asData?.value;

    return WtmPage(
      title: owned?.title ?? l10n.wtmGiveawaysTitle,
      eyebrow: l10n.wtmDiscover,
      trailing: owned != null && owned.isMine
          ? WtmIconButton(
              WtmGlyph.dots,
              key: const Key('wtm-giveaway-owner-menu'),
              semanticLabel: l10n.giveawayOwnerMenuLabel,
              onTap: _deleting ? null : () => _openOwnerMenu(owned),
            )
          : null,
      children: async.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 180),
        ],
        // A deleted listing is not a failure to recover from. The server says
        // 404 and it will say 404 forever, so offering Retry as the only
        // explanation leaves anyone arriving from an old notification or a
        // shared link tapping a button that can never work. Every OTHER error
        // is still transient and keeps its retry.
        error: (err, _) => [
          if (err is ApiException && err.statusCode == 404)
            WtmEmptyState(
              glyph: WtmGlyph.gift,
              title: l10n.giveawayUnavailable,
              message: l10n.giveawayUnavailableBody,
              ctaLabel: l10n.giveawayBrowseTab,
              onCta: () => context.go(AppRoute.wtmGiveaways),
            )
          else
            WtmErrorState(
              title: l10n.wtmGiveawaysErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(giveawayDetailProvider(widget.id)),
            ),
        ],
        data: (g) {
          return [
            _GiveawayGallery(
              images: g.images,
              seed: g.id,
              glyph: wtmGarmentGlyph(g.category),
            ),
            const SizedBox(height: WtmSpace.s14),
            Text(
              g.title,
              textAlign: TextAlign.center,
              style: WtmType.h2.copyWith(fontSize: 20),
            ),
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
              Text(
                g.description!.trim(),
                style: WtmType.body.copyWith(fontSize: 12.5, height: 1.5),
              ),
            ],
            const SizedBox(height: WtmSpace.s16),
            if (g.isMine)
              _OwnerPanel(
                giveaway: g,
                chatOn: chatOn,
                deleting: _deleting,
                onDecide: _decide,
                onMarkGiven: _markGiven,
                onOpenChat: _openChat,
                onDelete: _delete,
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
            Text(
              l10n.wtmGiveawayRules,
              style: WtmType.micro.copyWith(height: 1.55),
            ),
          ];
        },
      ),
    );
  }
}

/// Every listing photo, in the published order, as a swipeable gallery with a
/// page indicator. A giveaway may carry up to six images; showing only the first
/// made a multi-photo listing look like a single-photo one. The placeholder is
/// used ONLY when the listing genuinely has no image.
class _GiveawayGallery extends StatefulWidget {
  const _GiveawayGallery({
    required this.images,
    required this.seed,
    required this.glyph,
  });

  final List<String> images;

  /// Stable identity for the drawn fallback, so a listing always looks the
  /// same and two listings never come out as copies of each other.
  final String seed;
  final WtmGlyph glyph;

  @override
  State<_GiveawayGallery> createState() => _GiveawayGalleryState();
}

class _GiveawayGalleryState extends State<_GiveawayGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final images = widget.images;
    return SizedBox(
      height: 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WtmRadius.card),
        child: images.isEmpty
            ? WtmDiscoverArtwork(
                url: null,
                seed: widget.seed,
                glyph: widget.glyph,
                glyphScale: 0.42,
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => WtmDiscoverArtwork(
                      url: images[i],
                      // Per IMAGE: a listing whose photos all failed must not
                      // come out as the same drawing swiped three times.
                      seed: '${widget.seed}:$i',
                      glyph: widget.glyph,
                      decodeWidth: 900,
                      glyphScale: 0.42,
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      right: WtmSpace.s10,
                      bottom: WtmSpace.s10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WtmSpace.s8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(WtmRadius.chip),
                        ),
                        child: Text(
                          l10n.giveawayPhotoCount(_page + 1, images.length),
                          style: WtmType.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
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
                icon: const WtmIcon(
                  WtmGlyph.check,
                  size: 12,
                  color: WtmColors.gold,
                ),
              ),
            ),
            // Gated on the SERVER-resolved chat, not just the claim status, so
            // the requester is only offered a conversation that actually exists —
            // and is offered exactly the same one the owner sees.
            if (chatOn && giveaway.hasChat) ...[
              const SizedBox(height: WtmSpace.s12),
              GradientCta(
                label: l10n.wtmGiveawayOpenChat,
                icon: const WtmIcon(
                  WtmGlyph.comment,
                  size: 15,
                  color: WtmColors.ctaText,
                ),
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
                icon: const WtmIcon(
                  WtmGlyph.check,
                  size: 12,
                  color: WtmColors.gold,
                ),
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
          icon: const WtmIcon(
            WtmGlyph.gift,
            size: 15,
            color: WtmColors.ctaText,
          ),
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
    required this.deleting,
    required this.onDecide,
    required this.onMarkGiven,
    required this.onOpenChat,
    required this.onDelete,
  });

  final Giveaway giveaway;
  final bool chatOn;

  /// A delete is in flight (or its confirmation is open) — the action disables
  /// itself so a second tap cannot issue a second DELETE.
  final bool deleting;
  final void Function(GiveawayClaim claim, bool accept) onDecide;
  final VoidCallback onMarkGiven;
  final VoidCallback onOpenChat;
  final VoidCallback onDelete;

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
              icon: const WtmIcon(
                WtmGlyph.check,
                size: 12,
                color: WtmColors.gold,
              ),
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
              final accepted = list
                  .where((c) => c.status == 'accepted')
                  .toList();
              final pending = list
                  .where((c) => c.status == 'requested')
                  .toList();
              if (accepted.isEmpty && pending.isEmpty) {
                return Text(l10n.wtmGiveawayNoRequests, style: WtmType.sub);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in accepted) ...[
                    _AcceptedCard(
                      claim: c,
                      chatOn: chatOn && giveaway.hasChat,
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
        // PERMANENT removal — last in the panel, in danger red, and deliberately
        // NOT grouped with Accept / Decline / Mark as Given. Those are all
        // recoverable; this one destroys the listing and everything hanging off
        // it. Offered on a given-away listing too, so an owner can clear a
        // finished post rather than leaving it in their history forever.
        const SizedBox(height: WtmSpace.s16),
        GhostButton(
          key: const Key('wtm-giveaway-delete'),
          label: l10n.giveawayDelete,
          foregroundColor: WtmColors.danger,
          borderColor: WtmColors.danger,
          onPressed: deleting ? null : onDelete,
        ),
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
          Text(
            claim.claimerName ?? l10n.wtmGiveawayMember,
            style: WtmType.labelMedium,
          ),
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
                icon: const WtmIcon(
                  WtmGlyph.check,
                  size: 12,
                  color: WtmColors.gold,
                ),
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
                    claim.claimerName ?? l10n.wtmGiveawayMember,
                  ),
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
              icon: const WtmIcon(
                WtmGlyph.comment,
                size: 15,
                color: WtmColors.ctaText,
              ),
              onPressed: onOpenChat,
            ),
            const SizedBox(height: WtmSpace.s8),
          ],
          GhostButton(
            label: l10n.wtmGiveawayMarkGiven,
            icon: const WtmIcon(
              WtmGlyph.check,
              size: 15,
              color: WtmColors.gold,
            ),
            foregroundColor: WtmColors.gold,
            onPressed: onMarkGiven,
          ),
        ],
      ),
    );
  }
}
