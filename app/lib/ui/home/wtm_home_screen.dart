import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/env/app_env.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
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
/// [wtmMoodProvider] and re-seeds Today's Look zone/name/swatches live; the
/// AI Stylist reads the same value (context wiring completes in P5, weather
/// temp is a placeholder until then). Inspiration tiles are the designed
/// aurora placeholders until community imagery lands (P8).
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
          Row(
            children: [
              for (final (i, tile) in const [
                (AuroraVariant.noir, false),
                (AuroraVariant.blush, false),
                (AuroraVariant.noir, true),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: WtmSpace.s8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: l10n.wtmInspiration,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        onTap: () => context.push(AppRoute.wtmPost),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: AuroraBox(
                            variant: tile.$1,
                            child: tile.$2
                                ? const Center(
                                    child: SizedBox(
                                      width: 40,
                                      height: 66,
                                      child: WtmFigure(
                                        WtmFigureKind.form,
                                        opacity: 0.45,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

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

/// Today's Look hero card — zone-seeded name + swatches; taps into the
/// stylist look detail (§8).
class _TodaysLookCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    return Semantics(
      button: true,
      label: '${l10n.wtmTodaysLook}. $nameA $nameB',
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
                    AuroraBox(
                      width: 56,
                      height: 70,
                      child: const Center(
                        child: SizedBox(
                          width: 34,
                          height: 56,
                          child: WtmFigure(
                            WtmFigureKind.form,
                            opacity: 0.55,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: WtmSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EyebrowLabel(l10n.wtmTodaysLook),
                          const SizedBox(height: 5),
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
                    for (final (i, swatch)
                        in _zoneSwatches[zone]!.indexed) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: FabricTile(swatchIndex: swatch, radius: 9),
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
