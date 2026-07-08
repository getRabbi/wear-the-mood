import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/flags/feature_flags.dart';
import '../../core/router/routes.dart';
import '../../data/models/post.dart';
import '../../features/social/social_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_community_shared.dart';

/// WTM Community feed (board 07, P8) — the OOTD feed on the real
/// [feedProvider]. Gated behind the `community` flag (§6): OFF → an honest
/// "coming soon" state so the tab is never a dead end. Post cards carry the
/// real like/comment/bookmark actions and the ⋯ → report/block sheet.
class WtmSocialScreen extends ConsumerStatefulWidget {
  const WtmSocialScreen({super.key});

  @override
  ConsumerState<WtmSocialScreen> createState() => _WtmSocialScreenState();
}

class _WtmSocialScreenState extends ConsumerState<WtmSocialScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(featureEnabledProvider(FeatureFlags.community));

    return SafeArea(
      bottom: false,
      // Pull-to-refresh re-fetches the feed AND the feature flags, so a fresh
      // post — or a just-enabled community flag — lands without an app restart
      // (mobile QA: feed must reflect new posts immediately).
      child: RefreshIndicator(
        color: WtmColors.gold,
        backgroundColor: WtmColors.panel,
        onRefresh: () async {
          ref.invalidate(enabledFeatureFlagsProvider);
          await ref.read(feedProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            wtmNavClearance,
          ),
          children: [
            Row(
              children: [
                Text(l10n.wtmSocialTitle, style: WtmType.h1),
                const Spacer(),
                if (enabled) ...[
                  WtmIconButton(
                    WtmGlyph.search,
                    semanticLabel: l10n.wtmSocialSearch,
                    onTap: () =>
                        context.push('${AppRoute.wtmSearch}?scope=community'),
                  ),
                  const SizedBox(width: WtmSpace.s6),
                ],
                // Create Post is ALWAYS available — even while the community feed
                // is in preview — so the tab is never a dead end. Routes to the
                // real WTM compose flow (Looks/Closet → caption → tags → publish).
                WtmIconButton(
                  WtmGlyph.plus,
                  semanticLabel: l10n.wtmSocialShare,
                  onTap: () => context.push(AppRoute.wtmCompose),
                ),
              ],
            ),
            if (!enabled)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: WtmEmptyState(
                  glyph: WtmGlyph.users,
                  title: l10n.wtmSocialComingTitle,
                  message: l10n.wtmSocialComingMessage,
                  ctaLabel: l10n.wtmSocialShare,
                  onCta: () => context.push(AppRoute.wtmCompose),
                ),
              )
            else ...[
              const SizedBox(height: WtmSpace.s14),
              WtmChipRow(
                children: [
                  for (final (i, label) in [
                    l10n.wtmSocialForYou,
                    l10n.wtmSocialFollowing,
                    l10n.wtmSocialNew,
                    l10n.wtmSocialNearYou,
                  ].indexed)
                    WtmChip(
                      label: label,
                      on: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                ],
              ),
              if (_tab == 3) ...[
                const SizedBox(height: WtmSpace.s6),
                Text(l10n.wtmSocialNearYouNote, style: WtmType.micro),
              ],
              const SizedBox(height: WtmSpace.s14),
              ..._feed(context, l10n),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _feed(BuildContext context, AppLocalizations l10n) {
    return ref
        .watch(feedProvider)
        .when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(height: WtmSpace.s10),
              const LoadingShimmer(
                width: double.infinity,
                height: 220,
                borderRadius: BorderRadius.all(Radius.circular(WtmRadius.card)),
              ),
            ],
          ],
          error: (_, _) => [
            WtmErrorState(
              title: l10n.wtmSocialErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.read(feedProvider.notifier).refresh(),
            ),
          ],
          data: (posts) => posts.isEmpty
              ? [
                  const SizedBox(height: WtmSpace.s22),
                  WtmEmptyState(
                    glyph: WtmGlyph.image,
                    title: l10n.wtmSocialEmptyTitle,
                    message: l10n.wtmSocialEmptyMessage,
                    ctaLabel: l10n.wtmSocialShare,
                    onCta: () => context.push(AppRoute.wtmCompose),
                  ),
                ]
              : [
                  for (final (i, post) in posts.indexed) ...[
                    if (i > 0) const SizedBox(height: WtmSpace.s10),
                    WtmPostCard(post: post),
                  ],
                ],
        );
  }
}

/// A community post card — reused by the feed. Author → public profile, image /
/// comment → post detail, like/bookmark toggles, ⋯ → report/block.
class WtmPostCard extends ConsumerWidget {
  const WtmPostCard({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(wtmSavedPostsProvider).contains(post.id);
    final image = post.thumbnailUrl ?? post.imageUrl;

    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: post.authorName ?? l10n.wtmSocialSomeone,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          context.push('${AppRoute.wtmUser}?u=${post.userId}'),
                      child: Row(
                        children: [
                          WtmAvatar(post.authorName),
                          const SizedBox(width: WtmSpace.s10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post.authorName ?? l10n.wtmSocialSomeone,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WtmType.labelMedium,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  wtmPostTime(l10n, post.createdAt),
                                  style: WtmType.micro,
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
              WtmIconButton(
                WtmGlyph.dots,
                semanticLabel: l10n.wtmSocialPostOptions,
                onTap: () => showWtmReportBlockSheet(
                  context,
                  ref,
                  subjectType: 'post',
                  subjectId: post.id,
                  userId: post.userId,
                  onBlocked: () =>
                      ref.read(feedProvider.notifier).removeLocally(post.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          // Media only when the post has some — text-only and poll posts render
          // their content directly instead of a blank gradient block.
          if (image != null) ...[
            GestureDetector(
              onTap: () => context.push(AppRoute.wtmPost, extra: post),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WtmRadius.tile),
                child: CachedNetworkImage(
                  imageUrl: image,
                  cacheKey: stableImageCacheKey(image),
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // Decode at feed-card size, not full-res (mobile QA #1).
                  memCacheWidth: 900,
                  placeholder: (_, _) =>
                      const AuroraBox(height: 220, vignette: true),
                  errorWidget: (_, _, _) =>
                      const AuroraBox(height: 220, vignette: true),
                ),
              ),
            ),
            const SizedBox(height: WtmSpace.s10),
          ],
          // Text-only post: the caption IS the content — serif, roomy, up top.
          if (image == null && (post.caption ?? '').trim().isNotEmpty) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push(AppRoute.wtmPost, extra: post),
              child: Text(
                post.caption!.trim(),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: WtmType.h2.copyWith(fontSize: 16, height: 1.45),
              ),
            ),
            const SizedBox(height: WtmSpace.s10),
          ],
          if (post.poll != null) ...[
            WtmPollView(poll: post.poll!),
            const SizedBox(height: WtmSpace.s10),
          ],
          Row(
            children: [
              _Action(
                glyph: WtmGlyph.heart,
                label: '${post.likeCount}',
                on: post.likedByMe,
                onTap: () => ref.read(feedProvider.notifier).toggleLike(post),
              ),
              const SizedBox(width: WtmSpace.s14),
              _Action(
                glyph: WtmGlyph.comment,
                label: '${post.commentCount}',
                onTap: () => context.push(AppRoute.wtmPost, extra: post),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: l10n.wtmSocialSave,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(wtmSavedPostsProvider.notifier)
                        .toggle(post.id),
                    child: WtmIcon(
                      WtmGlyph.bookmark,
                      size: 15,
                      color: saved ? WtmColors.gold : WtmColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Caption under the actions — only when it wasn't already the hero
          // content above (text-only posts).
          if (image != null && (post.caption ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: WtmSpace.s8),
            Text(
              post.caption!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WtmType.body.copyWith(fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.on = false,
  });

  final WtmGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final color = on ? WtmColors.gold : WtmColors.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          WtmIcon(glyph, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: WtmType.chip.copyWith(color: color)),
        ],
      ),
    );
  }
}
