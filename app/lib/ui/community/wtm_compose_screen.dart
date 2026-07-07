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
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/social_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/social/post_image_service.dart';
import '../../features/social/social_providers.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/utils/uuid.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Prefill passed by "Share Look" entry points (outfit detail, saved-look
/// viewer, garment detail): the image to share and, for outfits, the outfit id
/// so the post links back to it.
class WtmComposeArgs {
  const WtmComposeArgs({this.imageUrl, this.outfitId});

  final String? imageUrl;
  final String? outfitId;

  bool get hasContent => imageUrl != null || outfitId != null;
}

/// What kind of post is being written (board §3.12 + mobile QA follow-up):
/// a look/image post, a text-only post, or a poll.
enum _ComposeMode { look, text, poll }

/// Where the look-post image is being picked from (mobile QA #2 — the full
/// closet, saved outfits, and saved looks; gallery/camera picks live beside).
enum _MediaSource { closet, outfits, looks }

/// The picked media for a look post — a closet/outfit/look image URL, an
/// outfit reference, or freshly picked photo bytes (gallery/camera).
class _Selection {
  const _Selection({
    required this.key,
    this.imageUrl,
    this.outfitId,
    this.bytes,
  });

  /// Unique tile identity (`shared`, `photo`, `item:id`, `look:i`, `outfit:id`).
  final String key;
  final String? imageUrl;
  final String? outfitId;

  /// Compressed photo bytes when picked from gallery/camera — uploaded at
  /// publish time through the shipped [PostImageService].
  final Uint8List? bytes;
}

/// WTM Create Post (board §3.12, P8) — share to the community through the
/// moderated [SocialRepository.createPost]. Supports look/image posts (saved
/// looks AND saved outfits, prefillable via [WtmComposeArgs]), text-only
/// posts, and polls (flag-gated, mirroring the shipped composer §16). After
/// publishing it returns to Community and refreshes the feed.
class WtmComposeScreen extends ConsumerStatefulWidget {
  const WtmComposeScreen({super.key, this.args});

  final WtmComposeArgs? args;

  @override
  ConsumerState<WtmComposeScreen> createState() => _WtmComposeScreenState();
}

class _WtmComposeScreenState extends ConsumerState<WtmComposeScreen> {
  static const _suggested = ['#WearTheMood', '#ootd', '#style'];
  final _caption = TextEditingController();
  final _tags = <String>{'#WearTheMood'};
  _ComposeMode _mode = _ComposeMode.look;
  _Selection? _picked;
  bool _busy = false;

  // Poll draft (question + 2–4 options), same rules as the shipped composer.
  final _pollQuestion = TextEditingController();
  final List<TextEditingController> _pollOptions = [
    TextEditingController(),
    TextEditingController(),
  ];

