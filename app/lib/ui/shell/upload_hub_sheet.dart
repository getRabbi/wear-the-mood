import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Opens the Upload Hub (board screen 13) as a modal bottom sheet — the orb's
/// action (§2 LOCKED: the orb is the app's "+").
Future<void> showUploadHubSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: WtmColors.panel,
    // Size to content (scrolls on short screens) instead of the default
    // 9/16-height cap, which clips the five rows + assistant card.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => const UploadHubSheet(),
  );
}

/// Upload Hub content — five entries + the Atelier-assistant card, routing per
/// §2/§8: Add Garment · Body Photo · Outfit Maker (Save a Look) · Brand/Store ·
/// MoodMirror Step 1, and assistant → AI Stylist.
class UploadHubSheet extends StatelessWidget {
  const UploadHubSheet({super.key});

  void _go(BuildContext context, String path) {
    // Close the sheet, then route from the surviving navigator context.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
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
            Text(
              l10n.wtmUploadHubTitle,
              textAlign: TextAlign.center,
              style: WtmType.h1.copyWith(fontSize: 21),
            ),
            const SizedBox(height: WtmSpace.s6),
            Text(
              l10n.wtmUploadHubSubtitle,
              textAlign: TextAlign.center,
              style: WtmType.sub,
            ),
            const SizedBox(height: WtmSpace.s14),
            WtmRow(
              glyph: WtmGlyph.hanger,
              title: l10n.wtmUploadGarmentTitle,
              subtitle: l10n.wtmUploadGarmentSub,
              onTap: () => _go(context, AppRoute.wtmClosetAdd),
            ),
            const SizedBox(height: 9), // .row + .row
            WtmRow(
              glyph: WtmGlyph.camera,
              title: l10n.wtmUploadBodyTitle,
              subtitle: l10n.wtmUploadBodySub,
              onTap: () => _go(context, AppRoute.wtmBodyPhoto),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.image,
              title: l10n.wtmUploadLookTitle,
              subtitle: l10n.wtmUploadLookSub,
              onTap: () => _go(context, AppRoute.wtmOutfits),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.store,
              title: l10n.wtmUploadBrandTitle,
              subtitle: l10n.wtmUploadBrandSub,
              onTap: () => _go(context, AppRoute.wtmBrandStore),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.sparkle,
              title: l10n.wtmUploadTryonTitle,
              subtitle: l10n.wtmUploadTryonSub,
              onTap: () => _go(context, AppRoute.wtmMirror),
            ),
            const SizedBox(height: WtmSpace.s16),
            // Atelier assistant (board .assist) → AI Stylist (§8).
            Semantics(
              button: true,
              label: l10n.wtmAssistantEyebrow,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _go(context, AppRoute.wtmStylist),
                  child: Container(
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
                                l10n.wtmAssistantEyebrow,
                                color: WtmColors.assistEyebrow,
                              ),
                              const SizedBox(height: WtmSpace.s4),
                              Text(
                                l10n.wtmAssistantLine,
                                style: WtmType.body.copyWith(
                                  fontSize: 12,
                                  color: WtmColors.muted,
                                ),
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
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
