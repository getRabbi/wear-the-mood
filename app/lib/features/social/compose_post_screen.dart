import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/repositories/challenges_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../outfits/outfit_providers.dart';
import 'post_image_service.dart';
import 'social_providers.dart';

/// Optional context passed to the composer when entering a challenge (§24): the
/// new post is linked to this challenge on success.
class ComposeArgs {
  const ComposeArgs({required this.challengeId, required this.challengeTitle});

  final String challengeId;
  final String challengeTitle;
}

/// Share a look to the community (CLAUDE.md §1 pillar 4). The user can post ANY
/// photo (Facebook-style) OR one of their saved outfits, with a caption + tags.
/// The backend moderates the image + text before they go public (§19). When given
/// a challenge, the new post is also entered into it (§24).
class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({super.key, this.challengeId, this.challengeTitle});

  final String? challengeId;
  final String? challengeTitle;

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  final _caption = TextEditingController();
  final _tagInput = TextEditingController();

  bool _useOutfit = false; // false = upload a photo, true = share an outfit
  Uint8List? _photo; // picked + compressed bytes (photo mode)
  String? _selectedId; // selected outfit (outfit mode)
  final List<String> _tags = [];
  bool _sharing = false;

  @override
  void dispose() {
    _caption.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref
          .read(postImageServiceProvider)
          .pickAndCompress(source);
      if (bytes != null && mounted) setState(() => _photo = bytes);
    } catch (_) {
      _snack(l10n.addItemPickError);
    }
  }

  void _addTag() {
    final raw = _tagInput.text.trim().replaceAll('#', '');
    if (raw.isEmpty) return;
    if (!_tags.contains(raw) && _tags.length < 10) {
      setState(() => _tags.add(raw));
    }
    _tagInput.clear();
  }

  bool get _canShare =>
      _useOutfit ? _selectedId != null : _photo != null;

  /// Unsaved work that should be confirmed before discarding (redesign spec —
  /// prevent accidental loss of caption/photo).
  bool get _hasUnsavedContent =>
      _caption.text.trim().isNotEmpty ||
      _photo != null ||
      _tags.isNotEmpty ||
      _selectedId != null;

  Future<void> _confirmDiscard(bool didPop) async {
    if (didPop) return;
    final l10n = AppLocalizations.of(context);
    final discard = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.composeDiscardTitle,
      message: l10n.composeDiscardBody,
      confirmLabel: l10n.composeDiscardConfirm,
      cancelLabel: l10n.composeKeepEditing,
      destructive: true,
    );
    if (discard && mounted) context.pop();
  }

  Future<void> _share(List<Outfit> outfits) async {
    if (_sharing || !_canShare) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sharing = true);
    try {
      String? imageUrl;
      String? outfitId;
      if (_useOutfit) {
        final outfit = outfits.firstWhere((o) => o.id == _selectedId);
        imageUrl = outfit.coverImageUrl;
        outfitId = outfit.id;
      } else {
        imageUrl = await ref.read(postImageServiceProvider).upload(_photo!);
      }

      final caption = _caption.text.trim();
      final post = await ref
          .read(socialRepositoryProvider)
          .createPost(
            caption: caption.isEmpty ? null : caption,
            imageUrl: imageUrl,
            outfitId: outfitId,
            tags: _tags,
          );
      await ref.read(analyticsProvider).track(AnalyticsEvents.postCreated);
      await ref.read(feedProvider.notifier).refresh();

      final challengeId = widget.challengeId;
      if (challengeId != null) {
        await ref.read(challengesRepositoryProvider).join(challengeId, post.id);
        await ref.read(analyticsProvider).track(AnalyticsEvents.challengeJoined);
      }
      if (mounted) {
        _snack(challengeId != null ? l10n.challengeJoined : l10n.composeShared);
        context.pop();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      _snack(
        error.code == ApiErrorCode.moderationBlocked
            ? l10n.composeBlocked
            : widget.challengeId != null
            ? l10n.challengeJoinError
            : l10n.composeError,
      );
    } catch (_) {
      _snack(l10n.composeError);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final outfits = ref.watch(outfitsProvider);
    final outfitList = outfits.asData?.value ?? const <Outfit>[];

    return PopScope(
      canPop: !_hasUnsavedContent,
      onPopInvokedWithResult: (didPop, _) => _confirmDiscard(didPop),
      child: Scaffold(
      appBar: AppBar(title: Text(l10n.composeTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  if (widget.challengeTitle != null) ...[
                    Text(
                      l10n.composeEnterHeading(widget.challengeTitle!),
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  // Source: upload a photo OR share a saved outfit.
                  Center(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(l10n.composeSourcePhoto),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.style_outlined),
                          label: Text(l10n.composeSourceOutfit),
                        ),
                      ],
                      selected: {_useOutfit},
                      onSelectionChanged: (s) =>
                          setState(() => _useOutfit = s.first),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),

                  if (_useOutfit)
                    _OutfitSection(
                      outfits: outfits,
                      selectedId: _selectedId,
                      onSelect: (id) => setState(() => _selectedId = id),
                    )
                  else
                    _PhotoSection(
                      photo: _photo,
                      onCamera: () => _pickPhoto(ImageSource.camera),
                      onGallery: () => _pickPhoto(ImageSource.gallery),
                    ),

                  const SizedBox(height: AppSpace.lg),
                  TextField(
                    controller: _caption,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      labelText: l10n.composeCaptionLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _TagsField(
                    controller: _tagInput,
                    tags: _tags,
                    onAdd: _addTag,
                    onRemove: (t) => setState(() => _tags.remove(t)),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: PrimaryButton(
                  label: l10n.composeShare,
                  icon: Icons.send_rounded,
                  isLoading: _sharing,
                  onPressed: _canShare ? () => _share(outfitList) : null,
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

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photo,
    required this.onCamera,
    required this.onGallery,
  });

  final Uint8List? photo;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: photo == null
                    ? const ColoredBox(
                        color: AppColors.accentSoft,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 48,
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    : Image.memory(photo!, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.addItemCamera),
            ),
            OutlinedButton.icon(
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.addItemGallery),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutfitSection extends StatelessWidget {
  const _OutfitSection({
    required this.outfits,
    required this.selectedId,
    required this.onSelect,
  });

  final AsyncValue<List<Outfit>> outfits;
  final String? selectedId;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return outfits.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Text(l10n.composeError, style: text.bodySmall),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.style_outlined,
              title: l10n.composeNoOutfitsTitle,
              message: l10n.composeNoOutfits,
              actionLabel: l10n.outfitsCreate,
              onAction: () => context.push(AppRoute.outfitsCreate),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.composePickOutfit, style: text.titleMedium),
                const SizedBox(height: AppSpace.md),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: AppSpace.md,
                        crossAxisSpacing: AppSpace.md,
                        childAspectRatio: 0.66,
                      ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final outfit = list[i];
                    final name = (outfit.name?.trim().isNotEmpty ?? false)
                        ? outfit.name!.trim()
                        : l10n.outfitsUntitled;
                    final isSelected = outfit.id == selectedId;
                    return Stack(
                      children: [
                        OutfitTile(
                          imageUrl: outfit.coverImageUrl ?? '',
                          label: name,
                          onTap: () => onSelect(outfit.id),
                        ),
                        if (isSelected)
                          Positioned(
                            top: AppSpace.sm,
                            right: AppSpace.sm,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(AppSpace.xs),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _TagsField extends StatelessWidget {
  const _TagsField({
    required this.controller,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final TextEditingController controller;
  final List<String> tags;
  final VoidCallback onAdd;
  final void Function(String tag) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                decoration: InputDecoration(
                  labelText: l10n.composeTagsLabel,
                  hintText: l10n.composeTagsHint,
                  prefixText: '#',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            IconButton.filledTonal(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              for (final t in tags)
                Chip(
                  label: Text('#$t'),
                  onDeleted: () => onRemove(t),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
