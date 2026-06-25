import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/post.dart';
import '../../data/models/public_profile.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/public_name.dart';
import '../../shared/widgets/widgets.dart';
import '../wardrobe/closet_colors.dart';
import 'social_providers.dart';
import 'public_profile_providers.dart';

/// A creator's PUBLIC profile (CLAUDE.md §1 pillar 4) — separate from the
/// private own-profile tab. Shows only safe fields (name, bio, style, counts,
/// public looks) with a follow/unfollow + message action. NEVER shows private
/// settings (email/password/export/delete/body data).
///
/// Resilient by design: the header + Looks grid are seeded from the already
/// public community feed, then enriched with counts/bio/follow-state from the
/// API when it's reachable. Feed posts are public by definition, so this leaks
/// nothing the user hasn't already shared.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
  });

  final String userId;
  final String? initialName;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(followStoreProvider.notifier)
          .toggle(widget.userId, ref.read(socialRepositoryProvider));
    } catch (_) {
      _snack(l10n.pubProfileFollowError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(publicProfileProvider(widget.userId));
    final profile = profileAsync.asData?.value;

    // Fold server truth into the shared follow store once it arrives.
    ref.listen(publicProfileProvider(widget.userId), (_, next) {
      final p = next.asData?.value;
      if (p != null && !p.isMe) {
        ref
            .read(followStoreProvider.notifier)
            .seedOnce(widget.userId, following: p.isFollowing);
      }
    });

    // "This is me" is known locally and reliably, even before the API responds.
    final isMe =
        profile?.isMe ?? (ref.watch(currentUserProvider)?.id == widget.userId);

    // Posts: prefer the dedicated endpoint, else derive from the public feed.
    final apiPosts = ref.watch(userPostsProvider(widget.userId)).asData?.value;
    final feedPosts = ref
            .watch(feedProvider)
            .asData
            ?.value
            .where((p) => p.userId == widget.userId)
            .toList() ??
        const <Post>[];
    final posts = (apiPosts != null && apiPosts.isNotEmpty)
        ? apiPosts
        : feedPosts;

    // Priority: display name → username → nav-passed name → a feed post's author,
    // each scrubbed so a raw email is never shown as the profile name (§10).
    final name = publicName(profile?.displayName, profile?.username) ??
        publicName(widget.initialName) ??
        (posts.isNotEmpty ? publicName(posts.first.authorName) : null) ??
        l10n.socialSomeone;

    // If the profile is genuinely unavailable (private/blocked/missing) AND we
    // have nothing public to show, surface a clean unavailable state.
    if (profileAsync.hasError && posts.isEmpty && !isMe) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.pubProfileTitle)),
        body: SafeArea(
          child: EmptyState(
            icon: Icons.lock_outline_rounded,
            title: l10n.pubProfileNotFoundTitle,
            message: l10n.pubProfileNotFoundMessage,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        top: false,
        child: DefaultTabController(
          length: 3,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenH,
                    AppSpace.md,
                    AppSpace.screenH,
                    AppSpace.md,
                  ),
                  child: _Header(
                    userId: widget.userId,
                    name: name,
                    profile: profile,
                    isMe: isMe,
                    busy: _busy,
                    looksCount: posts.length,
                    onToggleFollow: _toggleFollow,
                    onMessage: () => _snack(l10n.pubProfileMessageSoon),
                    onEdit: () => context.push(AppRoute.accountDetails),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeader(
                  TabBar(
                    labelColor: AppColors.accent,
                    indicatorColor: AppColors.accent,
                    tabs: [
                      Tab(text: l10n.pubProfileTabLooks),
                      Tab(text: l10n.pubProfileTabCloset),
                      Tab(text: l10n.pubProfileTabAbout),
                    ],
                  ),
                  Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _LooksTab(posts: posts, name: name),
                _ClosetTab(userId: widget.userId),
                _AboutTab(profile: profile, name: name),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── Header ─────────────

class _Header extends ConsumerWidget {
  const _Header({
    required this.userId,
    required this.name,
    required this.profile,
    required this.isMe,
    required this.busy,
    required this.looksCount,
    required this.onToggleFollow,
    required this.onMessage,
    required this.onEdit,
  });

  final String userId;
  final String name;
  final PublicProfile? profile;
  final bool isMe;
  final bool busy;
  final int looksCount;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final following = ref.watch(followStoreProvider).contains(userId);

    // Counts: backend numbers, with an optimistic ±1 on the follower count when
    // the viewer's follow state differs from what the server last reported.
    final base = profile?.followerCount ?? 0;
    final seeded = profile?.isFollowing ?? false;
    final followerCount =
        (base + ((following ? 1 : 0) - (seeded ? 1 : 0))).clamp(0, 1 << 31);
    final followingCount = profile?.followingCount ?? 0;
    final username = profile?.username;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A47), Color(0xFF1A102A)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InitialAvatar(name: name, radius: 32),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: text.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username != null && username.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${username.trim()}',
                        style: text.bodySmall?.copyWith(color: AppColors.lavender),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          // Stat row — Looks / Followers / Following. Followers & Following open
          // the respective lists. Equal Expanded slots so it never clips (spec).
          Row(
            children: [
              Expanded(
                child: _Stat(value: looksCount, label: l10n.pubProfileStatLooks),
              ),
              Expanded(
                child: _Stat(
                  value: followerCount,
                  label: l10n.pubProfileStatFollowers,
                  onTap: () => context.pushNamed(
                    AppRoute.userFollowersName,
                    pathParameters: {'userId': userId},
                  ),
                ),
              ),
              Expanded(
                child: _Stat(
                  value: followingCount,
                  label: l10n.pubProfileStatFollowing,
                  onTap: () => context.pushNamed(
                    AppRoute.userFollowingName,
                    pathParameters: {'userId': userId},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (isMe)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.glassBorder),
              ),
              label: Text(l10n.profileEditProfile),
            )
          else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _FollowButton(
                    following: following,
                    busy: busy,
                    onTap: onToggleFollow,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: onMessage,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.glassBorder),
                    ),
                    child: Text(l10n.pubProfileMessage),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Column(
          children: [
            Text('$value',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.following,
    required this.busy,
    required this.onTap,
  });

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppRadius.pill);
    if (following) {
      return OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: const Icon(Icons.check_rounded, size: 18),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppColors.glassBorder),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
        label: Text(l10n.pubProfileFollowing),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: radius),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              l10n.pubProfileFollow,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── Tabs ───────────────

class _LooksTab extends StatelessWidget {
  const _LooksTab({required this.posts, required this.name});

  final List<Post> posts;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final urls = [
      for (final p in posts)
        if ((p.imageUrl ?? '').isNotEmpty) p.imageUrl!,
    ];
    if (urls.isEmpty) {
      return EmptyState(
        icon: Icons.grid_on_outlined,
        title: l10n.pubProfileLooksEmptyTitle,
        message: l10n.pubProfileLooksEmptyMessage(name),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        bottomNavClearance(context),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpace.sm,
        crossAxisSpacing: AppSpace.sm,
        childAspectRatio: 0.8,
      ),
      itemCount: urls.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => showFullscreenImage(context, urls[i], heroTag: urls[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Hero(
            tag: urls[i],
            child: CachedNetworkImage(
              imageUrl: urls[i],
              fit: BoxFit.cover,
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

class _ClosetTab extends ConsumerWidget {
  const _ClosetTab({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final closet = ref.watch(userClosetProvider(userId));

    Widget empty() => EmptyState(
      icon: Icons.checkroom_outlined,
      title: l10n.pubProfileClosetEmptyTitle,
      message: l10n.pubProfileClosetEmptyMessage,
    );

    return closet.when(
      loading: () => SkeletonLoader.grid(aspectRatio: 0.7),
      // The endpoint returns [] when the closet isn't shared; on a hard error
      // we still show the same friendly empty state (never a broken screen).
      error: (_, _) => empty(),
      data: (items) {
        final shown = [
          for (final i in items)
            if ((i.displayImageUrl ?? '').isNotEmpty) i,
        ];
        if (shown.isEmpty) return empty();
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            AppSpace.screenH,
            AppSpace.md,
            AppSpace.screenH,
            bottomNavClearance(context),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.sm,
            childAspectRatio: 0.62,
          ),
          itemCount: shown.length,
          itemBuilder: (_, i) => _ClosetTile(item: shown[i]),
        );
      },
    );
  }
}

/// One public closet piece: image + name + a category/colour chip. Tap → view.
class _ClosetTile extends StatelessWidget {
  const _ClosetTile({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final url = item.displayImageUrl ?? '';
    final color = resolveItemColor(item);
    final label = item.category ?? color?.label;

    return GestureDetector(
      onTap: () => showFullscreenImage(context, url, heroTag: 'closet_${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Hero(
                tag: 'closet_${item.id}',
                child: ColoredBox(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xs),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      errorWidget: (_, _, _) => const Icon(
                        Icons.checkroom_outlined,
                        color: AppColors.graphite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          if ((item.title ?? '').isNotEmpty)
            Text(
              item.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          if (label != null && label.isNotEmpty)
            Row(
              children: [
                if (color != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color.swatch,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.lavender),
                  ),
                ),
              ],
            )
          else
            Text(
              l10n.pubProfileTabCloset,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.profile, required this.name});

  final PublicProfile? profile;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final bio = profile?.bio?.trim();
    final tags = profile?.styleTags ?? const <String>[];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        bottomNavClearance(context),
      ),
      children: [
        AppCard(
          child: Text(
            (bio != null && bio.isNotEmpty) ? bio : l10n.pubProfileAboutBioEmpty,
            style: text.bodyMedium?.copyWith(
              color: (bio != null && bio.isNotEmpty)
                  ? null
                  : AppColors.graphite,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(l10n.pubProfileAboutStyleTitle, style: text.titleMedium),
        const SizedBox(height: AppSpace.sm),
        if (tags.isEmpty)
          Text(l10n.pubProfileAboutStyleEmpty,
              style: text.bodySmall?.copyWith(color: AppColors.graphite))
        else
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              for (final t in tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    t,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.lavender,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── Shared ──────────────

/// A gradient initial avatar — consistent with the community feed (we don't
/// expose other users' private photo paths, §10).
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppGradients.brand,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: background, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) =>
      tabBar != oldDelegate.tabBar || background != oldDelegate.background;
}
