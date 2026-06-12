import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/challenge.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'challenge_providers.dart';

/// Browse active style challenges (CLAUDE.md §1 pillar 4, §24). All four states
/// (§4.3); tap a challenge to see its brief and entries, and to enter.
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final challenges = ref.watch(challengesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.challengesTitle)),
      body: SafeArea(
        child: challenges.when(
          loading: () => const _ChallengesShimmer(),
          error: (_, _) => ErrorState(
            title: l10n.challengesErrorTitle,
            onRetry: () => ref.invalidate(challengesProvider),
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: l10n.challengesEmptyTitle,
                  message: l10n.challengesEmptyMessage,
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(challengesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        _ChallengeCard(challenge: list[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push('${AppRoute.challenges}/${challenge.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (challenge.coverUrl != null && challenge.coverUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: challenge.coverUrl!,
                    fit: BoxFit.cover,
                    fadeInDuration: AppMotion.base,
                    placeholder: (_, _) => const LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.mist),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(challenge.title, style: text.titleMedium),
                      ),
                      if (challenge.joinedByMe)
                        AppChip(label: l10n.challengeJoinedBadge),
                    ],
                  ),
                  if (challenge.prompt != null &&
                      challenge.prompt!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      challenge.prompt!.trim(),
                      style: text.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    l10n.challengeEntriesCount(challenge.entryCount),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengesShimmer extends StatelessWidget {
  const _ChallengesShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: 3,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: LoadingShimmer(
          width: double.infinity,
          height: 220,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
