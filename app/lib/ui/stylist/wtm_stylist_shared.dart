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

/// The mood · daypart · weather context chips (board §3.18). Weather is a
/// placeholder line until the stylist request wires coordinates.
class WtmStylistContextChips extends ConsumerWidget {
  const WtmStylistContextChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zone = WtmMoodZone.of(ref.watch(wtmMoodProvider));
    return WtmChipRow(
      children: [
        WtmChip(label: l10n.wtmStylistMoodChip(wtmMoodZoneLabel(l10n, zone)),
            on: true),
        WtmChip(label: wtmDaypart(l10n)),
        WtmChip(label: l10n.wtmStylistWeather),
      ],
    );
  }
}
