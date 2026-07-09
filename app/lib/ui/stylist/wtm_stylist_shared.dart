import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/env/app_env.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';

/// Serif look name with the LAST word in gold italic (board LookCard / Today's
/// Look convention — e.g. "Moonlit *Confidence*").
Widget wtmLookTitle(String title, {double size = 18}) {
  final words = title.trim().split(RegExp(r'\s+'));
  final base = WtmType.h2.copyWith(fontSize: size);
  if (words.length < 2) {
    return Text(title, style: WtmType.goldItalic(base), maxLines: 2,
        overflow: TextOverflow.ellipsis);
  }
  final head = words.sublist(0, words.length - 1).join(' ');
  return Text.rich(
    TextSpan(
      text: '$head ',
      style: base,
      children: [
        TextSpan(text: words.last, style: WtmType.goldItalic(base)),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

/// Time-of-day greeting word (shared with Home).
String wtmHello(AppLocalizations l10n) => switch (DateTime.now().hour) {
      < 12 => l10n.homeHelloMorning,
      < 17 => l10n.homeHelloAfternoon,
      _ => l10n.homeHelloEvening,
    };

/// Daypart word for context lines.
String wtmDaypart(AppLocalizations l10n) => switch (DateTime.now().hour) {
      < 12 => l10n.wtmDaypartMorning,
      < 17 => l10n.wtmDaypartAfternoon,
      _ => l10n.wtmDaypartEvening,
    };

String wtmMoodZoneLabel(AppLocalizations l10n, WtmMoodZone zone) =>
    switch (zone) {
      WtmMoodZone.calm => l10n.wtmMoodCalm,
      WtmMoodZone.confident => l10n.wtmMoodConfident,
      WtmMoodZone.bold => l10n.wtmMoodBold,
      WtmMoodZone.rebel => l10n.wtmMoodRebel,
    };

/// Board `.assist` header — mini orb + "Your stylist" eyebrow + serif greeting
/// with the signed-in first name in gold italic (greeting-only for guests /
/// tests, where Supabase isn't configured).
class WtmStylistGreeting extends ConsumerWidget {
  const WtmStylistGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hello = wtmHello(l10n);
    // Supabase-backed providers assert without env config — same guard the app
    // root and Home use.
    final signedIn =
        AppEnv.hasSupabaseConfig && ref.watch(signedInEmailProvider) != null;
    final name = signedIn
        ? ref.watch(profileProvider).asData?.value.displayName?.trim()
        : null;
    final firstName =
        (name == null || name.isEmpty) ? null : name.split(RegExp(r'\s+')).first;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: WtmGradients.assistFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WtmColors.assistBorder),
      ),
      child: Row(
        children: [
          const TheOrb(size: TheOrb.miniSize),
          const SizedBox(width: WtmSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EyebrowLabel(
                  l10n.wtmStylistYourStylist,
                  color: WtmColors.assistEyebrow,
                ),
                const SizedBox(height: 4),
                if (firstName == null)
                  Text(hello, style: WtmType.h2)
                else
                  Text.rich(
                    TextSpan(
                      text: '$hello, ',
                      style: WtmType.h2,
                      children: [
                        TextSpan(
                          text: firstName,
                          style: WtmType.goldItalic(WtmType.h2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mood · daypart · weather context chips (board §3.18) — INTERACTIVE
/// (mobile QA #3): the mood chip opens the live mood slider sheet (retunes the
/// stylist immediately), the daypart/weather chips open the styling-context
/// sheet, which is honest that weather is estimated until it's wired live.
class WtmStylistContextChips extends ConsumerWidget {
  const WtmStylistContextChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zone = WtmMoodZone.of(ref.watch(wtmMoodProvider));
    return WtmChipRow(
      children: [
        WtmChip(
          label: l10n.wtmStylistMoodChip(wtmMoodZoneLabel(l10n, zone)),
          on: true,
          onTap: () => _showMoodSheet(context, ref),
        ),
        WtmChip(
          label: wtmDaypart(l10n),
          onTap: () => _showContextSheet(context),
        ),
        WtmChip(
          label: l10n.wtmStylistWeather,
          onTap: () => _showContextSheet(context),
        ),
      ],
    );
  }

  /// The live mood slider in a WTM sheet — same [wtmMoodProvider] the Home
  /// slider drives, so the stylist context retunes on release.
  Future<void> _showMoodSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showWtmSheet(
      context,
      title: l10n.wtmStylistMoodSheetTitle,
      subtitle: l10n.wtmStylistMoodSheetNote,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final mood = ref.watch(wtmMoodProvider);
            final zone = WtmMoodZone.of(mood);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WtmSlider(
                  value: mood,
                  onChanged: ref.read(wtmMoodProvider.notifier).preview,
                  onChangeEnd: ref.read(wtmMoodProvider.notifier).commit,
                  fill: false,
                  height: 4,
                  semanticLabel: l10n.wtmMoodEyebrow,
                  trackGradient: const LinearGradient(
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
                        wtmMoodZoneLabel(l10n, z),
                        style: z == zone
                            ? WtmType.micro.copyWith(color: WtmColors.gold)
                            : WtmType.micro,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// What the stylist is styling around right now — daypart is real (device
  /// clock); weather is honestly labeled as estimated until wired live.
  Future<void> _showContextSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showWtmSheet(
      context,
      title: l10n.wtmStylistContextTitle,
      subtitle: l10n.wtmStylistContextBody,
      children: [
        WtmRow(
          glyph: WtmGlyph.sparkle,
          title: l10n.wtmStylistContextDaypart,
          trailing: Text(wtmDaypart(l10n),
              style: WtmType.micro.copyWith(color: WtmColors.gold)),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.image,
          title: l10n.wtmStylistContextWeather,
          trailing: Text(l10n.wtmStylistWeather,
              style: WtmType.micro.copyWith(color: WtmColors.gold)),
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          l10n.wtmStylistContextWeatherNote,
          textAlign: TextAlign.center,
          style: WtmType.micro.copyWith(height: 1.5),
        ),
      ],
    );
  }
}
