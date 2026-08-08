import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../home/wtm_mood.dart';

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

    final pad = DiscoverTokens.padFor(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Container(
        width: double.infinity,
        // `.daily-pulse { padding: 13px 14px }`
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: DiscoverTokens.pulseFill,
          borderRadius: BorderRadius.circular(DiscoverTokens.radiusPulse),
          border: Border.all(color: DiscoverTokens.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.wtmDiscoverPulseTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.pulseTitle,
            ),
            const SizedBox(height: 3), // .pulse-copy strong margin-bottom
            Text(
              l10n.wtmDiscoverPulseSubtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.pulseSub,
            ),
            const SizedBox(height: 12),
            // The prototype puts two choices beside the copy and stacks them
            // under it below 350px. Four real mood zones never fit beside the
            // copy at any phone width, so this always takes the stacked form —
            // the prototype's own narrow layout — rather than dropping two of
            // the user's moods to win a row.
            Wrap(
              spacing: 7, // .pulse-choices gap
              runSpacing: 7,
              children: [
                for (final zone in WtmMoodZone.values)
                  _Choice(
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

/// `.choice` — a hairline capsule that fills lilac when active.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: WtmMotion.fast,
            curve: WtmMotion.easing,
            // `.choice { padding: 8px 10px }`, opened out vertically so the
            // capsule still clears a comfortable tap target.
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? DiscoverTokens.choiceOnBg : DiscoverTokens.choiceBg,
              borderRadius: BorderRadius.circular(DiscoverTokens.pill),
              border: Border.all(
                color: on ? Colors.transparent : DiscoverTokens.line,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: DiscoverTokens.choice.copyWith(
                color: on ? DiscoverTokens.choiceOnText : DiscoverTokens.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
