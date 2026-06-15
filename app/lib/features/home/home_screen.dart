import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/post.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../credits/credits_chip.dart';
import '../credits/credits_sheet.dart';
import '../paywall/billing_providers.dart';
import '../shell/shell_providers.dart';
import '../social/social_providers.dart';
import '../tryon/sample_garments.dart';
import '../wardrobe/wardrobe_providers.dart';

/// The daily landing — an AI fashion dashboard (CLAUDE.md §1, §17). Leads with
/// the try-on hook, then the day's actions, the closet, AI suggestions and what's
/// trending — so the surface never feels empty. Pull-to-refresh re-syncs the
/// closet, feed, credits and profile.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _goTryOn(WidgetRef ref) =>
      ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(wardrobeItemsProvider);
            ref.invalidate(creditsProvider);
            ref.invalidate(profileProvider);
            await ref.read(feedProvider.notifier).refresh();
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.screenH,
              AppSpace.md,
              AppSpace.screenH,
              bottomNavClearance(context),
            ),
            children: [
              const _Header(),
              const SizedBox(height: AppSpace.lg),
              _FadeInUp(
                child: _TryOnHero(
                  onStart: () => _goTryOn(ref),
                  onUpload: () => context.push(AppRoute.wardrobeAdd),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(l10n.homeQuickActions,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.md),
              _QuickActions(onTryOn: () => _goTryOn(ref)),
              const SizedBox(height: AppSpace.xl),
              SectionHeader(
                title: l10n.homeClosetTitle,
                subtitle: _closetSubtitle(context, ref),
                actionLabel: l10n.homeSeeAll,
                onAction: () =>
                    ref.read(shellTabProvider.notifier).select(ShellTabs.closet),
              ),
              const SizedBox(height: AppSpace.md),
              _ClosetPreview(
                onOpenCloset: () =>
                    ref.read(shellTabProvider.notifier).select(ShellTabs.closet),
                onAdd: () => context.push(AppRoute.wardrobeAdd),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(l10n.homeSuggestionsTitle,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.md),
              const _AiSuggestions(),
              const SizedBox(height: AppSpace.xl),
              _TrendingLooks(onTryOn: () => _goTryOn(ref)),
            ],
          ),
        ),
      ),
    );
  }

  String? _closetSubtitle(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(wardrobeItemsProvider).asData?.value.length;
    if (count == null) return null;
    return l10n.homeClosetItemsCount(count);
  }
}

// ─────────────────────────────────────────────────────────── Header ──────────

class _Header extends ConsumerWidget {
  const _Header();

  String _hello(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 12) return l10n.homeHelloMorning;
    if (h < 17) return l10n.homeHelloAfternoon;
    return l10n.homeHelloEvening;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final signedIn = ref.watch(signedInEmailProvider) != null;
    final name = signedIn
        ? ref.watch(profileProvider).asData?.value.displayName
        : null;

