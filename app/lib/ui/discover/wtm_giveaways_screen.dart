import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// Giveaway detail (board §3.17, P9) — hero, prize, status, Enter Now → claim
/// (real endpoint) → entered pill, and the rules. Reached with `?id=`.
class WtmGiveawayDetailScreen extends ConsumerStatefulWidget {
  const WtmGiveawayDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<WtmGiveawayDetailScreen> createState() =>
      _WtmGiveawayDetailScreenState();
}

class _WtmGiveawayDetailScreenState
    extends ConsumerState<WtmGiveawayDetailScreen> {
  bool _justEntered = false;
  bool _busy = false;

  Future<void> _enter() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(giveawayRepositoryProvider).claim(widget.id);
      ref.invalidate(giveawayDetailProvider(widget.id));
      if (mounted) {
        setState(() => _justEntered = true);
        wtmSnack(context, l10n.wtmGiveawayEntered);
      }
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmGiveawaysErrorTitle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayDetailProvider(widget.id));

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
          final entered = g.hasClaimed || _justEntered;
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
            if (entered)
              const Center(child: _EnteredPill())
            else if (!g.isAvailable)
              Center(child: Text(l10n.wtmGiveawayClosed, style: WtmType.micro))
            else
              GradientCta(
                label: l10n.wtmGiveawayEnter,
                icon: const WtmIcon(WtmGlyph.gift,
                    size: 15, color: WtmColors.ctaText),
                onPressed: _busy ? null : _enter,
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

class _EnteredPill extends StatelessWidget {
  const _EnteredPill();

  @override
  Widget build(BuildContext context) {
    return GoldPill(
      label: AppLocalizations.of(context).wtmGiveawayEnteredPill,
      icon: const WtmIcon(WtmGlyph.check, size: 12, color: WtmColors.gold),
    );
  }
}
