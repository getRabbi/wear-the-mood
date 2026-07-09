import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../data/models/news_item.dart';
import '../../features/news/news_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Newsroom (board 10, P9) — the fashion feed on [newsProvider]. Tap →
/// the article reader (`?id=`), the Inbox Drops deep-link target for news.
class WtmNewsroomScreen extends ConsumerWidget {
  const WtmNewsroomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(newsProvider);

    return WtmPage(
      title: l10n.wtmNewsTitle,
      eyebrow: l10n.wtmDiscover,
      children: async.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 200),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmNewsErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(newsProvider),
          ),
        ],
        data: (items) => items.isEmpty
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmEmptyState(
                  glyph: WtmGlyph.image,
                  title: l10n.wtmNewsEmptyTitle,
                  message: l10n.wtmNewsEmptyMessage,
                ),
              ]
            : [
                _FeatureCard(item: items.first),
                if (items.length > 1) ...[
                  const SizedBox(height: WtmSpace.s16),
                  EyebrowLabel(l10n.wtmNewsMore),
                  const SizedBox(height: WtmSpace.s10),
                  // Every story is a PICTURE card (mobile QA #1) — thumbnail,
                  // serif title, source and excerpt; never an icon-only row.
                  for (final item in items.skip(1))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _StoryCard(item: item),
                    ),
                ],
              ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: item.title,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => context.push('${AppRoute.wtmArticle}?id=${item.id}'),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 142,
                  width: double.infinity,
                  child: item.imageUrl == null
                      ? const AuroraBox(
                          borderRadius: BorderRadius.zero,
                          border: false,
                          vignette: true)
                      : CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          cacheKey: stableImageCacheKey(item.imageUrl!),
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const AuroraBox(
                              borderRadius: BorderRadius.zero, border: false),
                          errorWidget: (_, _, _) => const AuroraBox(
                              borderRadius: BorderRadius.zero, border: false),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: WtmType.h2.copyWith(fontSize: 19),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      if ((item.summary ?? '').isNotEmpty) ...[
                        const SizedBox(height: WtmSpace.s8),
                        Text(item.summary!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: WtmType.sub),
                      ],
                      const SizedBox(height: WtmSpace.s12),
                      GoldPill(
                        label: l10n.wtmNewsRead,
                        onTap: () => context
                            .push('${AppRoute.wtmArticle}?id=${item.id}'),
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

/// A "More Stories" picture card (mobile QA #1): rounded thumbnail on the
/// left, serif title + source + excerpt on the right — the whole card opens
/// the in-app article reader.
class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: item.title,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('${AppRoute.wtmArticle}?id=${item.id}'),
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s10),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: SizedBox(
                    width: 96,
                    height: 112,
                    child: item.imageUrl == null
                        ? const AuroraBox(
                            borderRadius: BorderRadius.zero,
                            border: false,
                            vignette: true,
                          )
                        : CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            cacheKey: stableImageCacheKey(item.imageUrl!),
                            fit: BoxFit.cover,
                            // Thumbnail-size decode (mobile QA perf).
                            memCacheWidth: 320,
                            placeholder: (_, _) => const AuroraBox(
                              borderRadius: BorderRadius.zero,
                              border: false,
                            ),
                            errorWidget: (_, _, _) => const AuroraBox(
                              borderRadius: BorderRadius.zero,
                              border: false,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.h2.copyWith(fontSize: 15.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.source ?? l10n.wtmArticleEyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.micro.copyWith(color: WtmColors.gold),
                      ),
                      if ((item.summary ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          item.summary!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.micro.copyWith(height: 1.45),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: WtmSpace.s8, top: 4),
                  child: WtmIcon(
                    WtmGlyph.chevron,
                    size: 13,
                    color: WtmColors.faint,
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

/// Article reader (board §3.17, P9) — the story + source + a "read on source"
/// external link, and trend-to-closet matches ([closetMatchesProvider]).
class WtmArticleScreen extends ConsumerWidget {
  const WtmArticleScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(newsProvider).asData?.value ?? const <NewsItem>[];
    NewsItem? item;
    for (final n in items) {
      if (n.id == id) item = n;
    }

    if (item == null) {
      return WtmPage(
        title: l10n.wtmNewsTitle,
        eyebrow: l10n.wtmArticleEyebrow,
        children: [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.image,
            title: l10n.wtmArticleGoneTitle,
            message: l10n.wtmArticleGoneMessage,
            ctaLabel: l10n.wtmNewsTitle,
            onCta: () => context.go(AppRoute.wtmNewsroom),
          ),
        ],
      );
    }

    final a = item;
    final reader = WtmType.h2.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.65,
    );
    final matches = ref.watch(closetMatchesProvider(a.id)).asData?.value ??
        const [];

    return WtmPage(
      title: l10n.wtmNewsTitle,
      eyebrow: l10n.wtmArticleEyebrow,
      children: [
        SizedBox(
          height: 210,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WtmRadius.card),
            child: a.imageUrl == null
                ? const AuroraBox(vignette: true)
                : CachedNetworkImage(
                    imageUrl: a.imageUrl!,
                    cacheKey: stableImageCacheKey(a.imageUrl!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    memCacheWidth: 1080,
                    placeholder: (_, _) => const AuroraBox(vignette: true),
                    errorWidget: (_, _, _) => const AuroraBox(vignette: true),
                  ),
          ),
        ),
        const SizedBox(height: WtmSpace.s14),
        Text(a.title, style: WtmType.h1.copyWith(fontSize: 24)),
        const SizedBox(height: WtmSpace.s6),
        Text(a.source ?? l10n.wtmArticleEyebrow, style: WtmType.micro),
        const SizedBox(height: WtmSpace.s14),
        Text(a.summary ?? l10n.wtmArticleNoSummary, style: reader),
        const SizedBox(height: WtmSpace.s16),
        if ((a.url ?? '').isNotEmpty)
          GhostButton(
            label: l10n.wtmArticleReadOn(a.source ?? 'source'),
            icon: const WtmIcon(WtmGlyph.store, size: 15, color: WtmColors.text),
            onPressed: () => launchUrl(Uri.parse(a.url!),
                mode: LaunchMode.externalApplication),
          ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: WtmSpace.s18),
          EyebrowLabel(l10n.wtmArticleFromCloset),
          const SizedBox(height: WtmSpace.s10),
          Row(
            children: [
              for (final (i, item) in matches.take(4).indexed) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: FabricTile(
                    imageUrl: item.displayImageUrl,
                    swatchIndex: i,
                    fit: BoxFit.contain,
                    radius: 9,
                    semanticLabel: item.title,
                    onTap: () =>
                        context.push(AppRoute.wtmClosetItem, extra: item),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
