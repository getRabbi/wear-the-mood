import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../data/models/profile.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/collections/local_collections.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/social/public_profile_providers.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Profile (board 11 + §3.1, P7) — the signed-in user's profile on the real
/// profile + social + wardrobe data. Segments (Closet · Looks · Posts), tappable
/// stats, Style DNA from the profile's style tags, member card → paywall, and
/// the ⋯ menu → Settings / Saved posts.
class WtmProfileScreen extends ConsumerStatefulWidget {
  const WtmProfileScreen({super.key});

  @override
  ConsumerState<WtmProfileScreen> createState() => _WtmProfileScreenState();
}

class _WtmProfileScreenState extends ConsumerState<WtmProfileScreen> {
  int _segment = 0;

  void _menu() => showWtmSheet(
        context,
        title: AppLocalizations.of(context).wtmProfileTitle,
        children: [
          WtmRow(
            glyph: WtmGlyph.sliders,
            title: AppLocalizations.of(context).wtmSettingsTitle,
            onTap: () {
              Navigator.of(context).pop();
              context.push(AppRoute.wtmSettings);
            },
          ),
          const SizedBox(height: 9),
          WtmRow(
            glyph: WtmGlyph.bookmark,
            title: AppLocalizations.of(context).wtmProfileSavedPosts,
            onTap: () {
              Navigator.of(context).pop();
              context.push(AppRoute.wtmProfileSaved);
            },
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          WtmSpace.s8,
          WtmSpace.screenH,
          wtmNavClearance,
        ),
        children: [
          Row(
            children: [
              const SizedBox(width: 44),
              const Spacer(),
              WtmIconButton(
                WtmGlyph.dots,
                semanticLabel: l10n.wtmProfileMenu,
                onTap: _menu,
              ),
            ],
          ),
          ...profileAsync.when<List<Widget>>(
            skipLoadingOnReload: true,
            loading: () => [
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: LoadingShimmer(width: 160, height: 22),
                ),
              ),
            ],
            error: (_, _) => [
              const SizedBox(height: WtmSpace.s22),
              WtmEmptyState(
                glyph: WtmGlyph.user,
                title: l10n.wtmProfileSignedOutTitle,
                message: l10n.wtmProfileSignedOutMessage,
              ),
            ],
            data: (profile) => _content(context, l10n, profile),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    AppLocalizations l10n,
    Profile profile,
  ) {
    final userId = ref.watch(authUserIdProvider);
    final pub = userId == null
        ? null
        : ref.watch(publicProfileProvider(userId)).asData?.value;
    final items = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final outfits = ref.watch(outfitsProvider).asData?.value ?? const [];
    final looks = ref.watch(savedLookRecordsProvider);
    final name = (profile.displayName ?? '').trim();

    return [
      Center(
        child: Column(
          children: [
            _Avatar(url: profile.profilePictureDisplayUrl, name: name),
            const SizedBox(height: 11),
            Text(
              name.isEmpty ? l10n.wtmProfileYou : name,
              style: WtmType.h1.copyWith(fontSize: 21),
            ),
            const SizedBox(height: 6),
            EyebrowLabel(l10n.wtmProfileEyebrow),
            const SizedBox(height: WtmSpace.s12),
            GoldPill(
              label: l10n.wtmProfileEdit,
              onTap: () => context.push(AppRoute.wtmProfileEdit),
            ),
          ],
        ),
      ),
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
            _Stat(_count(pub?.followerCount), l10n.wtmProfileFollowers,
                onTap: () => context.push(AppRoute.wtmUserFollowers)),
            const _StatDivider(),
            _Stat(_count(pub?.followingCount), l10n.wtmProfileFollowing,
                onTap: () => context.push(AppRoute.wtmUserFollowing)),
            const _StatDivider(),
            _Stat('${items.length}', l10n.wtmProfileItems,
                onTap: () => context.push(AppRoute.wtmCloset)),
            const _StatDivider(),
            _Stat('${outfits.length}', l10n.wtmProfileOutfits,
                onTap: () => context.push(AppRoute.wtmOutfits)),
          ],
        ),
      ),
      if (profile.styleTags.isNotEmpty) ...[
        const SizedBox(height: WtmSpace.s10),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: WtmGradients.cardFill,
            borderRadius: BorderRadius.circular(WtmRadius.card),
            border: Border.all(color: WtmColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EyebrowLabel(l10n.wtmProfileStyleDna),
              const SizedBox(height: WtmSpace.s10),
              Wrap(
                spacing: WtmSpace.s6,
                runSpacing: WtmSpace.s6,
                children: [
                  for (final tag in profile.styleTags.take(6))
                    WtmChip(label: tag, on: true),
                ],
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: WtmSpace.s14),
      WtmChipRow(
        children: [
          for (final (i, label) in [
            l10n.wtmProfileSegCloset,
            l10n.wtmProfileSegLooks,
            l10n.wtmProfileSegPosts,
          ].indexed)
            WtmChip(
              label: label,
              on: _segment == i,
              onTap: () => setState(() => _segment = i),
            ),
        ],
      ),
      const SizedBox(height: WtmSpace.s10),
      Row(
        children: [
          EyebrowLabel([
            l10n.wtmProfileMyCloset,
            l10n.wtmProfileMyLooks,
            l10n.wtmProfileMyPosts,
          ][_segment]),
          const Spacer(),
          _MicroLink(
            l10n.wtmViewAll,
            onTap: () => switch (_segment) {
              0 => context.push(AppRoute.wtmCloset),
              1 => context.push(AppRoute.wtmLooks),
              _ => context.go(AppRoute.wtmSocial),
            },
          ),
        ],
      ),
      const SizedBox(height: WtmSpace.s10),
      _SegmentGrid(segment: _segment, items: items, looks: looks, l10n: l10n),
      const SizedBox(height: WtmSpace.s14),
      Semantics(
        button: true,
        label: l10n.wtmProfileMembership,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push(AppRoute.wtmPaywall),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: WtmGradients.assistFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WtmColors.assistBorder),
              ),
              child: Row(
                children: [
                  const WtmIcon(WtmGlyph.sparkle,
                      size: 18, color: WtmColors.gold),
                  const SizedBox(width: WtmSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.wtmProfileMembership,
                            style: WtmType.labelMedium),
                        const SizedBox(height: 3),
                        Text(l10n.wtmProfileMembershipSub,
                            style: WtmType.micro),
                      ],
                    ),
                  ),
                  const WtmIcon(WtmGlyph.chevron,
                      size: 15, color: WtmColors.faint),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  String _count(int? n) => n == null ? '—' : '$n';
}

