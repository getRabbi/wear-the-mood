import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/public_name.dart';
import '../../shared/widgets/widgets.dart';
import 'public_profile_providers.dart';

/// Which list a [FollowListScreen] shows.
enum FollowListMode { followers, following }

/// Followers / Following list for a creator (CLAUDE.md §1 pillar 4). Each row
/// opens that user's public profile and offers a follow/unfollow toggle.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  final String userId;
  final FollowListMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = mode == FollowListMode.followers
        ? followersProvider(userId)
        : followingProvider(userId);
    final listAsync = ref.watch(provider);
    final title = mode == FollowListMode.followers
        ? l10n.followListFollowersTitle
        : l10n.followListFollowingTitle;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: listAsync.when(
          loading: () => PremiumLogoLoader(label: l10n.loadingCommunity),
          error: (_, _) => ErrorState(
            title: l10n.followListErrorTitle,
            onRetry: () => ref.invalidate(provider),
          ),
          data: (cards) {
            if (cards.isEmpty) {
              return EmptyState(
                icon: Icons.people_outline_rounded,
                title: mode == FollowListMode.followers
                    ? l10n.followListEmptyFollowers
                    : l10n.followListEmptyFollowing,
              );
            }
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpace.screenH,
                AppSpace.md,
                AppSpace.screenH,
                bottomNavClearance(context),
              ),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (_, i) => _UserRow(card: cards[i]),
            );
          },
        ),
      ),
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.card});

  final PublicUserCard card;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Fold this card's server truth into the shared follow store before the
    // first build, so the toggle starts from reality (and stays in sync with
    // any follow tapped elsewhere).
    ref.read(followStoreProvider.notifier).seedOnce(
          widget.card.userId,
          following: widget.card.isFollowing,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final card = widget.card;
    final name =
        publicName(card.displayName, card.username) ?? l10n.socialSomeone;

    final following = ref.watch(followStoreProvider).contains(card.userId);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push(
                AppRoute.userProfilePath(card.userId),
                extra: publicName(card.displayName, card.username),
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Row(
                children: [
                  _Avatar(name: name),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (card.username != null &&
                            card.username!.trim().isNotEmpty)
                          Text(
                            '@${card.username!.trim()}',
                            style: text.bodySmall
                                ?.copyWith(color: AppColors.lavender),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!card.isMe) ...[
            const SizedBox(width: AppSpace.sm),
            _MiniFollowButton(
              following: following,
              busy: _busy,
              onTap: () async {
                if (_busy) return;
                // Capture context-bound objects before the await (lint-safe).
                final messenger = ScaffoldMessenger.of(context);
                final errorText = l10n.pubProfileFollowError;
                setState(() => _busy = true);
                try {
                  await ref.read(followStoreProvider.notifier).toggle(
                        card.userId,
                        ref.read(socialRepositoryProvider),
                      );
                } catch (_) {
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(errorText)));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
            ),
          ],
        ],
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
      width: 42,
      height: 42,
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
          fontSize: 17,
        ),
      ),
    );
  }
}

class _MiniFollowButton extends StatelessWidget {
  const _MiniFollowButton({
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
      return OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: AppColors.glassBorder),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
        child: Text(l10n.pubProfileFollowing),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 8,
            ),
            child: Text(
              l10n.pubProfileFollow,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
