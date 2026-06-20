import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/models/post.dart';
import '../../data/repositories/challenges_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/uuid.dart';
import '../../shared/widgets/widgets.dart';
import '../outfits/outfit_providers.dart';
import 'post_image_service.dart';
import 'social_providers.dart';

/// Optional context passed to the composer: a challenge to enter (§24) and/or a
/// preset photo (e.g. a 2D try-on preview the user wants to share).
class ComposeArgs {
  const ComposeArgs({
    this.challengeId,
    this.challengeTitle,
    this.presetPhoto,
    this.editPost,
  });

  final String? challengeId;
  final String? challengeTitle;
  final Uint8List? presetPhoto;

  /// When set, the composer opens in EDIT mode for this existing post
  /// (FEATURES_COMMUNITY_PLUS · Post Edit).
  final Post? editPost;
}

/// Share a look to the community (CLAUDE.md §1 pillar 4). The user can post ANY
/// photo (Facebook-style) OR one of their saved outfits, with a caption + tags.
/// The backend moderates the image + text before they go public (§19). When given
/// a challenge, the new post is also entered into it (§24).
class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({
    super.key,
    this.challengeId,
    this.challengeTitle,
    this.presetPhoto,
    this.editPost,
  });

  final String? challengeId;
  final String? challengeTitle;

  /// A photo to pre-fill (e.g. a 2D try-on preview shared via "Post to Community").
  final Uint8List? presetPhoto;

  /// When set, edit this existing post instead of creating a new one.
  final Post? editPost;

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  final _caption = TextEditingController();
  final _tagInput = TextEditingController();

  bool _useOutfit = false; // false = upload a photo, true = share an outfit
  late Uint8List? _photo = widget.presetPhoto; // picked/compressed bytes (photo mode)
  String? _selectedId; // selected outfit (outfit mode)
  String? _existingImageUrl; // current photo URL when editing (until replaced)
  final List<String> _tags = [];
  bool _sharing = false;

  // Optional attached poll (create mode only, flag-gated).
  bool _addPoll = false;
  final _pollQuestion = TextEditingController();
  final List<TextEditingController> _pollOptions = [
    TextEditingController(),
    TextEditingController(),
  ];

  /// Stable across retries of THIS composer so a re-tap / network retry replays
  /// the same create instead of duplicating the post (§9).
  final String _idempotencyKey = uuidV4();

  bool get _isEdit => widget.editPost != null;

  /// A poll, if enabled, needs a question + at least 2 non-blank options.
  bool get _pollValid {
    if (!_addPoll) return true;
    if (_pollQuestion.text.trim().isEmpty) return false;
    return _pollOptions.where((c) => c.text.trim().isNotEmpty).length >= 2;
  }

  @override
  void initState() {
    super.initState();
    // Edit mode: prefill the composer from the existing post (Post Edit).
    final post = widget.editPost;
    if (post != null) {
      _caption.text = post.caption ?? '';
      _tags.addAll(post.tags);
      if (post.outfitId != null) {
        _useOutfit = true;
        _selectedId = post.outfitId;
      } else {
        _existingImageUrl = post.imageUrl;
      }
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _tagInput.dispose();
    _pollQuestion.dispose();
    for (final c in _pollOptions) {
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

  bool get _canShare {
    final hasContent = _useOutfit
        ? _selectedId != null
        : (_photo != null || _existingImageUrl != null);
    return hasContent && _pollValid;
  }

  /// Unsaved work that should be confirmed before discarding (redesign spec —
  /// prevent accidental loss of caption/photo). In edit mode the post already
  /// has content, so any open composer counts as unsaved work.
  bool get _hasUnsavedContent =>
      _isEdit ||
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
        // Only re-upload when the user picked a NEW photo; otherwise keep the
        // existing image (edit mode).
        imageUrl = _photo != null
            ? await ref.read(postImageServiceProvider).upload(_photo!)
            : _existingImageUrl;
      }

      final caption = _caption.text.trim();

      // Edit mode: PATCH the existing post (re-moderated server-side) and stop.
      if (_isEdit) {
        await ref.read(socialRepositoryProvider).editPost(
              widget.editPost!.id,
              caption: caption.isEmpty ? null : caption,
              imageUrl: imageUrl,
              outfitId: outfitId,
              tags: _tags,
            );
        await ref.read(analyticsProvider).track(AnalyticsEvents.postEdited);
        await ref.read(feedProvider.notifier).refresh();
        if (mounted) {
          _snack(l10n.composeEditSaved);
          context.pop();
        }
        return;
      }

      // Build the attached poll, if enabled + valid (create mode only).
      Map<String, dynamic>? pollPayload;
      if (_addPoll && _pollValid) {
        pollPayload = {
          'question': _pollQuestion.text.trim(),
          'options': [
            for (final c in _pollOptions)
              if (c.text.trim().isNotEmpty) c.text.trim(),
          ],
        };
      }

      final post = await ref
          .read(socialRepositoryProvider)
          .createPost(
            caption: caption.isEmpty ? null : caption,
            imageUrl: imageUrl,
            outfitId: outfitId,
            tags: _tags,
            poll: pollPayload,
            idempotencyKey: _idempotencyKey,
          );
      await ref.read(analyticsProvider).track(AnalyticsEvents.postCreated);
      if (pollPayload != null) {
        await ref.read(analyticsProvider).track(AnalyticsEvents.pollCreated);
      }
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
    // Polls attach only on NEW posts, and only when the feature is enabled (§16).
    final pollsEnabled =
        !_isEdit && ref.watch(featureEnabledProvider(FeatureFlags.postPolls));

    return PopScope(
      canPop: !_hasUnsavedContent,
      onPopInvokedWithResult: (didPop, _) => _confirmDiscard(didPop),
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.composeEditTitle : l10n.composeTitle),
      ),
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
                      existingImageUrl: _existingImageUrl,
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
                  if (pollsEnabled) ...[
                    const SizedBox(height: AppSpace.lg),
                    _PollComposer(
                      enabled: _addPoll,
                      question: _pollQuestion,
                      options: _pollOptions,
                      onToggle: (v) => setState(() => _addPoll = v),
                      onAddOption: _pollOptions.length < 4
                          ? () => setState(
                              () => _pollOptions.add(TextEditingController()))
                          : null,
                      onRemoveOption: _pollOptions.length > 2
                          ? (i) => setState(() => _pollOptions.removeAt(i).dispose())
                          : null,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Explain WHY Share is disabled when a poll is half-filled —
                    // never silently grey it out (Issue 1).
                    if (_addPoll && !_pollValid) ...[
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppColors.graphite),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              l10n.composePollIncomplete,
                              style: text.bodySmall
                                  ?.copyWith(color: AppColors.graphite),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                    ],
                    PrimaryButton(
                      label:
                          _isEdit ? l10n.composeSaveChanges : l10n.composeShare,
                      icon: _isEdit ? Icons.check_rounded : Icons.send_rounded,
                      isLoading: _sharing,
                      onPressed: _canShare ? () => _share(outfitList) : null,
                    ),
                  ],
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
    this.existingImageUrl,
  });

  final Uint8List? photo;

  /// The post's current photo (edit mode) — shown until the user picks a new one.
  final String? existingImageUrl;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  Widget _preview() {
    if (photo != null) return Image.memory(photo!, fit: BoxFit.cover);
    if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: existingImageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
      );
    }
    return const ColoredBox(
      color: AppColors.accentSoft,
      child: Center(
        child: Icon(Icons.image_outlined, size: 48, color: AppColors.accent),
      ),
    );
  }

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
                child: _preview(),
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

/// Optional poll attachment in the composer: a toggle, a question, and 2–4
/// option fields (FEATURES_COMMUNITY_PLUS · Poll).
class _PollComposer extends StatelessWidget {
  const _PollComposer({
    required this.enabled,
    required this.question,
    required this.options,
    required this.onToggle,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onChanged,
  });

  final bool enabled;
  final TextEditingController question;
  final List<TextEditingController> options;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onAddOption;
  final void Function(int index)? onRemoveOption;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.poll_outlined),
          title: Text(l10n.composeAddPoll),
          value: enabled,
          onChanged: onToggle,
        ),
        if (enabled) ...[
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: question,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: l10n.composePollQuestion,
              hintText: l10n.composePollQuestionHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < options.length; i++) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: options[i],
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: l10n.composePollOption(i + 1),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (onRemoveOption != null)
                  IconButton(
                    onPressed: () => onRemoveOption!(i),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          if (onAddOption != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddOption,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.composePollAddOption),
              ),
            ),
        ],
      ],
    );
  }
}
