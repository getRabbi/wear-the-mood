import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../social/post_image_service.dart';
import 'giveaway_disclaimer.dart';

/// Create a giveaway listing (FEATURES_COMMUNITY_PLUS · Giveaway). Optionally
/// prefilled from a wardrobe item ("Give it away"). The safety disclaimer is
/// always shown; images + text are moderated server-side before publish.
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      _snack(l10n.addItemPickError);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
        _snack(l10n.giveawayPublished);
        context.pop();
      }
    } on ApiException catch (error) {
      _snack(
        error.code == ApiErrorCode.moderationBlocked
            ? l10n.composeBlocked
            : l10n.giveawayPublishError,
      );
    } catch (_) {
      _snack(l10n.giveawayPublishError);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.giveawayCreateTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  const GiveawayDisclaimer(),
                  const SizedBox(height: AppSpace.lg),
                  _PhotoRow(
                    images: _images,
                    uploading: _uploading,
                    onAdd: _addPhoto,
                    onRemove: (i) => setState(() => _images.removeAt(i)),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _field(_title, l10n.giveawayFieldTitle, onChanged: () => setState(() {})),
                  const SizedBox(height: AppSpace.md),
                  _field(_description, l10n.giveawayFieldDescription, maxLines: 3),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Expanded(child: _field(_size, l10n.giveawayFieldSize)),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: _field(_category, l10n.giveawayFieldCategory)),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  _field(_condition, l10n.giveawayFieldCondition),
                  const SizedBox(height: AppSpace.md),
                  _field(_area, l10n.giveawayFieldArea),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    l10n.giveawayPrivacyNote,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.graphite),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: PrimaryButton(
                  label: l10n.giveawayPublish,
                  icon: Icons.volunteer_activism_outlined,
                  isLoading: _publishing,
                  onPressed: _canPublish ? _publish : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    VoidCallback? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
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
  final void Function(ImageSource source) onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < images.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SmartImageCard(
                      imageUrl: images[i],
                      aspectRatio: 1,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: AppColors.scrim,
                        child: Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (images.length < 6)
            GestureDetector(
              onTap: uploading
                  ? null
                  : () => showModalBottomSheet<void>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.photo_camera_outlined),
                                title: Text(l10n.addItemCamera),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onAdd(ImageSource.camera);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.photo_library_outlined),
                                title: Text(l10n.addItemGallery),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onAdd(ImageSource.gallery);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: uploading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined,
                              color: AppColors.accent),
                          const SizedBox(height: 2),
                          Text(
                            l10n.giveawayAddPhoto,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.accent),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