    final hasName = name != null && name.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Responsive greeting: hello on one line, name on its own so it
              // never gets cut by the header actions (spec).
              if (hasName) ...[
                Text(
                  '${_hello(l10n)},',
                  style: text.bodyMedium?.copyWith(color: AppColors.graphite),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  name.trim(),
                  style: text.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else
                Text(
                  _hello(l10n),
                  style: text.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 14, color: AppColors.lavender),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      l10n.homeStylistReady,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CreditsChip(onTap: () => showCreditsSheet(context)),
              _RoundIcon(
                icon: Icons.notifications_none_rounded,
                onTap: () => context.push(AppRoute.notifications),
              ),
              _CrownButton(onTap: () => context.push(AppRoute.paywall)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppColors.ink),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CrownButton extends ConsumerWidget {
  const _CrownButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(isPremiumProvider);
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        premium
            ? Icons.workspace_premium_rounded
            : Icons.workspace_premium_outlined,
        color: premium ? AppColors.warn : AppColors.violet,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Hero ────────────

/// Editorial AI try-on hero — a swipeable carousel of full-body looks with a
/// dark scrim + the primary "Start Try-On" CTA and a secondary "Upload clothing".
class _TryOnHero extends StatefulWidget {
  const _TryOnHero({required this.onStart, required this.onUpload});

  final VoidCallback onStart;
  final VoidCallback onUpload;

  @override
  State<_TryOnHero> createState() => _TryOnHeroState();
}

class _TryOnHeroState extends State<_TryOnHero> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final looks = sampleLookImageUrls;

    return Semantics(
      button: true,
      label: l10n.homeHeroTitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadow.premiumGlow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Cap the hero so it never dominates short / small screens (spec).
              final h = (constraints.maxWidth * 1.2).clamp(
                0.0,
                MediaQuery.of(context).size.height * 0.46,
              );
              return SizedBox(
                height: h,
                child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: looks.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: looks[i],
                    fit: BoxFit.cover,
                    fadeInDuration: AppMotion.base,
                    placeholder: (_, _) => const LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.mist),
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: AppGradients.imageScrim),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < looks.length; i++)
                            AnimatedContainer(
                              duration: AppMotion.fast,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _index ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _index
                                    ? Colors.white
                                    : Colors.white54,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppGradients.brand,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              l10n.tryOnBadgeFree.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        l10n.homeHeroTitle,
                        style: text.headlineSmall?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        l10n.homeHeroSubtitle,
                        style: text.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: AppSpace.md),
                      PrimaryButton(
                        label: l10n.homeHeroCta,
                        icon: Icons.auto_awesome,
                        onPressed: widget.onStart,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SecondaryButton(
                        label: l10n.homeHeroUpload,
                        icon: Icons.add_a_photo_outlined,
                        onDark: true,
                        onPressed: widget.onUpload,
                      ),
                    ],
                  ),
                ),
              ],
            ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── Quick actions ───────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTryOn});

  final VoidCallback onTryOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = [
      QuickActionCard(
        icon: Icons.auto_awesome,
        title: l10n.homeQaTryOnTitle,
        subtitle: l10n.homeQaTryOnSub,
        tint: AppColors.accent,
        onTap: onTryOn,
      ),
      QuickActionCard(
        icon: Icons.style_outlined,
        title: l10n.homeQaOutfitTitle,
        subtitle: l10n.homeQaOutfitSub,
        tint: AppColors.violet,
        onTap: () => context.push(AppRoute.outfitsCreate),
      ),
      QuickActionCard(
        icon: Icons.wb_sunny_outlined,
        title: l10n.homeQaStylistTitle,
        subtitle: l10n.homeQaStylistSub,
        tint: AppColors.warn,
        onTap: () => context.push(AppRoute.stylist),
      ),
      QuickActionCard(
        icon: Icons.luggage_outlined,
        title: l10n.homeQaPackTitle,
        subtitle: l10n.homeQaPackSub,
        tint: AppColors.success,
        onTap: () => context.push(AppRoute.packing),
      ),
    ];

    // Fixed-height rows (not aspect-ratio) so cards never overflow on small or
    // large screens regardless of text length / font metrics.
    SizedBox cell(Widget c) => SizedBox(height: 126, child: c);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cell(cards[0])),
            const SizedBox(width: AppSpace.md),
            Expanded(child: cell(cards[1])),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(child: cell(cards[2])),
            const SizedBox(width: AppSpace.md),
            Expanded(child: cell(cards[3])),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────── Closet preview ──────────

class _ClosetPreview extends ConsumerWidget {
  const _ClosetPreview({required this.onOpenCloset, required this.onAdd});

  final VoidCallback onOpenCloset;
  final VoidCallback onAdd;

