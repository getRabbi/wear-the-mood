import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/social_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/social/social_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Create Post (board §3.12, P8) — share a saved Look to the community.
/// Pick one of your durable saved looks as the image, add a caption + tags,
/// and publish through the moderated [SocialRepository.createPost].
class WtmComposeScreen extends ConsumerStatefulWidget {
  const WtmComposeScreen({super.key});

  @override
  ConsumerState<WtmComposeScreen> createState() => _WtmComposeScreenState();
}

class _WtmComposeScreenState extends ConsumerState<WtmComposeScreen> {
  static const _suggested = ['#WearTheMood', '#ootd', '#style'];
  final _caption = TextEditingController();
  final _tags = <String>{'#WearTheMood'};
  int? _picked;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _publish(List<SavedLook> looks) async {
    final l10n = AppLocalizations.of(context);
    if (_picked == null) {
      wtmSnack(context, l10n.wtmComposePickFirst);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(socialRepositoryProvider).createPost(
            imageUrl: looks[_picked!].imageUrl,
            caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
            tags: [for (final t in _tags) t.replaceFirst('#', '')],
          );
      ref.read(feedProvider.notifier).refresh();
      if (mounted) {
        wtmSnack(context, l10n.wtmComposeDone);
        wtmPageBack(context);
      }
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.wtmComposeError);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmComposeError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final looks = ref.watch(savedLookRecordsProvider);

    return WtmPage(
      title: l10n.wtmComposeTitle,
      eyebrow: l10n.wtmComposeEyebrow,
      children: looks.isEmpty
          ? [
              const SizedBox(height: WtmSpace.s22),
              WtmEmptyState(
                glyph: WtmGlyph.sparkle,
                title: l10n.wtmComposeEmptyTitle,
                message: l10n.wtmComposeEmptyMessage,
                ctaLabel: l10n.wtmComposeEmptyCta,
                onCta: () => context.push(AppRoute.wtmMirror),
              ),
            ]
          : [
              EyebrowLabel(l10n.wtmComposePick),
              const SizedBox(height: WtmSpace.s10),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                childAspectRatio: 3 / 4,
                children: [
                  for (final (i, look) in looks.take(8).indexed)
                    _LookPick(
                      url: look.imageUrl,
                      selected: _picked == i,
                      onTap: () => setState(() => _picked = i),
                    ),
                ],
              ),
              const SizedBox(height: WtmSpace.s14),
              TextField(
                controller: _caption,
                maxLines: 3,
                maxLength: 400,
                style: WtmType.body,
                cursorColor: WtmColors.gold,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.wtmComposeCaption,
                  hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
                  filled: true,
                  fillColor: WtmColors.iconBtnBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.chipOnBorder),
                  ),
                ),
              ),
              const SizedBox(height: WtmSpace.s12),
              WtmChipRow(
                children: [
                  for (final tag in _suggested)
                    WtmChip(
                      label: tag,
                      on: _tags.contains(tag),
                      onTap: () => setState(() => _tags.contains(tag)
                          ? _tags.remove(tag)
                          : _tags.add(tag)),
                    ),
                ],
              ),
              const SizedBox(height: WtmSpace.s16),
              GradientCta(
                label: l10n.wtmComposePublish,
                icon: const WtmIcon(WtmGlyph.sparkle,
                    size: 15, color: WtmColors.ctaText),
                onPressed: _busy ? null : () => _publish(looks),
              ),
              const SizedBox(height: WtmSpace.s8),
              Text(l10n.wtmComposeModerationNote,
                  textAlign: TextAlign.center, style: WtmType.micro),
            ],
    );
  }
}

class _LookPick extends StatelessWidget {
  const _LookPick({
    required this.url,
    required this.selected,
    required this.onTap,
  });

  final String url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WtmRadius.tile),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: stableImageCacheKey(url),
              fit: BoxFit.cover,
              placeholder: (_, _) => const AuroraBox(
                borderRadius: BorderRadius.all(Radius.circular(WtmRadius.tile)),
              ),
              errorWidget: (_, _, _) => const AuroraBox(
                borderRadius: BorderRadius.all(Radius.circular(WtmRadius.tile)),
              ),
            ),
          ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WtmRadius.tile),
                border: Border.all(color: WtmColors.gold, width: 2),
              ),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.all(4),
              child: const WtmIcon(WtmGlyph.check, size: 14,
                  color: WtmColors.gold),
            ),
        ],
      ),
    );
  }
}
