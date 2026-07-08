import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/env/app_env.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/router/routes.dart';
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/social/social_providers.dart';
import '../../features/stylist/stylist_controller.dart';
import '../../features/stylist/stylist_state.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_mood.dart';

/// WTM Home — the command center (board 01 + §3.1 amendments), P2 pixel pass.
///
/// Greeting uses the signed-in profile name (shimmer while it loads, hidden
/// when browsing without a session). The mood slider persists via
/// [wtmMoodProvider] and re-seeds Today's Look zone/name live; the AI Stylist
/// reads the same value. Today's Look and Inspiration render REAL imagery —
/// the stylist's pick, saved outfits/looks, closet pieces, and (when the
/// community flag is on) feed posts — with honest loading/empty states
/// (mobile QA: no blank gradient cards).
class WtmHomeScreen extends ConsumerWidget {
  const WtmHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mood = ref.watch(wtmMoodProvider);
    final zone = WtmMoodZone.of(mood);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          20, // board .body top
          WtmSpace.screenH,
          120, // clearance under the floating nav
        ),
        children: [
          _AppHead(l10n: l10n),
          const SizedBox(height: WtmSpace.s18),
          _Greeting(l10n: l10n),
          const SizedBox(height: WtmSpace.s6),
          Text(l10n.wtmHomeTagline, style: WtmType.sub),

          const SizedBox(height: WtmSpace.s18),
          EyebrowLabel(l10n.wtmMoodEyebrow),
          const SizedBox(height: WtmSpace.s12),
          WtmSlider(
            value: mood,
            onChanged: ref.read(wtmMoodProvider.notifier).preview,
            onChangeEnd: ref.read(wtmMoodProvider.notifier).commit,
            fill: false,
            height: 4,
            semanticLabel: l10n.wtmMoodEyebrow,
            trackGradient: const LinearGradient(
              // board .track.mood spectrum
              colors: [
                Color(0xFF6F86D6),
                Color(0xFF9B7BE8),
                Color(0xFFC77DFF),
                Color(0xFFF3A0C8),
              ],
              stops: [0.0, 0.35, 0.65, 1.0],
            ),
          ),
          const SizedBox(height: WtmSpace.s8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final z in WtmMoodZone.values)
                Text(
                  _zoneLabel(l10n, z),
                  style: z == zone
                      ? WtmType.micro.copyWith(color: WtmColors.gold)
                      : WtmType.micro,
                ),
            ],
          ),

          const SizedBox(height: WtmSpace.s16),
          Row(
            children: [
              _QuickAction(
                glyph: WtmGlyph.camera,
                label: l10n.wtmQaTryOn,
                onTap: () => context.push(AppRoute.wtmMirror),
              ),
              const SizedBox(width: WtmSpace.s8),
              _QuickAction(
                glyph: WtmGlyph.hanger,
                label: l10n.wtmQaCloset,
                onTap: () => context.push(AppRoute.wtmCloset),
              ),
              const SizedBox(width: WtmSpace.s8),
              _QuickAction(
                glyph: WtmGlyph.sparkle,
                label: l10n.wtmQaStylist,
                onTap: () => context.push(AppRoute.wtmStylist),
              ),
              const SizedBox(width: WtmSpace.s8),
              _QuickAction(
                glyph: WtmGlyph.shirt,
                label: l10n.wtmQaOutfits,
                onTap: () => context.push(AppRoute.wtmOutfits),
              ),
            ],
          ),

          const SizedBox(height: WtmSpace.s16),
          _TodaysLookCard(l10n: l10n, zone: zone),

          const SizedBox(height: WtmSpace.s16),
          Row(
            children: [
              EyebrowLabel(l10n.wtmInspiration),
              const Spacer(),
              _MicroLink(
                l10n.wtmViewAll,
                onTap: () => context.go(AppRoute.wtmSocial),
              ),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          const _InspirationRow(),

          const SizedBox(height: WtmSpace.s16),
          EyebrowLabel(l10n.wtmDiscover),
          const SizedBox(height: WtmSpace.s10),
          Row(
            children: [
              _QuickAction(
                glyph: WtmGlyph.gift,
                label: l10n.wtmDiscoverGiveaways,
                onTap: () => context.push(AppRoute.wtmGiveaways),
              ),
              const SizedBox(width: WtmSpace.s8),
              _QuickAction(
                glyph: WtmGlyph.store,
                label: l10n.wtmDiscoverOffers,
                onTap: () => context.push(AppRoute.wtmOffers),
              ),
              const SizedBox(width: WtmSpace.s8),
              _QuickAction(
                glyph: WtmGlyph.image,
                label: l10n.wtmDiscoverNewsroom,
                onTap: () => context.push(AppRoute.wtmNewsroom),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _zoneLabel(AppLocalizations l10n, WtmMoodZone zone) =>
      switch (zone) {
        WtmMoodZone.calm => l10n.wtmMoodCalm,
        WtmMoodZone.confident => l10n.wtmMoodConfident,
        WtmMoodZone.bold => l10n.wtmMoodBold,
        WtmMoodZone.rebel => l10n.wtmMoodRebel,
      };
}

/// Board `.apphead` — wordmark + bell → Inbox (§8).
class _AppHead extends StatelessWidget {
  const _AppHead({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // "Wear The Mood" → two-line uppercase wordmark ("WEAR THE\nMOOD").
    final words = l10n.appTitle.toUpperCase().split(' ');
    final wordmark = words.length > 1
        ? '${words.sublist(0, words.length - 1).join(' ')}\n${words.last}'
        : l10n.appTitle.toUpperCase();
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: WtmColors.pillBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            'W',
            style: WtmType.h2.copyWith(fontSize: 16, color: WtmColors.gold),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          wordmark,
          style: WtmType.micro.copyWith(
            fontSize: 8.5,
            letterSpacing: 2.55, // .3em × 8.5
            color: WtmColors.muted,
            height: 1.5,
          ),
        ),
        const Spacer(),
        WtmIconButton(
          WtmGlyph.bell,
          semanticLabel: l10n.wtmNavInbox,
          onTap: () => context.go(AppRoute.wtmInbox),
        ),
      ],
    );
  }
}

/// Serif greeting with the signed-in first name in gold italic; shimmer while
/// the profile loads, greeting-only when browsing without a session or on a
/// profile error (name is decoration, never a blocker).
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hello = switch (DateTime.now().hour) {
      < 12 => l10n.homeHelloMorning,
      < 17 => l10n.homeHelloAfternoon,
      _ => l10n.homeHelloEvening,
    };
    // Supabase-backed providers assert without env config (tests, previews) —
    // same guard the app root uses. Guests get the greeting, no name.
    final signedIn = AppEnv.hasSupabaseConfig &&
        ref.watch(signedInEmailProvider) != null;
    if (!signedIn) return Text(hello, style: WtmType.display);

    final profile = ref.watch(profileProvider);
    if (profile.isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$hello,', style: WtmType.display),
          const Padding(
            padding: EdgeInsets.only(top: WtmSpace.s6),
            child: LoadingShimmer(width: 140, height: 24),
          ),
        ],
      );
    }
    final name = profile.asData?.value.displayName?.trim();
    if (name == null || name.isEmpty) {
      return Text(hello, style: WtmType.display);
    }
    final firstName = name.split(RegExp(r'\s+')).first;
    return Text.rich(
      TextSpan(
        text: '$hello,\n',
        style: WtmType.display,
        children: [
          TextSpan(
            text: firstName,
            style: WtmType.goldItalic(WtmType.display),
          ),
        ],
      ),
    );
  }
}

