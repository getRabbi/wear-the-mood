import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import 'comments_sheet.dart';
import 'community_filter.dart';
import 'public_profile_providers.dart';
import 'social_providers.dart';

/// The community feed (CLAUDE.md §1 pillar 4) — OOTD posts with like, comment,
/// follow, save and "try this look". All four states (§4.3); pull to refresh;
/// FAB to share a look.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: l10n.feedChallenges,
            onPressed: () => context.push(AppRoute.challenges),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoute.socialCompose),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.feedCompose),
      ),
      body: const SafeArea(child: FeedView()),
    );
  }
}

/// The community feed body (no Scaffold) — reused by [FeedScreen] and the
/// Community tab of `CommunityScreen`. Shows the filter chips above the feed.
class FeedView extends ConsumerWidget {
  const FeedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(feedProvider);
    final filter = ref.watch(communityFilterProvider);

    return Column(
      children: [
        const _FilterChips(),
        Expanded(
          child: feed.when(
            loading: () => const _FeedShimmer(),
            error: (_, _) => ErrorState(
              title: l10n.feedErrorTitle,
              onRetry: () => ref.read(feedProvider.notifier).refresh(),
            ),
            data: (posts) {
              final filtered = filter.apply(posts);
              if (filtered.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () => ref.read(feedProvider.notifier).refresh(),
                  child: ListView(
                    children: [
                      const SizedBox(height: AppSpace.xxl),
                      EmptyState(
                        icon: Icons.dynamic_feed_outlined,
                        title: l10n.feedEmptyTitle,
                        message: l10n.feedEmptyMessage,
                        actionLabel: l10n.feedCompose,
                        onAction: () => context.push(AppRoute.socialCompose),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(feedProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: bottomNavClearance(context)),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => CommunityPostCard(post: filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(communityFilterProvider);
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        itemCount: CommunityFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final f = CommunityFilter.values[i];
          return Center(
            child: AppChip(
              label: f.label(l10n),
              selected: f == selected,
              onTap: () =>
                  ref.read(communityFilterProvider.notifier).select(f),
            ),
          );
        },
      ),
    );
  }
}

/// A rich, social post card (redesign spec): author + time + follow, the look,
/// a like/comment/save/share + "try this look" action row, caption and tags.
class CommunityPostCard extends ConsumerWidget {
  const CommunityPostCard({super.key, required this.post});

  final Post post;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openProfile(BuildContext context) {
    context.push(AppRoute.userProfilePath(post.userId), extra: post.authorName);
  }

  Future<void> _toggleFollow(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final nowFollowing = await ref
          .read(followStoreProvider.notifier)
          .toggle(post.userId, ref.read(socialRepositoryProvider));
      if (nowFollowing) {
        await ref.read(analyticsProvider).track(AnalyticsEvents.userFollowed);
        if (context.mounted) {
          _snack(context,
              l10n.socialFollowing(post.authorName ?? l10n.socialSomeone));
        }
      }
    } on ApiException {
      if (context.mounted) _snack(context, l10n.socialActionError);
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
  }) {
    return showConfirmSheet(
      context,
      icon: Icons.flag_outlined,
      title: title,
      message: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: true,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l10n.postDeleteTitle,
      body: l10n.postDeleteBody,
      confirmLabel: l10n.postDeleteConfirm,
      cancelLabel: l10n.postDeleteCancel,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(socialRepositoryProvider).deletePost(post.id);
      ref.read(feedProvider.notifier).removeLocally(post.id);
      if (context.mounted) _snack(context, l10n.postDeleted);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.postDeleteError);
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l10n.reportTitle,
      body: l10n.reportBody,
      confirmLabel: l10n.reportConfirm,
      cancelLabel: l10n.postDeleteCancel,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref
          .read(socialRepositoryProvider)
          .report(subjectType: 'post', subjectId: post.id);
      if (context.mounted) _snack(context, l10n.reported);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.socialActionError);
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l10n.blockTitle,
      body: l10n.blockBody,
      confirmLabel: l10n.blockConfirm,
      cancelLabel: l10n.postDeleteCancel,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(socialRepositoryProvider).block(post.userId);
      ref.read(feedProvider.notifier).removeLocally(post.id);
      if (context.mounted) _snack(context, l10n.blocked);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.socialActionError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final isMine = post.userId == ref.watch(currentUserProvider)?.id;
    final saved = ref.watch(savedLooksProvider).contains(post.id);
    final following = ref.watch(followStoreProvider).contains(post.userId);
    final name = post.authorName ?? l10n.socialSomeone;

    // A premium dark-glass card — never a full-bleed photo. Margin + radius +
    // hairline border keep it feeling like a social card (spec).
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.sm,
        AppSpace.screenH,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadow.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.md,
              AppSpace.sm,
              AppSpace.sm,
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _openProfile(context),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: _Avatar(name: name),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: InkWell(
                    onTap: () => _openProfile(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(_timeAgo(post.createdAt), style: text.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (!isMine)
                  _FollowButton(
                    following: following,
                    onTap: () => _toggleFollow(context, ref),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (v) => switch (v) {
                    'profile' => _openProfile(context),
                    'delete' => _delete(context, ref),
                    'report' => _report(context, ref),
                    _ => _block(context, ref),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'profile',
                      child: Text(l10n.pubProfileViewProfile),
                    ),
                    if (isMine)
                      PopupMenuItem(value: 'delete', child: Text(l10n.postDelete))
                    else ...[
                      PopupMenuItem(
                          value: 'report', child: Text(l10n.postReport)),
                      PopupMenuItem(
                          value: 'block', child: Text(l10n.socialBlock)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
            _PostImage(
              imageUrl: post.imageUrl!,
              heroTag: 'post_${post.id}',
              onTap: () => showFullscreenImage(
                context,
                post.imageUrl!,
                heroTag: 'post_${post.id}',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
              AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CountAction(
                      icon: post.likedByMe
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: post.likedByMe ? AppColors.accent : null,
                      count: post.likeCount,
                      semanticLabel: l10n.postLike,
                      onTap: () =>
                          ref.read(feedProvider.notifier).toggleLike(post),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _CountAction(
                      icon: Icons.mode_comment_outlined,
                      count: post.commentCount,
                      semanticLabel: l10n.commentsTitle,
                      onTap: () => showCommentsSheet(context, post.id),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _CountAction(
                      icon: saved ? Icons.bookmark : Icons.bookmark_border,
                      color: saved ? AppColors.violet : null,
                      count: 0,
                      semanticLabel: l10n.postSave,
                      onTap: () {
                        ref.read(savedLooksProvider.notifier).toggle(post.id);
                        _snack(context, l10n.postSaved);
                      },
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _CountAction(
                      icon: Icons.ios_share_rounded,
                      count: 0,
                      semanticLabel: l10n.postShare,
                      onTap: () => _snack(context, l10n.tryOnShareComingSoon),
                    ),
                    const Spacer(),
                    _TryThisLook(
                      onTap: () {
                        // Seed the Try-On Studio with this look, then jump to it.
                        final url = post.imageUrl;
                        if (url != null && url.isNotEmpty) {
                          ref
                              .read(tryOnPreselectProvider.notifier)
                              .setImages([url]);
                        }
                        ref
                            .read(shellTabProvider.notifier)
                            .select(ShellTabs.tryOn);
                      },
                    ),
                  ],
                ),
                if (post.caption != null && post.caption!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(post.caption!.trim(), style: text.bodyMedium),
                ],
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      for (final t in post.tags)
                        Text(
                          '#$t',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.lavender,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The post photo: a controlled 4:5 frame, capped to ~58% of screen height on
/// small Android devices so it never fills the screen (spec). Tap → full-screen.
class _PostImage extends StatelessWidget {
  const _PostImage({
    required this.imageUrl,
    required this.heroTag,
    required this.onTap,
  });

  final String imageUrl;
  final Object heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.58;
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: AppMotion.base,
              placeholder: (_, _) => const LoadingShimmer(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
              errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppGradients.brand,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.onTap, required this.following});

  final VoidCallback onTap;
  final bool following;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: following ? AppColors.glassFill : AppColors.accentSoft,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
          child: Text(
            following ? l10n.pubProfileFollowing : l10n.socialFollow,
            style: TextStyle(
              color: following ? AppColors.graphite : AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _TryThisLook extends StatelessWidget {
  const _TryThisLook({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  l10n.postTryThisLook,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
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

class _CountAction extends StatelessWidget {
  const _CountAction({
    required this.icon,
    required this.count,
    required this.semanticLabel,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final int count;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color, semanticLabel: semanticLabel),
            if (count > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Text('$count', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedShimmer extends StatelessWidget {
  const _FeedShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: 3,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: LoadingShimmer(
          width: double.infinity,
          height: 320,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}

/// Compact relative timestamp (e.g. "3h", "2d"). Kept short + numeric so it
/// reads naturally in any locale.
String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}
