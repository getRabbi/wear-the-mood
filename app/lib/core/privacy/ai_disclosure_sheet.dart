import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../../ui/widgets/widgets.dart';
import '../legal/legal_links.dart';

/// What the user chose in the disclosure sheet.
enum AiDisclosureChoice {
  /// Explicit, affirmative permission. The ONLY value that may lead to sharing.
  allow,

  /// Declined, dismissed by the back gesture, or tapped outside. All three are
  /// the same answer — silence is never consent, so the sheet has no outcome
  /// that means "allowed" other than pressing the button that says so.
  notNow,
}

/// The just-in-time disclosure shown immediately before the first transmission
/// of a personal photo to a third-party AI provider (Apple 5.1.1(i), §10).
///
/// Compact by design. A full-screen legal wall gets scrolled past; what a user
/// has to be able to answer is who receives their photo and why, and that fits
/// in a sheet they can read in one glance. The Privacy Policy is one tap away
/// for the detail, and nothing important is available ONLY behind that tap.
Future<AiDisclosureChoice> showAiDisclosureSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<AiDisclosureChoice>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    // Dismissible on purpose: a permission prompt the user cannot escape is a
    // dark pattern. Every escape route resolves to `notNow` below.
    isDismissible: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => const _AiDisclosureSheet(),
  );
  // A null result is a dismissal (back gesture, scrim tap, swipe down).
  return choice ?? AiDisclosureChoice.notNow;
}

class _AiDisclosureSheet extends StatelessWidget {
  const _AiDisclosureSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Tall text (large Dynamic Type) scrolls inside the sheet instead of
        // overflowing; on a short screen the actions stay reachable.
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            WtmSpace.s18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle — decorative only, so it is hidden from VoiceOver.
              ExcludeSemantics(
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: WtmColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WtmSpace.s16),
              Semantics(
                header: true,
                child: Text(
                  l10n.aiDisclosureTitle,
                  textAlign: TextAlign.center,
                  style: WtmType.h1.copyWith(fontSize: 21),
                ),
              ),
              const SizedBox(height: WtmSpace.s12),
              Text(
                l10n.aiDisclosureBodyWhat,
                textAlign: TextAlign.center,
                style: WtmType.body,
              ),
              const SizedBox(height: WtmSpace.s10),
              Text(
                l10n.aiDisclosureBodyUse,
                textAlign: TextAlign.center,
                style: WtmType.body,
              ),
              const SizedBox(height: WtmSpace.s10),
              Text(
                l10n.aiDisclosureBodyChoice,
                textAlign: TextAlign.center,
                style: WtmType.sub,
              ),
              const SizedBox(height: WtmSpace.s16),
              // Primary action. Never pre-selected, never disabled — a consent
              // button that looks unavailable reads as a wall rather than a
              // choice.
              GradientCta(
                label: l10n.aiDisclosureAllow,
                onPressed: () =>
                    Navigator.of(context).pop(AiDisclosureChoice.allow),
              ),
              const SizedBox(height: 9),
              GhostButton(
                label: l10n.aiDisclosureNotNow,
                onPressed: () =>
                    Navigator.of(context).pop(AiDisclosureChoice.notNow),
              ),
              const SizedBox(height: WtmSpace.s12),
              // Visually secondary, but a real 48dp target rather than fine
              // print. Opens externally so the sheet's own state is untouched.
              Semantics(
                link: true,
                child: Center(
                  child: TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(LegalLinks.privacy),
                      mode: LaunchMode.externalApplication,
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: WtmColors.gold,
                    ),
                    child: Text(
                      l10n.aiDisclosurePrivacyPolicy,
                      style: WtmType.micro.copyWith(
                        color: WtmColors.gold,
                        decoration: TextDecoration.underline,
                        decorationColor: WtmColors.gold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
