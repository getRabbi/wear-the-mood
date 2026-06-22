import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/share/share_service.dart';
import '../../core/theme/tokens.dart';
import '../../shared/utils/image_format.dart';
import '../../data/models/poll.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import 'comments_sheet.dart';
import 'community_filter.dart';
import 'compose_post_screen.dart';
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

  /// Native share sheet for the look — the caption (if any) plus a friendly
  /// tagline. Falls back to a friendly message if the OS share fails; never
  /// crashes.
  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final caption = post.caption?.trim();
    final text = (caption != null && caption.isNotEmpty)
        ? '$caption\n\n${l10n.postShareText}'
        : l10n.postShareText;
    try {
      await ref.read(shareServiceProvider).shareText(text);
    } catch (_) {
      if (context.mounted) _snack(context, l10n.shareFailed);
    }
  }

  /// Open the Try-On Studio seeded with this look. If the post has no usable
  /// image, the studio still opens (empty) with a friendly hint — never a crash
  /// or silent no-op.
  void _tryThisLook(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = post.imageUrl;
    if (url != null && url.isNotEmpty) {
      ref.read(tryOnPreselectProvider.notifier).setImages([url]);
    } else {
      _snack(context, l10n.postTryThisLookEmptyHint);
    }
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
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

  /// Open the composer in edit mode for this post (Post Edit, flag-gated).
  void _edit(BuildContext context) {
    context.push(AppRoute.socialCompose, extra: ComposeArgs(editPost: post));
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
    // Edit is owner-only and behind the feature flag (off by default, §16).
    final canEdit =
        isMine && ref.watch(featureEnabledProvider(FeatureFlags.postEdit));
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
                        Text(
                          post.isEdited
                              ? '${_timeAgo(post.createdAt)} · ${l10n.postEditedLabel}'
                              : _timeAgo(post.createdAt),
                          style: text.bodySmall,
                        ),
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
                    'edit' => _edit(context),
                    'delete' => _delete(context, ref),
                    'report' => _report(context, ref),
                    _ => _block(context, ref),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'profile',
                      child: Text(l10n.pubProfileViewProfile),
                    ),
                    if (isMine) ...[
                      if (canEdit)
                        PopupMenuItem(value: 'edit', child: Text(l10n.postEdit)),
                      PopupMenuItem(value: 'delete', child: Text(l10n.postDelete)),
                    ] else ...[
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
              // Feed list shows the lighter thumbnail where available; tap opens
              // the full image.
              imageUrl: post.thumbnailUrl ?? post.imageUrl!,
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
                    // The icon actions take the available width and scroll
                    // horizontally if cramped on small screens, so "Try this
                    // look" stays pinned and nothing overflows (spec).
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
                              onTap: () => _share(context, ref),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _TryThisLook(onTap: () => _tryThisLook(context, ref)),
                  ],
                ),
                if (post.caption != null && post.caption!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    post.caption!.trim(),
                    style: text.bodyMedium,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                if (post.poll != null) ...[
                  const SizedBox(height: AppSpace.md),
                  _PollView(poll: post.poll!),
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
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.58;
    // Decode at display width (full-bleed card) so the feed stays memory-light.
    final cacheW = (media.size.width * media.devicePixelRatio).clamp(64, 1440).round();
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(
            aspectRatio: 4 / 5,
            child: Hero(
              tag: heroTag,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                // Key on object identity so a refreshed signed URL reuses bytes (1D).
                cacheKey: stableImageCacheKey(imageUrl),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                fadeInDuration: AppMotion.base,
                memCacheWidth: cacheW,
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
    // Outlined accent, not a gradient — there's one per post (§3).
    return GhostButton(
      label: l10n.postTryThisLook,
      icon: Icons.auto_awesome,
      dense: true,
      expand: false,
      onPressed: onTap,
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

/// Card-shaped skeletons that mirror the real post card (header → image →
/// actions) for a premium loading state, not a bare grey box.
class _FeedShimmer extends StatelessWidget {
  const _FeedShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.only(
        top: AppSpace.sm,
        bottom: bottomNavClearance(context),
      ),
      itemCount: 3,
      itemBuilder: (context, _) => Container(
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
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  LoadingShimmer(
                    width: 40,
                    height: 40,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      LoadingShimmer(width: 120, height: 12),
                      SizedBox(height: 6),
                      LoadingShimmer(width: 60, height: 10),
                    ],
                  ),
                ],
              ),
            ),
            const LoadingShimmer(
              width: double.infinity,
              height: 280,
              borderRadius: BorderRadius.zero,
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: LoadingShimmer(width: 160, height: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A poll under a post (FEATURES_COMMUNITY_PLUS · Poll). Before voting, options
/// are tappable; after voting (or once closed) it shows result bars with % and
/// total votes, highlighting the viewer's own choice. Holds the latest poll
/// locally so a vote updates in place without a feed refetch.
class _PollView extends ConsumerStatefulWidget {
  const _PollView({required this.poll});

  final Poll poll;

  @override
  ConsumerState<_PollView> createState() => _PollViewState();
}

class _PollViewState extends ConsumerState<_PollView> {
  late Poll _poll = widget.poll;
  bool _voting = false;

  @override
  void didUpdateWidget(_PollView old) {
    super.didUpdateWidget(old);
    // Reseed from a refreshed feed (e.g. pull-to-refresh brought newer counts).
    if (widget.poll != old.poll) _poll = widget.poll;
  }

  Future<void> _vote(int index) async {
    if (_voting || _poll.showResults) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _voting = true);
    try {
      final updated =
          await ref.read(socialRepositoryProvider).votePoll(_poll.id, index);
      await ref.read(analyticsProvider).track(AnalyticsEvents.pollVoted);
      if (mounted) setState(() => _poll = updated);
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.pollVoteError)));
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final showResults = _poll.showResults;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_outlined, size: 18, color: AppColors.lavender),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(_poll.question, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final option in _poll.options)
            _PollRow(
              label: option.label,
              votes: option.votes,
              total: _poll.totalVotes,
              showResults: showResults,
              mine: _poll.myChoice == option.index,
              onTap: _voting ? null : () => _vote(option.index),
            ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _poll.isClosed
                ? '${l10n.pollTotalVotes(_poll.totalVotes)} · ${l10n.pollClosed}'
                : l10n.pollTotalVotes(_poll.totalVotes),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _PollRow extends StatelessWidget {
  const _PollRow({
    required this.label,
    required this.votes,
    required this.total,
    required this.showResults,
    required this.mine,
    required this.onTap,
  });

  final String label;
  final int votes;
  final int total;
  final bool showResults;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.sm);

    if (!showResults) {
      // Pre-vote: a tappable outlined option.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              width: double.infinity,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppColors.accent, width: 1.2),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Post-vote / closed: a result bar with %, highlighting the viewer's choice.
    final fraction = total == 0 ? 0.0 : (votes / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Container(height: 44, color: AppColors.paperAlt),
            FractionallySizedBox(
              widthFactor: fraction == 0 ? 0.0001 : fraction,
              child: Container(
                height: 44,
                color: mine
                    ? AppColors.accent.withValues(alpha: 0.30)
                    : AppColors.lavender.withValues(alpha: 0.18),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  children: [
                    if (mine) ...[
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: AppSpace.xs),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.graphite,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