  /// Stable across retries of THIS composer so a re-tap / network retry replays
  /// the same create instead of duplicating the post (§9).
  final String _idempotencyKey = uuidV4();

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args != null && args.hasContent) {
      _picked = _Selection(
        key: 'shared',
        imageUrl: args.imageUrl,
        outfitId: args.outfitId,
      );
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _pollQuestion.dispose();
    for (final c in _pollOptions) {
      c.dispose();
    }
    super.dispose();
  }

  /// A poll needs a question + at least 2 non-blank options.
  bool get _pollValid {
    if (_pollQuestion.text.trim().isEmpty) return false;
    return _pollOptions.where((c) => c.text.trim().isNotEmpty).length >= 2;
  }

  bool get _canPublish => switch (_mode) {
    _ComposeMode.look => _picked != null,
    _ComposeMode.text => _caption.text.trim().isNotEmpty,
    _ComposeMode.poll => _pollValid,
  };

  /// Pick a fresh photo from gallery/camera (compressed, EXIF-stripped by the
  /// shipped [PostImageService]); it becomes the selected media.
  Future<void> _pickPhoto(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref
          .read(postImageServiceProvider)
          .pickAndCompress(source);
      if (bytes == null || !mounted) return; // user cancelled
      setState(() => _picked = _Selection(key: 'photo', bytes: bytes));
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.addItemPickError);
    }
  }

  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context);
    if (_busy) return;
    if (!_canPublish) {
      wtmSnack(context, switch (_mode) {
        _ComposeMode.look => l10n.wtmComposePickFirst,
        _ComposeMode.text => l10n.wtmComposeTextFirst,
        _ComposeMode.poll => l10n.composePollIncomplete,
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final caption = _caption.text.trim();
      Map<String, dynamic>? pollPayload;
      if (_mode == _ComposeMode.poll) {
        pollPayload = {
          'question': _pollQuestion.text.trim(),
          'options': [
            for (final c in _pollOptions)
              if (c.text.trim().isNotEmpty) c.text.trim(),
          ],
        };
      }
      final sel = _mode == _ComposeMode.look ? _picked : null;
      // A gallery/camera pick uploads to the durable post bucket first (§8).
      String? imageUrl = sel?.imageUrl;
      if (sel?.bytes != null) {
        try {
          imageUrl = await ref
              .read(postImageServiceProvider)
              .upload(sel!.bytes!);
        } on Exception {
          if (mounted) {
            wtmSnack(context, l10n.wtmComposeUploadFailed);
            setState(() => _busy = false);
          }
          return;
        }
      }
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            imageUrl: imageUrl,
            outfitId: sel?.outfitId,
            caption: caption.isEmpty ? null : caption,
            tags: [for (final t in _tags) t.replaceFirst('#', '')],
            poll: pollPayload,
            idempotencyKey: _idempotencyKey,
          );
      await ref.read(analyticsProvider).track(AnalyticsEvents.postCreated);
      if (pollPayload != null) {
        await ref.read(analyticsProvider).track(AnalyticsEvents.pollCreated);
      }
      ref.read(feedProvider.notifier).refresh();
      if (mounted) {
        wtmSnack(context, l10n.wtmComposeDone);
        // Land back on Community so the fresh feed is right there.
        context.go(AppRoute.wtmSocial);
      }
    } on ApiException catch (e) {
      // Moderation/validation messages are written for users — surface them
      // instead of a generic failure (§13 error contract).
      if (mounted) {
        final specific =
            e.code == ApiErrorCode.moderationBlocked ||
            e.code == ApiErrorCode.validationError;
        wtmSnack(context, specific ? e.message : l10n.wtmComposeError);
      }
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmComposeError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pollsEnabled = ref.watch(
      featureEnabledProvider(FeatureFlags.postPolls),
    );
    if (!pollsEnabled && _mode == _ComposeMode.poll) {
      _mode = _ComposeMode.look;
    }

    return WtmPage(
      title: l10n.wtmComposeTitle,
      eyebrow: l10n.wtmComposeEyebrow,
      // Publish stays pinned under the form (mobile QA Part A: sticky CTA).
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientCta(
            label: l10n.wtmComposePublish,
            icon: const WtmIcon(
              WtmGlyph.sparkle,
              size: 15,
              color: WtmColors.ctaText,
            ),
            onPressed: _busy ? null : _publish,
          ),
          const SizedBox(height: WtmSpace.s6),
          Text(
            l10n.wtmComposeModerationNote,
            textAlign: TextAlign.center,
            style: WtmType.micro,
          ),
        ],
      ),
      children: [
        WtmChipRow(
          children: [
            WtmChip(
              label: l10n.wtmComposeModeLook,
              on: _mode == _ComposeMode.look,
              onTap: () => setState(() => _mode = _ComposeMode.look),
            ),
            WtmChip(
              label: l10n.wtmComposeModeText,
              on: _mode == _ComposeMode.text,
              onTap: () => setState(() => _mode = _ComposeMode.text),
            ),
            if (pollsEnabled)
              WtmChip(
                label: l10n.wtmComposeModePoll,
                on: _mode == _ComposeMode.poll,
                onTap: () => setState(() => _mode = _ComposeMode.poll),
              ),
          ],
        ),
        const SizedBox(height: WtmSpace.s14),
        ...switch (_mode) {
          _ComposeMode.look => _lookSection(l10n),
          _ComposeMode.text => const <Widget>[],
          _ComposeMode.poll => _pollSection(l10n),
        },
        TextField(
          controller: _caption,
          maxLines: _mode == _ComposeMode.text ? 5 : 3,
          maxLength: 400,
          style: WtmType.body,
          cursorColor: WtmColors.gold,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(
            _mode == _ComposeMode.text
                ? l10n.wtmComposeTextHint
                : l10n.wtmComposeCaption,
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        WtmChipRow(
          children: [
            for (final tag in _suggested)
              WtmChip(
                label: tag,
                on: _tags.contains(tag),
                onTap: () => setState(
                  () =>
                      _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag),
                ),
              ),
          ],
        ),
        const SizedBox(height: WtmSpace.s12),
      ],
    );
  }

  // ── look/image media (closet · outfits · looks · gallery · camera) ─────────

  List<Widget> _lookSection(AppLocalizations l10n) {
    final sel = _picked;

    return [
      // The selected media, previewed before publish (mobile QA #2).
      EyebrowLabel(l10n.wtmComposePreviewEyebrow),
      const SizedBox(height: WtmSpace.s10),
      Center(
        child: SizedBox(
          width: 168,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: sel == null
                ? WtmDashedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(WtmSpace.s12),
                      child: Center(
                        child: Text(
                          l10n.wtmComposeNoPreview,
                          textAlign: TextAlign.center,
                          style: WtmType.micro.copyWith(height: 1.5),
                        ),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(WtmRadius.tile),
                    child: sel.bytes != null
                        ? Image.memory(sel.bytes!, fit: BoxFit.cover)
                        : sel.imageUrl == null
                        ? const AuroraBox(
                            borderRadius: BorderRadius.all(
                              Radius.circular(WtmRadius.tile),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: sel.imageUrl!,
                            cacheKey: stableImageCacheKey(sel.imageUrl!),
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const AuroraBox(
                              borderRadius: BorderRadius.all(
                                Radius.circular(WtmRadius.tile),
                              ),
                            ),
                            errorWidget: (_, _, _) => const AuroraBox(
                              borderRadius: BorderRadius.all(
                                Radius.circular(WtmRadius.tile),
                              ),
                            ),
                          ),
                  ),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s12),
      // Owned media lives in the PICKER (mobile QA Part A: the compose page
      // stays clean — no inline grids); gallery/camera sit beside it.
      GhostButton(
        label: l10n.wtmComposeChoose,
        icon: const WtmIcon(WtmGlyph.hanger, size: 15, color: WtmColors.gold),
        foregroundColor: WtmColors.gold,
        borderColor: WtmColors.pillBorder,
        onPressed: _busy ? null : _openMediaPicker,
      ),
      const SizedBox(height: WtmSpace.s10),
      Row(
        children: [
          Expanded(
            child: GhostButton(
              label: l10n.wtmComposeFromGallery,
              icon: const WtmIcon(
                WtmGlyph.image,
                size: 15,
                color: WtmColors.text,
              ),
              onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
            ),
          ),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: GhostButton(
              label: l10n.wtmComposeFromCamera,
              icon: const WtmIcon(
                WtmGlyph.camera,
                size: 15,
                color: WtmColors.text,
              ),
              onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
            ),
          ),
        ],
      ),
      const SizedBox(height: WtmSpace.s10),
      // MoodMirror is an OPTION, never forced (mobile QA #2).
      GhostButton(
        label: l10n.wtmComposeGenerateLook,
        icon: const WtmIcon(WtmGlyph.sparkle, size: 15, color: WtmColors.text),
        onPressed: () => context.push(AppRoute.wtmMirror),
      ),
      const SizedBox(height: WtmSpace.s14),
    ];
  }

  /// The media picker sheet (mobile QA Part A): Closet / Outfits / Looks chips
  /// over a scrollable grid. Picking a tile closes the sheet and updates the
  /// compose preview.
  Future<void> _openMediaPicker() async {
    final selection = await _showWtmComposeMediaPicker(
      context,
      ref,
      shared: widget.args,
      selectedKey: _picked?.key,
    );
    if (selection != null && mounted) setState(() => _picked = selection);
  }

  // ── poll draft (question + 2–4 options) ────────────────────────────────────

  List<Widget> _pollSection(AppLocalizations l10n) {
    return [
      TextField(
        controller: _pollQuestion,
        style: WtmType.body,
        cursorColor: WtmColors.gold,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: _decoration(l10n.composePollQuestionHint),
      ),
      const SizedBox(height: WtmSpace.s10),
      for (var i = 0; i < _pollOptions.length; i++) ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pollOptions[i],
                style: WtmType.body,
                cursorColor: WtmColors.gold,
                onChanged: (_) => setState(() {}),
                decoration: _decoration(l10n.composePollOption(i + 1)),
              ),
            ),
            if (_pollOptions.length > 2) ...[
              const SizedBox(width: WtmSpace.s8),
              _RemoveOptionButton(
                onTap: () => setState(() => _pollOptions.removeAt(i).dispose()),
              ),
            ],
          ],
        ),
        const SizedBox(height: WtmSpace.s8),
      ],
      if (_pollOptions.length < 4)
        Align(
          alignment: Alignment.centerLeft,
          child: GoldPill(
            label: l10n.composePollAddOption,
            icon: const WtmIcon(WtmGlyph.plus, size: 12, color: WtmColors.gold),
            onTap: () =>
                setState(() => _pollOptions.add(TextEditingController())),
          ),
        ),
      const SizedBox(height: WtmSpace.s8),
      Text(
        _pollValid ? l10n.wtmComposePollNote : l10n.composePollIncomplete,
        style: WtmType.micro,
      ),
      const SizedBox(height: WtmSpace.s12),
    ];
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
    filled: true,
    fillColor: WtmColors.iconBtnBg,
    counterStyle: WtmType.micro,
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
  );
}

