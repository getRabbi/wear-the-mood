import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../credits/credits_chip.dart';
import '../tryon/sample_garments.dart';
import '../wardrobe/wardrobe_providers.dart';

/// Daily landing — the surface the user opens to decide what to wear
/// (CLAUDE.md §1). Leads with the try-on hook, then previews the closet and
/// teases the daily stylist (its backend lands in a later phase).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.appTitle, style: text.displaySmall)),
                const CreditsChip(),
                IconButton(
                  onPressed: () => context.push(AppRoute.profile),
                  icon: const Icon(Icons.person_outline_rounded),
                  tooltip: l10n.profileTitle,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            _TryOnHeroCard(
              title: l10n.homeTryOnTitle,
              subtitle: l10n.homeTryOnSubtitle,
              cta: l10n.homeStartTryOn,
              onTap: () => context.push(AppRoute.tryon),
            ),
            const SizedBox(height: AppSpace.xl),
            _SectionHeader(
              title: l10n.homeClosetTitle,
              actionLabel: l10n.homeSeeAll,
              onAction: () => context.push(AppRoute.wardrobe),
            ),
            const SizedBox(height: AppSpace.md),
            _ClosetPreview(onOpen: () => context.push(AppRoute.wardrobe)),
            const SizedBox(height: AppSpace.xl),
            _StylistTeaser(
              title: l10n.homeStylistTitle,
              subtitle: l10n.homeStylistSubtitle,
              comingSoon: l10n.homeComingSoon,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _ClosetPreview extends ConsumerWidget {
  const _ClosetPreview({required this.onOpen});

  final VoidCallback onOpen;

  static const _height = 150.0;
  static const _itemWidth = 112.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(wardrobeItemsProvider);

    return SizedBox(
      height: _height,
      child: items.when(
        loading: () => _row(
          6,
          (_) => LoadingShimmer(
            width: _itemWidth,
            height: _height,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        error: (_, _) => _Hint(l10n.homeClosetEmpty),
        data: (list) => list.isEmpty
            ? _Hint(l10n.homeClosetEmpty)
            : _row(list.length, (i) {
                final url = list[i].displayImageUrl ?? '';
                return _ClosetThumb(imageUrl: url, onTap: onOpen);
              }),
      ),
    );
  }

  Widget _row(int count, Widget Function(int) builder) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
      itemBuilder: (context, i) =>
          SizedBox(width: _itemWidth, child: builder(i)),
    );
  }
}

class _ClosetThumb extends StatelessWidget {
  const _ClosetThumb({required this.imageUrl, required this.onTap});

  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fadeInDuration: AppMotion.base,
          placeholder: (_, _) => const LoadingShimmer(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
          errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _StylistTeaser extends StatelessWidget {
  const _StylistTeaser({
    required this.title,
    required this.subtitle,
    required this.comingSoon,
  });

  final String title;
  final String subtitle;
  final String comingSoon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.accent,
            size: 28,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: AppSpace.xs),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AppChip(label: comingSoon),
        ],
      ),
    );
  }
}

class _TryOnHeroCard extends StatelessWidget {
  const _TryOnHeroCard({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: samplePersonImageUrl,
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
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: AppSpace.md),
                      PrimaryButton(
                        label: cta,
                        icon: Icons.auto_awesome,
                        onPressed: onTap,
                      ),
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
