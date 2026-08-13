import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wtm_article_web_screen.dart';
import 'wtm_discover_artwork.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/utils/in_app_link_policy.dart';
import '../../data/models/news_item.dart';
import '../../features/news/news_providers.dart';
import '../../l10n/app_localizations.dart';
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
                  child: WtmDiscoverArtwork(
                    url: item.imageUrl,
                    seed: item.id,
                    // A read, not a garment.
                    glyph: WtmGlyph.bookmark,
                    decodeWidth: 900,
                    glyphScale: 0.30,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: WtmType.h2.copyWith(fontSize: 19),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((item.summary ?? '').isNotEmpty) ...[
                        const SizedBox(height: WtmSpace.s8),
                        Text(
                          item.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.sub,
                        ),
                      ],
                      const SizedBox(height: WtmSpace.s12),
                      GoldPill(
                        label: l10n.wtmNewsRead,
                        onTap: () => context.push(
                          '${AppRoute.wtmArticle}?id=${item.id}',
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
                    child: WtmDiscoverArtwork(
                      url: item.imageUrl,
                      seed: item.id,
                      glyph: WtmGlyph.bookmark,
                      // Thumbnail-size decode (mobile QA perf).
                      decodeWidth: 320,
                      glyphScale: 0.40,
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

/// Article reader (board §3.17, P9) — the story + source + "read on source",
/// and trend-to-closet matches ([closetMatchesProvider]).
///
/// The story is resolved through [newsItemProvider], which prefers the already
/// loaded feed and falls back to a single fetch-by-id. That fallback is what
/// makes a push notification or a shared link work after a cold start: the
/// screen used to read the in-memory feed only, so an article opened before the
/// feed had loaded reported itself gone.
class WtmArticleScreen extends ConsumerWidget {
  const WtmArticleScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Widget gone() => WtmEmptyState(
      glyph: WtmGlyph.image,
      title: l10n.wtmArticleGoneTitle,
      message: l10n.wtmArticleGoneMessage,
      ctaLabel: l10n.wtmNewsTitle,
      onCta: () => context.go(AppRoute.wtmNewsroom),
    );

    return ref
        .watch(newsItemProvider(id))
        .when(
          skipLoadingOnReload: true,
          loading: () => WtmPage(
            title: l10n.wtmNewsTitle,
            eyebrow: l10n.wtmArticleEyebrow,
            children: const [
              LoadingShimmer(width: double.infinity, height: 210),
              SizedBox(height: WtmSpace.s14),
              LoadingShimmer(width: double.infinity, height: 96),
            ],
          ),
          // A 404 is permanent — the story really is gone, and offering Retry
          // would be a button that can never work. Everything else is transient.
          error: (err, _) => WtmPage(
            title: l10n.wtmNewsTitle,
            eyebrow: l10n.wtmArticleEyebrow,
            children: [
              const SizedBox(height: WtmSpace.s22),
              if (err is ApiException && err.statusCode == 404)
                gone()
              else
                WtmErrorState(
                  title: l10n.wtmNewsErrorTitle,
                  message: l10n.errorGenericTitle,
                  retryLabel: l10n.commonRetry,
                  onRetry: () => ref.invalidate(newsItemProvider(id)),
                ),
            ],
          ),
          data: (item) => _ArticleBody(item: item),
        );
  }
}

class _ArticleBody extends ConsumerWidget {
  const _ArticleBody({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final a = item;
    final reader = WtmType.h2.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.65,
    );
    final matches =
        ref.watch(closetMatchesProvider(a.id)).asData?.value ?? const [];

    return WtmPage(
      title: l10n.wtmNewsTitle,
      eyebrow: l10n.wtmArticleEyebrow,
      children: [
        SizedBox(
          height: 210,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WtmRadius.card),
            child: WtmDiscoverArtwork(
              url: a.imageUrl,
              seed: a.id,
              glyph: WtmGlyph.bookmark,
              decodeWidth: 1080,
              glyphScale: 0.30,
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
            key: const Key('wtm-article-read-on'),
            label: l10n.wtmArticleReadOn(a.source ?? 'source'),
            icon: const WtmIcon(
              WtmGlyph.bookmark,
              size: 15,
              color: WtmColors.text,
            ),
            // INSIDE the app. This used to hand the URL to the external
            // launcher, which put every reader in Chrome or Safari and ended
            // the session. The same audited https-only check still gates it —
            // it now decides whether the in-app reader will open the link at
            // all, rather than which browser gets it.
            onPressed: () {
              final decision = decideInAppLink(a.url!);
              if (decision.action != InAppLinkAction.loadInApp ||
                  decision.url == null) {
                // Scoped to this article screen — the refusal is about THIS
                // story's link, and following the user out of it would put the
                // message over whatever they opened next.
                wtmSnack(
                  context,
                  l10n.wtmArticleLinkBlocked,
                  dismissOnPop: true,
                );
                return;
              }
              context.push(
                AppRoute.wtmArticleWeb,
                // The normalized URL, so a cleartext feed link opens over TLS
                // rather than being refused at the reader's own door.
                extra: WtmArticleWebArgs(
                  url: decision.url!,
                  title: a.title,
                  source: a.source,
                ),
              );
            },
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
                    imageUrl: item.cardImageUrl,
                    isCutout: item.displaysCutout,
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
