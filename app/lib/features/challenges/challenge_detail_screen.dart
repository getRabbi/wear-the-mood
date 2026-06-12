import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/challenge.dart';
import '../../data/models/challenge_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../social/compose_post_screen.dart';
import 'challenge_providers.dart';

/// One challenge: its brief, the entries gallery, and the CTA to enter
/// (CLAUDE.md §1 pillar 4). Entering opens the composer pre-bound to this
/// challenge, which links the new post on success.
class ChallengeDetailScreen extends ConsumerWidget {
  const ChallengeDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final challenge = ref.watch(challengeProvider(slug));
    final loaded = challenge.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(loaded?.title ?? l10n.challengesTitle)),
      body: SafeArea(
        child: challenge.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.challengeErrorTitle,
            onRetry: () => ref.invalidate(challengeProvider(slug)),
          ),
          data: (c) => _ChallengeBody(challenge: c),
        ),
      ),
      floatingActionButton: loaded == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _enter(context, ref, loaded),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(l10n.challengeEnter),
            ),
    );
  }

  Future<void> _enter(BuildContext context, WidgetRef ref, Challenge c) async {
    await context.push(
      AppRoute.socialCompose,
      extra: ComposeArgs(challengeId: c.id, challengeTitle: c.title),
    );
    // Refresh counts/entries after returning from the composer.
    ref.invalidate(challengeProvider(slug));
    ref.invalidate(challengeEntriesProvider(c.id));
  }
}

class _ChallengeBody extends ConsumerWidget {
  const _ChallengeBody({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final entries = ref.watch(challengeEntriesProvider(challenge.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(challengeEntriesProvider(challenge.id));
        ref.invalidate(challengeProvider(challenge.slug));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.xxl * 2,
        ),
        children: [
          if (challenge.coverUrl != null && challenge.coverUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
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
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(child: Text(challenge.title, style: text.headlineSmall)),
              if (challenge.joinedByMe)
                AppChip(label: l10n.challengeJoinedBadge),
            ],
          ),
          if (challenge.prompt != null &&
              challenge.prompt!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(challenge.prompt!.trim(), style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(
            l10n.challengeEntriesCount(challenge.entryCount),
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl),
          Text(l10n.challengeEntriesTitle, style: text.titleMedium),
          const SizedBox(height: AppSpace.md),
          entries.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => ErrorState(
              title: l10n.challengeErrorTitle,
              onRetry: () =>
                  ref.invalidate(challengeEntriesProvider(challenge.id)),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                    child: Text(
                      l10n.challengeEntriesEmpty,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                : _EntriesGrid(entries: list),
          ),
        ],
      ),
    );
  }
}

class _EntriesGrid extends StatelessWidget {
  const _EntriesGrid({required this.entries});

  final List<ChallengeEntry> entries;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.72,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return OutfitTile(
          imageUrl: entry.imageUrl ?? '',
          label: entry.authorName,
        );
      },
    );
  }
}
