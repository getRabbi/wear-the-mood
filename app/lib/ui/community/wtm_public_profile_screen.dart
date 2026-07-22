import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/social_repository.dart';
import '../../features/social/public_profile_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../profile/wtm_profile_photo.dart' show showWtmProfilePhotoViewer;
import '../widgets/widgets.dart';
import 'wtm_community_shared.dart';

enum WtmFollowListMode { followers, following }

/// Optimistic follow toggle shared by the public profile + follow lists.
Future<void> _toggleFollow(
    BuildContext context, WidgetRef ref, String userId) async {
  try {
    await ref
        .read(followStoreProvider.notifier)
        .toggle(userId, ref.read(socialRepositoryProvider));
  } catch (_) {
    if (context.mounted) {
      wtmSnack(context, AppLocalizations.of(context).wtmFollowError);
    }
  }
}

/// A gold Follow / Following pill bound to the [followStoreProvider].
class WtmFollowPill extends ConsumerWidget {
  const WtmFollowPill({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final following = ref.watch(followStoreProvider).contains(userId);
    return GoldPill(
      label: following ? l10n.wtmFollowing : l10n.wtmFollow,
      icon: WtmIcon(following ? WtmGlyph.check : WtmGlyph.plus,
          size: 12, color: WtmColors.gold),
      onTap: () => _toggleFollow(context, ref, userId),
    );
  }
}

/// WTM Public profile (board §3.13, P8) — another user's profile on
/// [publicProfileProvider] + [userPostsProvider], with a real Follow pill and
/// the ⋯ → report/block sheet. Reached via `/wtm/user?u=<userId>`.
class WtmPublicProfileScreen extends ConsumerWidget {
  const WtmPublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(publicProfileProvider(userId));

    // Fold server follow-truth into the store once it loads.
    ref.listen(publicProfileProvider(userId), (_, next) {
      final p = next.asData?.value;
      if (p != null) {
        ref
            .read(followStoreProvider.notifier)
            .seedOnce(userId, following: p.isFollowing);
      }
    });

    return WtmPage(
      title: profileAsync.asData?.value.displayName ?? l10n.wtmUserTitle,
      eyebrow: l10n.wtmSocialTitle,
      trailing: WtmIconButton(
        WtmGlyph.dots,
        semanticLabel: l10n.wtmUserOptions,
        onTap: () => showWtmReportBlockSheet(
          context,
          ref,
          subjectType: 'user',
          subjectId: userId,
          userId: userId,
          onBlocked: () => wtmPageBack(context),
        ),
      ),
      children: profileAsync.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          Center(
            child: Padding(
              padding: EdgeInsets.only(top: 40),
              child: LoadingShimmer(width: 160, height: 22),
            ),
          ),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmUserErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(publicProfileProvider(userId)),
          ),
        ],
        data: (p) => _content(context, ref, l10n, p),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    PublicProfile p,
  ) {
    final postsAsync = ref.watch(userPostsProvider(userId));
    final avatarUrl = p.avatarUrl;
    return [
      // The creator's real photo when they have one — tap to view it full
      // screen (mobile QA #4); the monogram fallback otherwise.
      Center(
        child: Semantics(
          button: avatarUrl != null,
          label: l10n.wtmProfilePhotoView,
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: avatarUrl == null
                  ? null
                  : () =>
                      showWtmProfilePhotoViewer(context, ref, url: avatarUrl),
              child: WtmAvatar(p.displayName, size: 76, imageUrl: avatarUrl),
            ),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s12),
      if (!p.isMe) Center(child: WtmFollowPill(userId: userId)),
      if ((p.bio ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: WtmSpace.s12),
        Text(p.bio!.trim(), textAlign: TextAlign.center, style: WtmType.sub),
      ],
      const SizedBox(height: WtmSpace.s16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        decoration: BoxDecoration(
          gradient: WtmGradients.cardFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: Row(
          children: [
            _Stat('${p.followerCount}', l10n.wtmProfileFollowers,
                onTap: () => context
                    .push('${AppRoute.wtmUserFollowers}?u=$userId')),
            const _StatDivider(),
            _Stat('${p.followingCount}', l10n.wtmProfileFollowing,
                onTap: () => context
                    .push('${AppRoute.wtmUserFollowing}?u=$userId')),
            const _StatDivider(),
            _Stat('${p.postCount}', l10n.wtmUserPosts, onTap: null),
          ],
        ),
      ),
      const SizedBox(height: WtmSpace.s14),
      EyebrowLabel(l10n.wtmUserPosts),
      const SizedBox(height: WtmSpace.s10),
      ...postsAsync.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 120),
        ],
        error: (_, _) => [Text(l10n.errorGenericTitle, style: WtmType.micro)],
        data: (posts) => posts.isEmpty
            ? [Text(l10n.wtmUserNoPosts, style: WtmType.micro)]
            : [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 3 / 4,
                  children: [
                    for (final post in posts)
                      GestureDetector(
                        onTap: () =>
                            context.push(AppRoute.wtmPost, extra: post),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(WtmRadius.tile),
                          child: (post.thumbnailUrl ?? post.imageUrl) == null
                              ? const AuroraBox()
                              : CachedNetworkImage(
                                  imageUrl:
                                      post.thumbnailUrl ?? post.imageUrl!,
                                  cacheKey: stableImageCacheKey(
                                      post.thumbnailUrl ?? post.imageUrl!),
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => const AuroraBox(),
                                  errorWidget: (_, _, _) => const AuroraBox(),
                                ),
                        ),
                      ),
                  ],
                ),
              ],
      ),
    ];
  }
}