/// Board `.qa` cell — gold 19px glyph over a two-line micro label.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final WtmGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label.replaceAll('\n', ' '),
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10), // .qa cell
              decoration: BoxDecoration(
                border: Border.all(color: WtmColors.line),
                borderRadius: BorderRadius.circular(14),
                color: WtmColors.iconBtnBg,
              ),
              child: Column(
                children: [
                  WtmIcon(glyph, color: WtmColors.gold),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: WtmType.micro.copyWith(
                      fontSize: 8.5,
                      letterSpacing: 0.425, // .05em × 8.5
                      color: WtmColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's Look hero card — zone-seeded name over the wearer's REAL pieces:
/// the stylist's current pick when one is loaded, else the newest saved
/// outfit, else the latest saved look, else the closet's freshest pieces.
/// Empty closet → an honest invitation (never fake blank outfit cards);
/// still loading → shimmer. Taps into the stylist look detail (§8).
class _TodaysLookCard extends ConsumerWidget {
  const _TodaysLookCard({required this.l10n, required this.zone});

  final AppLocalizations l10n;
  final WtmMoodZone zone;

  static const _zoneSwatches = {
    WtmMoodZone.calm: [6, 1, 2, 7],
    WtmMoodZone.confident: [0, 1, 3, 5], // board c1 c2 c4 c6
    WtmMoodZone.bold: [4, 0, 5, 2],
    WtmMoodZone.rebel: [5, 6, 0, 3],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stylist = ref.watch(stylistControllerProvider);
    final outfitsAsync = ref.watch(outfitsProvider);
    final itemsAsync = ref.watch(wardrobeItemsProvider);
    final looks = ref.watch(savedLookRecordsProvider);

    // The pieces to show, best source first (stylist pick → newest outfit →
    // closet). Saved-look renders fill the hero when there are no pieces.
    final byId = {
      for (final i in itemsAsync.asData?.value ?? const <WardrobeItem>[])
        i.id: i,
    };
    List<WardrobeItem> pieces;
    String? title;
    if (stylist case StylistSuccess(:final suggestion)
        when !suggestion.isEmpty) {
      pieces = suggestion.items;
      title = suggestion.title;
    } else if ((outfitsAsync.asData?.value ?? const <Outfit>[])
        case [final newest, ...]) {
      pieces = [
        for (final id in newest.itemIds)
          if (byId[id] != null) byId[id]!,
      ];
      title = newest.name?.trim();
    } else {
      pieces = itemsAsync.asData?.value ?? const [];
    }
    final heroUrl = pieces
            .map((p) => p.displayImageUrl)
            .whereType<String>()
            .firstOrNull ??
        looks.firstOrNull?.imageUrl;

    // Still fetching with nothing local to show → shimmer, not fake cards.
    final loading = (outfitsAsync.isLoading || itemsAsync.isLoading) &&
        pieces.isEmpty &&
        looks.isEmpty;
    if (loading) {
      return const LoadingShimmer(
        width: double.infinity,
        height: 150,
        borderRadius: BorderRadius.all(Radius.circular(WtmRadius.card)),
      );
    }

    // Nothing to dress with at all → honest empty CTA into the closet.
    if (pieces.isEmpty && heroUrl == null) {
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: WtmGradients.cardFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EyebrowLabel(l10n.wtmTodaysLook),
            const SizedBox(height: WtmSpace.s8),
            Text(l10n.wtmTodaysLookEmptyMessage, style: WtmType.sub),
            const SizedBox(height: WtmSpace.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: GoldPill(
                label: l10n.wtmTodaysLookEmptyCta,
                icon: const WtmIcon(WtmGlyph.plus,
                    size: 12, color: WtmColors.gold),
                onTap: () => context.push(AppRoute.wtmClosetAdd),
              ),
            ),
          ],
        ),
      );
    }

    final (nameA, nameB) = switch (zone) {
      WtmMoodZone.calm => (l10n.wtmLookCalmA, l10n.wtmLookCalmB),
      WtmMoodZone.confident =>
        (l10n.wtmLookConfidentA, l10n.wtmLookConfidentB),
      WtmMoodZone.bold => (l10n.wtmLookBoldA, l10n.wtmLookBoldB),
      WtmMoodZone.rebel => (l10n.wtmLookRebelA, l10n.wtmLookRebelB),
    };
    final daypart = switch (DateTime.now().hour) {
      < 12 => l10n.wtmDaypartMorning,
      < 17 => l10n.wtmDaypartAfternoon,
      _ => l10n.wtmDaypartEvening,
    };
    final hasTitle = title != null && title.isNotEmpty;
    return Semantics(
      button: true,
      label: '${l10n.wtmTodaysLook}. ${hasTitle ? title : '$nameA $nameB'}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(AppRoute.wtmStylistLook),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      height: 70,
                      child: FabricTile(
                        imageUrl: heroUrl,
                        swatchIndex: _zoneSwatches[zone]![0],
                        aspectRatio: null,
                        fit: BoxFit.cover,
                        radius: 9,
                      ),
                    ),
                    const SizedBox(width: WtmSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EyebrowLabel(l10n.wtmTodaysLook),
                          const SizedBox(height: 5),
                          if (hasTitle)
                            Text(
                              title,
                              style: WtmType.h2.copyWith(fontSize: 17),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          else
                            Text.rich(
                              TextSpan(
                                text: '$nameA ',
                                style: WtmType.h2.copyWith(fontSize: 17),
                                children: [
                                  TextSpan(
                                    text: nameB,
                                    style: WtmType.goldItalic(
                                      WtmType.h2.copyWith(fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.wtmLookContext(daypart),
                            style: WtmType.micro,
                          ),
                        ],
                      ),
                    ),
                    const WtmIcon(
                      WtmGlyph.chevron,
                      size: 15,
                      color: WtmColors.faint,
                    ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s12),
                Row(
                  children: [
                    // Real garment thumbnails, padded to four with the zone's
                    // fabric swatches (styled fills, not blank cards).
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: i < pieces.length
                            ? FabricTile(
                                imageUrl: pieces[i].displayImageUrl,
                                swatchIndex: _zoneSwatches[zone]![i],
                                fit: BoxFit.contain,
                                radius: 9,
                                semanticLabel: pieces[i].title,
                              )
                            : FabricTile(
                                swatchIndex: _zoneSwatches[zone]![i],
                                radius: 9,
                              ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Inspiration For You" — a horizontally scrollable carousel of REAL imagery,
/// sized so three cards show at once (mobile QA): community posts when the
/// feed is live (tap → post), plus the wearer's saved looks, outfit covers,
/// and closet pieces (tap → the item). No placeholder padding — only real
/// tiles render. Loading → shimmer; error with nothing to show → retry;
/// truly nothing → an honest CTA into MoodMirror.
class _InspirationRow extends ConsumerWidget {
  const _InspirationRow();

  /// Cards visible at once; the rest scroll.
  static const _visible = 3;
  static const _gap = WtmSpace.s8;
  static const _maxTiles = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final communityOn =
        ref.watch(featureEnabledProvider(FeatureFlags.community));
    final feed = communityOn ? ref.watch(feedProvider) : null;
    final looks = ref.watch(savedLookRecordsProvider);
    final outfitsAsync = ref.watch(outfitsProvider);
    final itemsAsync = ref.watch(wardrobeItemsProvider);

    // Assemble the carousel (best source first), deduping repeated images.
    final tiles = <({String url, VoidCallback onTap})>[];
    final seen = <String>{};
    void add(String? url, VoidCallback onTap) {
      if (url == null || tiles.length >= _maxTiles || !seen.add(url)) return;
      tiles.add((url: url, onTap: onTap));
    }

    if (feed?.asData?.value case final posts?) {
      for (final post in posts) {
        add(
          post.thumbnailUrl ?? post.imageUrl,
          () => context.push(AppRoute.wtmPost, extra: post),
        );
      }
    }
    for (final look in looks) {
      add(look.imageUrl, () => context.push(AppRoute.wtmLooks));
    }
    final byId = {
      for (final i in itemsAsync.asData?.value ?? const <WardrobeItem>[])
        i.id: i,
    };
    for (final outfit in outfitsAsync.asData?.value ?? const <Outfit>[]) {
      add(
        outfit.coverImageUrl ??
            outfit.itemIds
                .map((id) => byId[id]?.displayImageUrl)
                .whereType<String>()
                .firstOrNull,
        () => context.push(AppRoute.wtmOutfitDetail, extra: outfit),
      );
    }
    for (final item in itemsAsync.asData?.value ?? const <WardrobeItem>[]) {
      add(
        item.displayImageUrl,
        () => context.push(AppRoute.wtmClosetItem, extra: item),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Exactly three cards fit the viewport; extras scroll into view.
        final tileW = (constraints.maxWidth - (_visible - 1) * _gap) / _visible;
        final tileH = tileW * 4 / 3;

        if (tiles.isEmpty) {
          final loading = (feed?.isLoading ?? false) ||
              outfitsAsync.isLoading ||
              itemsAsync.isLoading;
          if (loading) {
            return SizedBox(
              height: tileH,
              child: Row(
                children: [
                  for (var i = 0; i < _visible; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: LoadingShimmer(
                        width: double.infinity,
                        height: tileH,
                        borderRadius: const BorderRadius.all(
                            Radius.circular(WtmRadius.tile)),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }
          // The feed broke and nothing local can stand in → offer a retry.
          if (feed?.hasError ?? false) {
            return _InspirationNotice(
              message: l10n.wtmInspirationErrorMessage,
              ctaLabel: l10n.commonRetry,
              glyph: WtmGlyph.shield,
              onTap: () => ref.read(feedProvider.notifier).refresh(),
            );
          }
          return _InspirationNotice(
            message: l10n.wtmInspirationEmptyMessage,
            ctaLabel: l10n.wtmInspirationEmptyCta,
            glyph: WtmGlyph.sparkle,
            onTap: () => context.push(AppRoute.wtmMirror),
          );
        }

        return SizedBox(
          height: tileH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, i) {
              final tile = tiles[i];
              return Semantics(
                button: true,
                label: l10n.wtmInspiration,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: tile.onTap,
                    child: SizedBox(
                      width: tileW,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WtmRadius.tile),
                        child: CachedNetworkImage(
                          imageUrl: tile.url,
                          cacheKey: stableImageCacheKey(tile.url),
                          fit: BoxFit.cover,
                          // Decode at tile size, not full-res (mobile QA #1).
                          memCacheWidth: 480,
                          placeholder: (_, _) => const AuroraBox(
                            borderRadius: BorderRadius.all(
                                Radius.circular(WtmRadius.tile)),
                          ),
                          errorWidget: (_, _, _) => const AuroraBox(
                            borderRadius: BorderRadius.all(
                                Radius.circular(WtmRadius.tile)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Compact inspiration notice card (empty / error) with a single pill action.
class _InspirationNotice extends StatelessWidget {
  const _InspirationNotice({
    required this.message,
    required this.ctaLabel,
    required this.glyph,
    required this.onTap,
  });

  final String message;
  final String ctaLabel;
  final WtmGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: WtmType.sub),
          const SizedBox(height: WtmSpace.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: GoldPill(
              label: ctaLabel,
              icon: WtmIcon(glyph, size: 12, color: WtmColors.gold),
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
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
              horizontal: WtmSpace.s8,
              vertical: WtmSpace.s12,
            ),
            child: Text(
              label,
              style: WtmType.micro.copyWith(color: WtmColors.gold),
            ),
          ),
        ),
      ),
    );
  }
}
