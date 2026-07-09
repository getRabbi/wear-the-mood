import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../../ui/widgets/widgets.dart';
import '../social/post_image_service.dart';

/// Create a giveaway listing (FEATURES_COMMUNITY_PLUS · Giveaway), rebuilt in the
/// WTM Atelier style. Optionally prefilled from a wardrobe item ("Give it away").
/// The safety notice is always shown; images + text are moderated server-side
/// before publish. Backend behaviour is unchanged — only the UI is upgraded.
class CreateGiveawayScreen extends ConsumerStatefulWidget {
  const CreateGiveawayScreen({super.key, this.item});

  /// When launched from the closet, the item to prefill from.
  final WardrobeItem? item;

  @override
  ConsumerState<CreateGiveawayScreen> createState() =>
      _CreateGiveawayScreenState();
}

class _CreateGiveawayScreenState extends ConsumerState<CreateGiveawayScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _size = TextEditingController();
  final _category = TextEditingController();
  final _condition = TextEditingController();
  final _area = TextEditingController();
  final List<String> _images = [];
  bool _uploading = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _title.text = item.title ?? '';
      _category.text = item.category ?? '';
      final url = item.displayImageUrl;
      if (url != null && url.isNotEmpty) _images.add(url);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _size, _category, _condition, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    if (_images.length >= 6) return;
    setState(() => _uploading = true);
    try {
      final bytes =
          await ref.read(postImageServiceProvider).pickAndCompress(source);
      if (bytes == null) return;
      final url = await ref.read(postImageServiceProvider).upload(bytes);
      if (mounted) setState(() => _images.add(url));
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.addItemPickError);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: WtmColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(WtmRadius.sheetTop)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: WtmSpace.s8),
            ListTile(
              leading: const WtmIcon(WtmGlyph.camera,
                  size: 18, color: WtmColors.gold),
              title: Text(l10n.addItemCamera, style: WtmType.body),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const WtmIcon(WtmGlyph.image,
                  size: 18, color: WtmColors.gold),
              title: Text(l10n.addItemGallery, style: WtmType.body),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: WtmSpace.s8),
          ],
        ),
      ),
    );
    if (source != null) await _addPhoto(source);
  }

  bool get _canPublish => _title.text.trim().isNotEmpty && !_publishing;

  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context);
    if (!_canPublish) return;
    setState(() => _publishing = true);
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(giveawayRepositoryProvider).create(
            title: _title.text.trim(),
            description: text(_description),
            images: _images,
            size: text(_size),
            category: text(_category),
            condition: text(_condition),
            areaLabel: text(_area),
            wardrobeItemId: widget.item?.id,
          );
      await ref.read(analyticsProvider).track(AnalyticsEvents.giveawayListed);
      ref.invalidate(giveawayBrowseProvider);
      ref.invalidate(myGiveawaysProvider);
      if (mounted) {
        wtmSnack(context, l10n.giveawayPublished);
        context.pop();
      }
    } on ApiException catch (error) {
      if (mounted) {
        wtmSnack(
          context,
          error.code == ApiErrorCode.moderationBlocked
              ? l10n.composeBlocked
              : l10n.giveawayPublishError,
        );
      }
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.giveawayPublishError);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      fullBleed: true,
      title: l10n.giveawayCreateTitle,
      eyebrow: l10n.wtmGiveawaysTitle,
      footer: GradientCta(
        label: l10n.giveawayPublish,
        icon: const WtmIcon(WtmGlyph.gift, size: 15, color: WtmColors.ctaText),
        onPressed: _canPublish ? _publish : null,
      ),
      children: [
        // Gold P2P safety notice (§10) — WTM styled.
        _SafetyNotice(text: l10n.giveawayDisclaimer),
        const SizedBox(height: WtmSpace.s16),

        // Photos.
        _label(l10n.giveawayAddPhoto),
        const SizedBox(height: WtmSpace.s8),
        _PhotoRow(
          images: _images,
          uploading: _uploading,
          onAdd: _pickSource,
          onRemove: (i) => setState(() => _images.removeAt(i)),
        ),
        const SizedBox(height: WtmSpace.s16),

        _field(l10n.giveawayFieldTitle, _title, onChanged: (_) => setState(() {})),
        const SizedBox(height: WtmSpace.s14),
        _field(l10n.giveawayFieldDescription, _description, maxLines: 3),
        const SizedBox(height: WtmSpace.s14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(l10n.giveawayFieldSize, _size)),
            const SizedBox(width: WtmSpace.s12),
            Expanded(child: _field(l10n.giveawayFieldCategory, _category)),
          ],
        ),
        const SizedBox(height: WtmSpace.s14),
        _field(l10n.giveawayFieldCondition, _condition),
        const SizedBox(height: WtmSpace.s14),
        _field(l10n.giveawayFieldArea, _area),
        const SizedBox(height: WtmSpace.s12),
        Text(l10n.giveawayPrivacyNote, style: WtmType.micro),
      ],
    );
  }

  Widget _label(String text) =>
      Text(text, style: WtmType.label.copyWith(color: WtmColors.muted));

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: WtmSpace.s8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: WtmType.body,
          cursorColor: WtmColors.gold,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: WtmColors.panel,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: WtmSpace.s12, vertical: WtmSpace.s12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.gold),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gold-bordered P2P safety notice (board §10 — keep contact in-app, meet safe).
class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        color: WtmColors.pillBg,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WtmIcon(WtmGlyph.shield, size: 16, color: WtmColors.gold),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Text(text, style: WtmType.micro.copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.images,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> images;
  final bool uploading;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  static const _size = 92.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: _size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < images.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: WtmSpace.s10),
              child: SizedBox(
                width: _size,
                height: _size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                      child: CachedNetworkImage(
                        imageUrl: images[i],
                        cacheKey: stableImageCacheKey(images[i]),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const AuroraBox(),
                        errorWidget: (_, _, _) => const AuroraBox(),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xCC000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (images.length < 6)
            GestureDetector(
              onTap: uploading ? null : onAdd,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: WtmColors.panel,
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  border: Border.all(color: WtmColors.line),
                ),
                child: Center(
                  child: uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: WtmColors.gold),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const WtmIcon(WtmGlyph.camera,
                                size: 20, color: WtmColors.gold),
                            const SizedBox(height: WtmSpace.s6),
                            Text(l10n.giveawayAddPhoto, style: WtmType.micro),
                          ],
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