/// Square hairline remove button for a poll option — a 45°-rotated plus glyph
/// (the kit has no ✕), matching [WtmIconButton] metrics.
class _RemoveOptionButton extends StatelessWidget {
  const _RemoveOptionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).deleteButtonTooltip,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WtmColors.iconBtnBg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: WtmColors.line),
            ),
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: 0.7853981633974483, // π/4
              child: const WtmIcon(
                WtmGlyph.plus,
                size: 15,
                color: WtmColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Media picker sheet (mobile QA Part A) — Closet / Outfits / Looks chips over
/// a SCROLLABLE grid, kept out of the compose page. The Share-Look prefill
/// rides at the front of every source. Resolves with the picked media.
Future<_Selection?> _showWtmComposeMediaPicker(
  BuildContext context,
  WidgetRef ref, {
  WtmComposeArgs? shared,
  String? selectedKey,
}) {
  return showModalBottomSheet<_Selection>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (sheetContext) {
      var source = _MediaSource.closet;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Consumer(
          // WATCH the sources inside the sheet — the grids fill in live as the
          // closet/outfits load (the compose page itself no longer reads them).
          builder: (sheetContext, ref, _) {
            final l10n = AppLocalizations.of(sheetContext);
            final looks = ref.watch(savedLookRecordsProvider);
            final outfits =
                ref.watch(outfitsProvider).asData?.value ?? const <Outfit>[];
            final items =
                ref.watch(wardrobeItemsProvider).asData?.value ??
                const <WardrobeItem>[];
            final byId = {for (final i in items) i.id: i};
            void pick(_Selection selection) =>
                Navigator.of(sheetContext).pop(selection);

            final tiles = <Widget>[
              if (shared != null && shared.hasContent)
                _LookPick(
                  url: shared.imageUrl,
                  selected: selectedKey == 'shared',
                  onTap: () => pick(
                    _Selection(
                      key: 'shared',
                      imageUrl: shared.imageUrl,
                      outfitId: shared.outfitId,
                    ),
                  ),
                ),
              ...switch (source) {
                _MediaSource.closet => [
                  for (final item in items)
                    if (item.displayImageUrl != null)
                      _LookPick(
                        url: item.displayImageUrl,
                        selected: selectedKey == 'item:${item.id}',
                        onTap: () => pick(
                          _Selection(
                            key: 'item:${item.id}',
                            imageUrl: item.displayImageUrl,
                          ),
                        ),
                      ),
                ],
                _MediaSource.outfits => [
                  for (final outfit in outfits)
                    _OutfitPick(
                      outfit: outfit,
                      // The post image: the cover, else the first piece.
                      imageUrl:
                          outfit.coverImageUrl ??
                          outfit.itemIds
                              .map((id) => byId[id]?.displayImageUrl)
                              .whereType<String>()
                              .firstOrNull,
                      selected: selectedKey == 'outfit:${outfit.id}',
                      onTap: (url) => pick(
                        _Selection(
                          key: 'outfit:${outfit.id}',
                          imageUrl: url,
                          outfitId: outfit.id,
                        ),
                      ),
                    ),
                ],
                _MediaSource.looks => [
                  for (final (i, look) in looks.indexed)
                    _LookPick(
                      url: look.imageUrl,
                      selected: selectedKey == 'look:$i',
                      onTap: () => pick(
                        _Selection(key: 'look:$i', imageUrl: look.imageUrl),
                      ),
                    ),
                ],
              },
            ];

            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.72,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WtmSpace.screenH,
                  WtmSpace.s16,
                  WtmSpace.screenH,
                  WtmSpace.s10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.wtmComposePick,
                      textAlign: TextAlign.center,
                      style: WtmType.h1.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: WtmSpace.s12),
                    WtmChipRow(
                      children: [
                        WtmChip(
                          label: l10n.wtmComposeSourceCloset,
                          on: source == _MediaSource.closet,
                          onTap: () =>
                              setSheetState(() => source = _MediaSource.closet),
                        ),
                        WtmChip(
                          label: l10n.wtmComposeSourceOutfits,
                          on: source == _MediaSource.outfits,
                          onTap: () => setSheetState(
                            () => source = _MediaSource.outfits,
                          ),
                        ),
                        WtmChip(
                          label: l10n.wtmComposeSourceLooks,
                          on: source == _MediaSource.looks,
                          onTap: () =>
                              setSheetState(() => source = _MediaSource.looks),
                        ),
                      ],
                    ),
                    const SizedBox(height: WtmSpace.s10),
                    Expanded(
                      child: tiles.isEmpty
                          ? Center(
                              child: Text(
                                l10n.wtmComposeSourceEmpty,
                                textAlign: TextAlign.center,
                                style: WtmType.micro,
                              ),
                            )
                          : GridView.count(
                              crossAxisCount: 3,
                              mainAxisSpacing: 7,
                              crossAxisSpacing: 7,
                              childAspectRatio: 3 / 4,
                              children: tiles,
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _LookPick extends StatelessWidget {
  const _LookPick({
    required this.url,
    required this.selected,
    required this.onTap,
  });

  final String? url;
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
            child: url == null
                ? const AuroraBox(
                    borderRadius: BorderRadius.all(
                      Radius.circular(WtmRadius.tile),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: url!,
                    cacheKey: stableImageCacheKey(url!),
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const AuroraBox(
                      borderRadius: BorderRadius.all(
                        Radius.circular(WtmRadius.tile),
                      ),
                    ),
                    errorWidget: (_, _, _) => const AuroraBox(
                      borderRadius: BorderRadius.all(
                        Radius.circular(WtmRadius.tile),
                      ),
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
              child: const WtmIcon(
                WtmGlyph.check,
                size: 14,
                color: WtmColors.gold,
              ),
            ),
        ],
      ),
    );
  }
}

/// An outfit tile in the source grid — cover/piece image on the fabric swatch
/// (name under it would crowd a 4-col grid; the swatch face carries it).
class _OutfitPick extends StatelessWidget {
  const _OutfitPick({
    required this.outfit,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });

  final Outfit outfit;
  final String? imageUrl;
  final bool selected;
  final void Function(String? imageUrl) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        FabricTile(
          imageUrl: imageUrl,
          swatchIndex: outfit.id.hashCode.abs() % 8,
          aspectRatio: null,
          fit: BoxFit.cover,
          semanticLabel: (outfit.name ?? '').trim().isEmpty
              ? l10n.wtmOutfitsUntitled
              : outfit.name!.trim(),
          onTap: () => onTap(imageUrl),
        ),
        if (selected)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WtmRadius.tile),
                border: Border.all(color: WtmColors.gold, width: 2),
              ),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.all(4),
              child: const WtmIcon(
                WtmGlyph.check,
                size: 14,
                color: WtmColors.gold,
              ),
            ),
          ),
      ],
    );
  }
}