  static const _height = 168.0;
  static const _itemWidth = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider);

    return items.when(
      loading: () => SkeletonLoader.rowTiles(height: _height, width: _itemWidth),
      error: (_, _) => _BuildClosetCard(onAdd: onAdd),
      data: (list) => list.isEmpty
          ? _BuildClosetCard(onAdd: onAdd)
          : SizedBox(
              height: _height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length > 10 ? 10 : list.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
                itemBuilder: (context, i) => SizedBox(
                  width: _itemWidth,
                  child: _ClosetThumb(item: list[i], onTap: onOpenCloset),
                ),
              ),
            ),
    );
  }
}

class _ClosetThumb extends ConsumerWidget {
  const _ClosetThumb({required this.item, required this.onTap});

  final WardrobeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(closetFavoritesProvider).contains(item.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SmartImageCard(
            imageUrl: item.displayImageUrl ?? '',
            aspectRatio: 1,
            fit: BoxFit.contain,
            padded: true,
            onTap: onTap,
            overlay: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: _HeartButton(
                  active: fav,
                  onTap: () =>
                      ref.read(closetFavoritesProvider.notifier).toggle(item.id),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          item.title ?? AppLocalizations.of(context).closetUncategorized,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: AppShadow.soft,
        ),
        child: Icon(
          active ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: active ? AppColors.accent : AppColors.graphite,
        ),
      ),
    );
  }
}

class _BuildClosetCard extends StatelessWidget {
  const _BuildClosetCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onAdd,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.checkroom_rounded,
                color: AppColors.accent, size: 28),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.homeBuildClosetTitle, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(l10n.homeBuildClosetSub, style: text.bodySmall),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      l10n.homeAddFirstItem,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── AI suggestions ──────────

class _AiSuggestions extends ConsumerWidget {
  const _AiSuggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];

    final suggestions = <String>[];
    if (items.isEmpty) {
      suggestions.add(l10n.homeSuggestionStartCloset);
    } else {
      final cats =
          items.map((i) => (i.category ?? '').toLowerCase()).toSet();
      final hasBottoms =
          cats.any((c) => c.contains('bottom') || c.contains('pant') || c.contains('jean') || c.contains('skirt'));
      final hasShoes = cats.any((c) => c.contains('shoe') || c.contains('sneaker') || c.contains('boot'));
      suggestions.add(l10n.homeSuggestionStyleTop);
      if (!hasShoes) suggestions.add(l10n.homeSuggestionAddShoes);
      if (!hasBottoms) suggestions.add(l10n.homeSuggestionNeedBottoms);
    }

    return Column(
      children: [
        for (final s in suggestions.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _SuggestionCard(text: s),
          ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadow.soft,
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.auto_awesome, size: 17, color: Colors.white),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── Trending looks ──────────

class _TrendingLooks extends ConsumerWidget {
  const _TrendingLooks({required this.onTryOn});

  final VoidCallback onTryOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(feedProvider);

    return feed.maybeWhen(
      data: (posts) {
        final looks = posts
            .where((p) => (p.imageUrl ?? '').isNotEmpty)
            .take(8)
            .toList();
        if (looks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: l10n.homeTrendingTitle, subtitle: l10n.homeTrendingSub),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: looks.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
                itemBuilder: (_, i) => SizedBox(
                  width: 168,
                  child: _TrendingCard(post: looks[i], onTryOn: onTryOn),
                ),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  const _TrendingCard({required this.post, required this.onTryOn});

  final Post post;
  final VoidCallback onTryOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SmartImageCard(
      imageUrl: post.imageUrl ?? '',
      aspectRatio: 168 / 230,
      onTap: onTryOn,
      overlay: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppGradients.imageScrim),
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.authorName ?? l10n.socialSomeone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.favorite, size: 12, color: Colors.white70),
                  const SizedBox(width: 3),
                  Text(
                    '${post.likeCount}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const Spacer(),
                  const Icon(Icons.auto_awesome, size: 13, color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Motion ──────────

/// A gentle fade + rise entrance for hero content (CLAUDE.md §4 motion).
class _FadeInUp extends StatelessWidget {
  const _FadeInUp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.easing,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
      ),
      child: child,
    );
  }
}
