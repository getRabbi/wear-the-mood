import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/wardrobe_image_service.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Add Garment (§3.10, P3) — the REAL pipeline in Atelier dress:
/// camera/gallery pick (compressed, EXIF-stripped) → upload (R2 presigned or
/// legacy bucket) → `POST /v1/wardrobe` → poll until the background removal
/// finishes (same cadence/timeout as the shipped flow, transient errors
/// tolerated, timeout reveals) → cutout preview → name/category confirm
/// (PATCH) → closet refresh → toast. Backend untouched (§0.1).
class WtmAddGarmentScreen extends ConsumerStatefulWidget {
  const WtmAddGarmentScreen({super.key});

  @override
  ConsumerState<WtmAddGarmentScreen> createState() =>
      _WtmAddGarmentScreenState();
}

enum _Stage { capture, processing, confirm, failed }

class _WtmAddGarmentScreenState extends ConsumerState<WtmAddGarmentScreen> {
  _Stage _stage = _Stage.capture;
  Uint8List? _bytes;
  WardrobeItem? _item;
  String? _error;
  bool _saving = false;
  final _name = TextEditingController();
  ClosetCategory? _category;

  // Proven cadence from the shipped add flow.
  static const _firstCheck = Duration(milliseconds: 350);
  static const _pollEvery = Duration(milliseconds: 800);
  static const _timeout = Duration(seconds: 90);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    Uint8List? bytes;
    try {
      bytes =
          await ref.read(wardrobeImageServiceProvider).pickAndCompress(source);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmAddPickFailed);
      return;
    }
    if (bytes == null || !mounted) return; // user cancelled the picker
    _bytes = bytes;
    _run();
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _stage = _Stage.processing;
      _error = null;
    });
    try {
      // Upload → create. Category/name come AFTER the preview (§3.10).
      final media =
          await ref.read(wardrobeImageServiceProvider).upload(_bytes!);
      if (!mounted) return;
      final created = await ref.read(wardrobeRepositoryProvider).addItem(
            imageUrl: media.legacyUrl,
            objectKey: media.objectKey,
          );
      if (!mounted) return;
      final ready = await _pollUntilCutoutReady(created.id) ?? created;
      if (!mounted) return;
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _item = ready;
        _name.text = ready.title?.trim() ?? '';
        // Preselect what the auto-tagger decided, when it maps to a chip.
        _category = ClosetCategory.values.firstWhere(
          (c) =>
              c != ClosetCategory.all &&
              c != ClosetCategory.favorites &&
              c.matches(ready.category),
          orElse: () => ClosetCategory.all,
        );
        if (_category == ClosetCategory.all) _category = null;
        _stage = _Stage.confirm;
      });
    } on ApiException catch (e) {
      _fail(e.message);
    } on StateError catch (e) {
      _fail(e.message); // not signed in (upload guard)
    } catch (_) {
      _fail(l10n.addItemError);
    }
  }

  /// Poll the closet until the cutout settles (or time out and reveal — the
  /// piece keeps finishing server-side). Transient fetch errors just retry.
  Future<WardrobeItem?> _pollUntilCutoutReady(String id) async {
    final deadline = DateTime.now().add(_timeout);
    var first = true;
    WardrobeItem? latest;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(first ? _firstCheck : _pollEvery);
      first = false;
      if (!mounted) return latest;
      List<WardrobeItem> items;
      try {
        items = await ref.read(wardrobeRepositoryProvider).getItems();
      } catch (_) {
        continue; // transient network blip — retry next tick
      }
      for (final item in items) {
        if (item.id == id) {
          latest = item;
          break;
        }
      }
      if (latest != null && !latest.isProcessingCutout) return latest;
    }
    return latest;
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final item = _item!;
    setState(() => _saving = true);
    try {
      final title = _name.text.trim();
      await ref.read(wardrobeRepositoryProvider).updateItem(
            item.id,
            title: title.isEmpty ? null : title,
            category: _category?.name ?? item.category,
            // Preserve the tagger's color — null clears it server-side.
            color: item.color,
          );
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (!mounted) return;
      wtmSnack(context, l10n.wtmAddSavedToast);
      wtmPageBack(context);
    } on ApiException catch (e) {
      if (mounted) {
        wtmSnack(context, e.message);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      title: l10n.wtmAddTitle,
      eyebrow: switch (_stage) {
        _Stage.capture => l10n.wtmAddCaptureEyebrow,
        _Stage.processing => l10n.wtmAddProcessingEyebrow,
        _Stage.confirm => l10n.wtmAddConfirmEyebrow,
        _Stage.failed => l10n.errorGenericTitle,
      },
      children: switch (_stage) {
        _Stage.capture => _capture(l10n),
        _Stage.processing => _processing(l10n),
        _Stage.confirm => _confirm(l10n),
        _Stage.failed => [
            const SizedBox(height: WtmSpace.s22),
            WtmErrorState(
              title: l10n.errorGenericTitle,
              message: _error ?? l10n.addItemError,
              retryLabel: l10n.commonRetry,
              onRetry: _bytes == null
                  ? () => setState(() => _stage = _Stage.capture)
                  : _run,
            ),
          ],
      },
    );
  }

  List<Widget> _capture(AppLocalizations l10n) {
    return [
      Text(
        l10n.wtmAddCaptureTitle,
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.wtmAddCaptureMessage,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      AuroraBox(
        height: 240,
        vignette: true,
        child: const Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: WtmIcon(WtmGlyph.hanger, size: 40, color: WtmColors.gold),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      GradientCta(
        label: l10n.wtmAddTakePhoto,
        icon:
            const WtmIcon(WtmGlyph.camera, size: 15, color: WtmColors.ctaText),
        onPressed: () => _pick(ImageSource.camera),
      ),
      const SizedBox(height: WtmSpace.s10),
      GhostButton(
        label: l10n.wtmAddFromGallery,
        icon: const WtmIcon(WtmGlyph.image, size: 15, color: WtmColors.text),
        onPressed: () => _pick(ImageSource.gallery),
      ),
    ];
  }

  List<Widget> _processing(AppLocalizations l10n) {
    return [
      // The picked shot under the aurora treatment while the atelier works.
      SizedBox(
        height: 300,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WtmRadius.tile),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true),
              const DecoratedBox(
                decoration:
                    BoxDecoration(gradient: WtmGradients.vignetteRadial),
              ),
              const GrainOverlay(),
            ],
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      Text(
        l10n.wardrobeRemovingBackground,
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.wtmAddProcessingHint,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      const WtmGoldProgress(),
    ];
  }

  List<Widget> _confirm(AppLocalizations l10n) {
    final item = _item!;
    return [
      Text(
        l10n.wtmAddConfirmTitle,
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.wtmAddConfirmMessage,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      Center(
        child: SizedBox(
          width: 200,
          child: FabricTile(
            imageUrl: item.displayImageUrl,
            swatchIndex: item.id.hashCode.abs() % 8,
            fit: BoxFit.contain,
            semanticLabel: l10n.wtmAddConfirmTitle,
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s14),
      TextField(
        controller: _name,
        style: WtmType.body,
        cursorColor: WtmColors.gold,
        decoration: InputDecoration(
          hintText: l10n.wtmGarmentNameHint,
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
      Wrap(
        spacing: WtmSpace.s6,
        runSpacing: WtmSpace.s6,
        children: [
          for (final c in ClosetCategory.values)
            if (c != ClosetCategory.all && c != ClosetCategory.favorites)
              WtmChip(
                label: c.label(l10n),
                on: _category == c,
                onTap: () => setState(
                    () => _category = _category == c ? null : c),
              ),
        ],
      ),
      const SizedBox(height: WtmSpace.s16),
      GradientCta(
        label: l10n.wtmAddSaveCta,
        icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
        onPressed: _saving ? null : _save,
      ),
    ];
  }
}

/// Indeterminate thin gold progress line (board `.track`/`.fill`) — a sweeping
/// gold segment; static half-fill under reduced motion.
class WtmGoldProgress extends StatefulWidget {
  const WtmGoldProgress({super.key});

  @override
  State<WtmGoldProgress> createState() => _WtmGoldProgressState();
}

class _WtmGoldProgressState extends State<WtmGoldProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0x1CFFFFFF), // .track
                      borderRadius: BorderRadius.circular(WtmRadius.chip),
                    ),
                  ),
                  if (reduceMotion)
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: WtmGradients.sliderFill,
                          borderRadius: BorderRadius.circular(WtmRadius.chip),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      left: (width + 120) * t - 120,
                      width: 120,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: WtmGradients.sliderFill,
                          borderRadius: BorderRadius.circular(WtmRadius.chip),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