class _SegmentGrid extends StatelessWidget {
  const _SegmentGrid({
    required this.segment,
    required this.items,
    required this.looks,
    required this.l10n,
  });

  final int segment;
  final List<WardrobeItem> items;
  final List<SavedLook> looks;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Closet minis.
    if (segment == 0) {
      if (items.isEmpty) return _EmptyMini(l10n.wtmProfileEmptyCloset);
      return Row(
        children: [
          for (final (i, item) in items.take(4).indexed) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: FabricTile(
                imageUrl: item.displayImageUrl,
                swatchIndex: i,
                fit: BoxFit.contain,
                radius: 9,
                semanticLabel: item.title,
                onTap: () =>
                    context.push(AppRoute.wtmClosetItem, extra: item),
              ),
            ),
          ],
        ],
      );
    }
    // Saved looks minis.
    if (segment == 1) {
      if (looks.isEmpty) return _EmptyMini(l10n.wtmProfileEmptyLooks);
      return Row(
        children: [
          for (final (i, look) in looks.take(4).indexed) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: GestureDetector(
                onTap: () => context.push(AppRoute.wtmLooks),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: CachedNetworkImage(
                      imageUrl: look.imageUrl,
                      cacheKey: stableImageCacheKey(look.imageUrl),
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const AuroraBox(
                        borderRadius: BorderRadius.all(Radius.circular(9)),
                      ),
                      errorWidget: (_, _, _) => const AuroraBox(
                        borderRadius: BorderRadius.all(Radius.circular(9)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    // Posts — the user's community posts land with P8; invite to share.
    return _EmptyMini(l10n.wtmProfileEmptyPosts);
  }
}

class _EmptyMini extends StatelessWidget {
  const _EmptyMini(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Text(message, textAlign: TextAlign.center, style: WtmType.micro),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    final initials = name.isEmpty
        ? '·'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
            .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: WtmGradients.assistFill,
        border: Border.all(color: WtmColors.pillBorder),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (url == null || url!.isEmpty)
          ? Text(initials,
              style: WtmType.h1.copyWith(fontSize: 26, color: WtmColors.gold))
          : CachedNetworkImage(
              imageUrl: url!,
              cacheKey: stableImageCacheKey(url!),
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, _) => Text(initials,
                  style:
                      WtmType.h1.copyWith(fontSize: 26, color: WtmColors.gold)),
              errorWidget: (_, _, _) => Text(initials,
                  style:
                      WtmType.h1.copyWith(fontSize: 26, color: WtmColors.gold)),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {required this.onTap});

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
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
                    style: WtmType.micro.copyWith(
                        fontSize: 8.5, letterSpacing: 1.36)),
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

class _MicroLink extends StatelessWidget {
  const _MicroLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WtmSpace.s8, vertical: WtmSpace.s12),
            child:
                Text(label, style: WtmType.micro.copyWith(color: WtmColors.gold)),
          ),
        ),
      ),
    );
  }
}
