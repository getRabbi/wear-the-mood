import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';

/// The one interactive module on Discover (prototype `.daily-pulse`).
///
/// It sets today's mood, which is the app's existing personalization
/// primitive: the same value the Home slider writes, the one Today's Look and
/// the AI Stylist read, and the one the Discover header's subtitle names. So
/// the choice does something real and visible, and the copy says exactly what
/// that is — no invented promise about tomorrow's ranking, which the app does
/// not yet do (§26.10, §35 "never masquerade").
///
/// No new storage and no new event: this writes through
/// [wtmMoodProvider] to the existing secure-storage repository.
class WtmDailyPulse extends ConsumerWidget {
  const WtmDailyPulse({super.key});

  /// The centre of each mood zone, so tapping a chip lands the slider squarely
  /// inside that zone rather than on a boundary.
  static const _centres = <WtmMoodZone, double>{
    WtmMoodZone.calm: 0.12,
    WtmMoodZone.confident: 0.36,
    WtmMoodZone.bold: 0.62,
    WtmMoodZone.rebel: 0.88,
  };

  Future<void> _choose(WidgetRef ref, WtmMoodZone zone) async {
    await ref.read(wtmMoodProvider.notifier).commit(_centres[zone]!);
    // The header subtitle reads the STORED mood — the one that answers "has
    // this user ever picked?" — so it has to be re-read for the line above to
    // agree with the chip the user just tapped.
    ref.invalidate(wtmStoredMoodProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The live value, not the stored one: an untouched install still has a
    // resting position, and showing no selection at all would read as broken.
    final selected = WtmMoodZone.of(ref.watch(wtmMoodProvider));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(WtmSpace.s14),
        decoration: BoxDecoration(
          gradient: WtmGradients.assistFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.wtmDiscoverPulseTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WtmType.labelMedium,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.wtmDiscoverPulseSubtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WtmType.micro,
            ),
            const SizedBox(height: WtmSpace.s12),
            // A Wrap, not a Row: four chips plus a large text scale would
            // overflow a 320dp phone, and a horizontal scroller would hide
            // choices behind a gesture nobody knows is there.
            Wrap(
              spacing: WtmSpace.s8,
              runSpacing: WtmSpace.s8,
              children: [
                for (final zone in WtmMoodZone.values)
                  WtmChip(
                    label: zone.label(l10n),
                    on: zone == selected,
                    onTap: () => _choose(ref, zone),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