/// WTM Followers / Following list (board §3.13, P8) — the real follow graph
/// ([followersProvider] / [followingProvider]). Reached from own-profile stats
/// (`?u` omitted → the signed-in user) and public-profile stats (`?u=<id>`).
class WtmFollowListScreen extends ConsumerWidget {
  const WtmFollowListScreen({super.key, required this.mode, this.userId});

  final WtmFollowListMode mode;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = userId ?? ref.watch(authUserIdProvider);
    final title = mode == WtmFollowListMode.followers
        ? l10n.wtmProfileFollowers
        : l10n.wtmProfileFollowing;

    if (uid == null) {
      return WtmPage(
        title: title,
        eyebrow: l10n.wtmSocialTitle,
        children: [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.user,
            title: l10n.wtmProfileSignedOutTitle,
            message: l10n.wtmProfileSignedOutMessage,
          ),
        ],
      );
    }

    final listAsync = mode == WtmFollowListMode.followers
        ? ref.watch(followersProvider(uid))
        : ref.watch(followingProvider(uid));

    return WtmPage(
      title: title,
      eyebrow: l10n.wtmSocialTitle,
      children: listAsync.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 56),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmUserErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(mode == WtmFollowListMode.followers
                ? followersProvider(uid)
                : followingProvider(uid)),
          ),
        ],
        data: (cards) => cards.isEmpty
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmEmptyState(
                  glyph: WtmGlyph.users,
                  title: l10n.wtmFollowEmptyTitle,
                  message: l10n.wtmFollowEmptyMessage,
                ),
              ]
            : [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(height: 9),
                  _FollowRow(card: card),
                ],
              ],
      ),
    );
  }
}

class _FollowRow extends ConsumerWidget {
  const _FollowRow({required this.card});

  final PublicUserCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Fold server truth in once so the pill reflects the real relationship.
    ref.read(followStoreProvider.notifier)
        .seedOnce(card.userId, following: card.isFollowing);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        gradient: WtmGradients.rowFill,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: card.displayName ?? l10n.wtmSocialSomeone,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      context.push('${AppRoute.wtmUser}?u=${card.userId}'),
                  child: Row(
                    children: [
                      WtmAvatar(card.displayName, imageUrl: card.avatarUrl),
                      const SizedBox(width: WtmSpace.s10),
                      Flexible(
                        child: Text(
                          card.displayName ?? l10n.wtmSocialSomeone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.label,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!card.isMe) WtmFollowPill(userId: card.userId),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {required this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: onTap != null,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              children: [
                Text(value, style: WtmType.h2.copyWith(fontSize: 18)),
                const SizedBox(height: 3),
                Text(label.toUpperCase(),
                    style: WtmType.micro
                        .copyWith(fontSize: 8.5, letterSpacing: 1.36)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: WtmColors.lineSoft);
}
