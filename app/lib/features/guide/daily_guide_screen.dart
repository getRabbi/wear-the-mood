import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/daily_guide.dart';
import '../../shared/widgets/widgets.dart';
import '../shell/shell_providers.dart';

/// The full daily guide (FEATURES_COMMUNITY_PLUS · Daily Guide): hero, body,
/// topics, and CTAs that reuse existing actions (try-on, closet, add piece…).
class DailyGuideScreen extends ConsumerStatefulWidget {
  const DailyGuideScreen({super.key, required this.guide});

  final DailyGuide guide;

  @override
  ConsumerState<DailyGuideScreen> createState() => _DailyGuideScreenState();
}

class _DailyGuideScreenState extends ConsumerState<DailyGuideScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.dailyGuideOpened);
  }

  void _onCta(GuideCta cta) {
    ref.read(analyticsProvider).track(AnalyticsEvents.dailyGuideCtaClicked);
    switch (cta.action) {
      case 'tryon':
        ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
        context.pop();
      case 'closet':
        ref.read(shellTabProvider.notifier).select(ShellTabs.closet);
        context.pop();
      case 'wardrobe_add':
        context.push(AppRoute.wardrobeAdd);
      case 'news':
        context.push(AppRoute.news);
      default:
        context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.guide;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _GuideHero(imageUrl: guide.imageUrl, title: guide.title),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (guide.topics.isNotEmpty) ...[
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        for (final t in guide.topics)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.md,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              t,
                              style: text.bodySmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  if (guide.summary != null && guide.summary!.isNotEmpty) ...[
                    Text(guide.summary!, style: text.titleMedium),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (guide.body != null && guide.body!.isNotEmpty)
                    Text(
                      guide.body!,
                      style: text.bodyMedium?.copyWith(height: 1.6),
                    ),
                  if (guide.cta.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xl),
                    for (final cta in guide.cta) ...[
                      GhostButton(
                        label: cta.label,
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => _onCta(cta),
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The guide hero: the image with a serif title overlay, or a branded gradient
/// when there's no image.
class _GuideHero extends StatelessWidget {
  const _GuideHero({required this.imageUrl, required this.title});

  final String? imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const _GuideCoverFallback(),
            )
          else
            // No backend image: the curated editorial cover when available,
            // else the branded gradient (no regression).
            const _GuideCoverFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC15102A)],
              ),
            ),
          ),
          Positioned(
            left: AppSpace.lg,
            right: AppSpace.lg,
            bottom: AppSpace.lg,
            child: Text(
              title,
              style: text.displaySmall?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// The guide hero backdrop when the backend supplies no image: the curated
/// editorial cover (CATEGORY_COVER_IMAGES.md) over the branded gradient.
class _GuideCoverFallback extends StatelessWidget {
  const _GuideCoverFallback();

  @override
  Widget build(BuildContext context) {
    return CoverImage(
      coverKey: 'today_layering',
      fit: BoxFit.cover,
      fallback: (_) => const DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.brand),
      ),
    );
  }
}
