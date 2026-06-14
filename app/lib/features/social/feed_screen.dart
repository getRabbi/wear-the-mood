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
import 'comments_sheet.dart';
import 'social_providers.dart';

/// The community feed (CLAUDE.md §1 pillar 4) — OOTD posts with like, comment
/// and follow. All four states (§4.3); pull to refresh; FAB to share a look.
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
/// Community tab of `CommunityScreen`.
class FeedView extends ConsumerWidget {
  const FeedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(feedProvider);
    return feed.when(
      loading: () => const _FeedShimmer(),
      error: (_, _) => ErrorState(
        title: l10n.feedErrorTitle,
        onRetry: () => ref.read(feedProvider.notifier).refresh(),
      ),
      data: (posts) => posts.isEmpty
          ? EmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: l10n.feedEmptyTitle,
              message: l10n.feedEmptyMessage,
              actionLabel: l10n.feedCompose,
              onAction: () => context.push(AppRoute.socialCompose),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(feedProvider.notifier).refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                itemCount: posts.length,
                itemBuilder: (context, i) => PostCard(post: posts[i]),
              ),
            ),
    );
  }
}

class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _follow(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(socialRepositoryProvider).follow(post.userId);
      await ref.read(analyticsProvider).track(AnalyticsEvents.userFollowed);
      if (context.mounted) {
        _snack(
          context,
          l10n.socialFollowing(post.authorName ?? l10n.socialSomeone),
        );
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
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(
            post.authorName ?? l10n.socialSomeone,
            style: text.titleMedium,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'delete' => _delete(context, ref),
              'follow' => _follow(context, ref),
              'report' => _report(context, ref),
              _ => _block(context, ref),
            },
            itemBuilder: (_) => isMine
                ? [PopupMenuItem(value: 'delete', child: Text(l10n.postDelete))]
                : [
                    PopupMenuItem(
                      value: 'follow',
                      child: Text(l10n.socialFollow),
                    ),
                    PopupMenuItem(
                      value: 'report',
                      child: Text(l10n.postReport),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text(l10n.socialBlock),
                    ),
                  ],
          ),
        ),
        if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
          AspectRatio(
            aspectRatio: 4 / 5,
            child: CachedNetworkImage(
              imageUrl: post.imageUrl!,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.lg,
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
                  const SizedBox(width: AppSpace.lg),
                  _CountAction(
                    icon: Icons.mode_comment_outlined,
                    count: post.commentCount,
                    semanticLabel: l10n.commentsTitle,
                    onTap: () => showCommentsSheet(context, post.id),
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
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
      ],
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
