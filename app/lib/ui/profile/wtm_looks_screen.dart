import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/collections/local_collections.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../widgets/widgets.dart';

/// Saved Looks gallery (board §3.6, P7) — the durable try-on renders saved from
/// the Result screen ([savedLookRecordsProvider]). A tile opens the look
/// full-screen (zoomable). Empty → an invitation to run the mirror.
class WtmLooksScreen extends ConsumerWidget {
  const WtmLooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final looks = ref.watch(savedLookRecordsProvider);

    return WtmPage(
      title: l10n.wtmLooksTitle,
      eyebrow: l10n.wtmLooksEyebrow,
      children: [
        if (looks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WtmSpace.s22),
            child: WtmEmptyState(
              glyph: WtmGlyph.sparkle,
              title: l10n.wtmLooksEmptyTitle,
              message: l10n.wtmLooksEmptyMessage,
              ctaLabel: l10n.wtmLooksEmptyCta,
              onCta: () => context.push(AppRoute.wtmMirror),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 3 / 4,
            children: [
              for (final look in looks)
                Semantics(
                  button: true,
                  label: l10n.wtmLooksView,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onTap: () => _view(context, look.imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WtmRadius.tile),
                        child: CachedNetworkImage(
                          imageUrl: look.imageUrl,
                          cacheKey: stableImageCacheKey(look.imageUrl),
                          fit: BoxFit.cover,
                          // 3-across grid — cap the decode (mobile QA #1).
                          memCacheWidth: 480,
                          placeholder: (_, _) => const AuroraBox(
                            borderRadius:
                                BorderRadius.all(Radius.circular(WtmRadius.tile)),
                          ),
                          errorWidget: (_, _, _) => const AuroraBox(
                            borderRadius:
                                BorderRadius.all(Radius.circular(WtmRadius.tile)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  void _view(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xF2050308),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: url,
                cacheKey: stableImageCacheKey(url),
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Center(
                  child: WtmIcon(WtmGlyph.sparkle,
                      size: 40, color: WtmColors.faint),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(WtmSpace.screenH),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: WtmIconButton(
                    WtmGlyph.back,
                    semanticLabel: MaterialLocalizations.of(dialogContext)
                        .backButtonTooltip,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
            // Share Look → Create Post prefilled with this render. Pops with
            // the dialog's context, routes with the screen's (still mounted).
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(WtmSpace.screenH),
                  child: GoldPill(
                    label: AppLocalizations.of(dialogContext).wtmShareLook,
                    icon: const WtmIcon(WtmGlyph.users,
                        size: 12, color: WtmColors.gold),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      context.push(
                        AppRoute.wtmCompose,
                        extra: WtmComposeArgs(imageUrl: url),
                      );
                    },
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
