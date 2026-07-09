import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/social/social_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_shapes.dart';
import '../widgets/widgets.dart';
import 'wtm_community_shared.dart';

/// Saved posts (board 07 amendment, P8) — the bookmarked posts (local
/// [wtmSavedPostsProvider]) resolved against the loaded feed. Reached from the
/// Profile ⋯ menu.
class WtmSavedPostsScreen extends ConsumerWidget {
  const WtmSavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(wtmSavedPostsProvider);
    final feed = ref.watch(feedProvider).asData?.value ?? const [];
    final posts = [for (final p in feed) if (saved.contains(p.id)) p];

    return WtmPage(
      title: l10n.wtmSavedPostsTitle,
      eyebrow: l10n.wtmSavedPostsEyebrow,
      children: posts.isEmpty
          ? [
              const SizedBox(height: WtmSpace.s22),
              WtmEmptyState(
                glyph: WtmGlyph.bookmark,
                title: l10n.wtmSavedPostsEmptyTitle,
                message: l10n.wtmSavedPostsEmptyMessage,
              ),
            ]
          : [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                childAspectRatio: 4 / 3,
                children: [
                  for (final post in posts)
                    GestureDetector(
                      onTap: () => context.push(AppRoute.wtmPost, extra: post),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WtmRadius.tile),
                        child: (post.thumbnailUrl ?? post.imageUrl) == null
                            ? const AuroraBox()
                            : CachedNetworkImage(
                                imageUrl: post.thumbnailUrl ?? post.imageUrl!,
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
    );
  }
}
