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

/// Daily landing — the surface the user opens to decide what to wear
/// (CLAUDE.md §1). For now it leads with the try-on hook; wardrobe/stylist
/// surfaces slot in as later phases land.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l10n.appTitle, style: text.displaySmall),
                    ),
                    const CreditsChip(),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              sliver: SliverToBoxAdapter(
                child: _TryOnHeroCard(
                  title: l10n.homeTryOnTitle,
                  subtitle: l10n.homeTryOnSubtitle,
                  cta: l10n.homeStartTryOn,
                  onTap: () => context.push(AppRoute.tryon),
                ),
              ),
            ),
          ],
        ),
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
