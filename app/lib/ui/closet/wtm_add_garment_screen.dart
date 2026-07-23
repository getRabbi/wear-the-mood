import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/config/feature_gates.dart';
import '../../core/media/image_pick_permission.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/ai_job.dart';
import '../../data/models/credits.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/wardrobe_image_service.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_enhance.dart';

/// Add Garment (§3.10, P3) — the REAL pipeline in Atelier dress:
/// camera/gallery pick (compressed, EXIF-stripped) → upload (R2 presigned or
/// legacy bucket) → `POST /v1/wardrobe` → poll until the background removal
/// finishes (same cadence/timeout as the shipped flow, transient errors
/// tolerated, timeout reveals) → cutout preview → name/category confirm
/// (PATCH) → closet refresh → toast. Backend untouched (§0.1).
///
/// Mobile-QA restore: the shipped composer's add-mode choice rides along —
/// free "Remove background" (default) vs the premium **AI Enhance**
/// (Pro/Pro Max, spends credits via `/v1/ai/enhance`, §18 confirm-before-
/// charge). Free users see it locked → paywall; the cutout preview also
/// offers a post-hoc "Enhance item".
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
  bool _enhance = false; // AI Enhance mode picked on capture
  bool _enhancePhase = false; // poll is past bg-removal, enhance running
  String? _enhanceError; // the enhance JOB failed — shown on the confirm stage
  final _name = TextEditingController();
  ClosetCategory? _category;

  /// Drives the "alive" cutout wait: status steps through warming → clearing →
  /// refining → almost by elapsed time (the Job reports no sub-progress) and a
  /// tip rotates so the ~90s cold start never feels frozen.
  DateTime? _procStartedAt;
  Timer? _cycle;

  // Proven cadence from the shipped add flow.
  static const _firstCheck = Duration(milliseconds: 350);
  static const _pollEvery = Duration(milliseconds: 800);
  static const _timeout = Duration(seconds: 90);

  @override
  void dispose() {
    _cycle?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// Elapsed-time → friendly stage text for the BG-removal wait.
  String _stageText(AppLocalizations l10n) {
    final s = DateTime.now()
        .difference(_procStartedAt ?? DateTime.now())
        .inSeconds;
    if (s < 12) return l10n.wardrobeStageWarming;
    if (s < 40) return l10n.wardrobeStageClearing;
    if (s < 70) return l10n.wardrobeStageRefining;
    return l10n.wardrobeStageAlmost;
  }

  /// A tip that rotates every ~8s so the wait stays engaging.
  String _tip(AppLocalizations l10n) {
    final tips = [
      l10n.wardrobeTipBatch,
      l10n.wardrobeTipTryOn,
      l10n.wardrobeTipQuality,
    ];
    final i =
        DateTime.now().difference(_procStartedAt ?? DateTime.now()).inSeconds ~/
        8;
    return tips[i % tips.length];
  }

  Future<void> _pick(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    if (_enhance && !await confirmWtmEnhanceSpend(context, ref)) return;
    if (!mounted) return;
    Uint8List? bytes;
    try {
      bytes = await ref
          .read(wardrobeImageServiceProvider)
          .pickAndCompress(source);
    } catch (e) {
      if (!mounted) return;
      if (isImagePermissionDenied(e)) {
        await showImagePermissionHelp(
          context,
          camera: source == ImageSource.camera,
        );
      } else {
        wtmSnack(context, l10n.wtmAddPickFailed);
      }
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
      _enhancePhase = false;
      _enhanceError = null;
      _error = null;
    });
    _procStartedAt = DateTime.now();
    // Repaint every few seconds so the staged status + rotating tip advance.
    _cycle ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _stage == _Stage.processing) setState(() {});
    });
    try {
      // Upload → create. Category/name come AFTER the preview (§3.10).
      final media = await ref
          .read(wardrobeImageServiceProvider)
          .upload(_bytes!);
      if (!mounted) return;
      final created = await ref
          .read(wardrobeRepositoryProvider)
          .addItem(imageUrl: media.legacyUrl, objectKey: media.objectKey);
      if (!mounted) return;
      // Kick off the premium enhance right behind the bg removal. If it can't
      // start (e.g. out of credits) the piece still lands as a plain cutout.
      AiJob? enhanceJob;
      if (_enhance) {
        try {
          enhanceJob = await ref
              .read(aiStudioRepositoryProvider)
              .enhanceItem(created.id);
          ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
          ref.invalidate(creditsProvider);
        } on ApiException catch (e) {
          if (mounted) setState(() => _enhanceError = e.message);
        }
      }
      if (!mounted) return;
      var ready = await _pollUntilCutoutReady(created.id) ?? created;
      if (!mounted) return;
      // The JOB — not just the item — is polled to terminal, so a failed
      // enhance surfaces with the server's real message instead of silently
      // ending as "just background removal" (mobile QA #5).
      if (enhanceJob != null) {
        setState(() => _enhancePhase = true);
        final terminal = await pollWtmAiJob(ref, enhanceJob);
        if (!mounted) return;
        if (terminal.status.isFailed) {
          _enhanceError = terminal.error ?? l10n.wardrobeEnhanceError;
        }
        ref.invalidate(
          creditsProvider,
        ); // charged on success / refunded on fail
      }
      final refreshed = await _refreshAndFind(created.id);
      if (!mounted) return;
      ready = refreshed ?? ready;
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

  /// Enhance the already-created piece from the cutout preview (post-hoc
  /// choice — same credit confirm, then back to the processing stage to wait).
  Future<void> _enhanceExisting() async {
    final l10n = AppLocalizations.of(context);
    // AWAIT the real plan — creditsProvider is autoDispose, so a bare read
    // after the capture stage unmounts returns loading/null and sent even
    // Pro Max to the paywall (mobile QA #3). Fetch failure ≠ paywall.
    final Credits credits;
    try {
      credits = await ref.read(creditsProvider.future);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmCreditsCheckFailed);
      return;
    }
    if (!mounted) return;
    if (!credits.isSubscriber) {
      context.push(AppRoute.wtmPaywall);
      return;
    }
    if (!await confirmWtmEnhanceSpend(context, ref) || !mounted) return;
    final item = _item!;
    setState(() {
      _stage = _Stage.processing;
      _enhancePhase = true;
      _enhanceError = null;
      _error = null;
    });
    try {
      final job = await ref
          .read(aiStudioRepositoryProvider)
          .enhanceItem(item.id);
      ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
      ref.invalidate(creditsProvider);
      final terminal = await pollWtmAiJob(ref, job);
      if (!mounted) return;
      if (terminal.status.isFailed) {
        _enhanceError = terminal.error ?? l10n.wardrobeEnhanceError;
      }
      ref.invalidate(creditsProvider);
      final refreshed = await _refreshAndFind(item.id);
      if (!mounted) return;
      setState(() {
        _item = refreshed ?? item;
        _stage = _Stage.confirm;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _enhanceError = e.message;
          _stage = _Stage.confirm;
        });
      }
    }
  }

  /// Open the free Erase/Restore editor on the fresh cutout; adopt the result.
  Future<void> _fixCutout() async {
    final item = _item;
    if (item == null) return;
    final updated = await context.push<WardrobeItem>(
      AppRoute.wtmClosetFixCutout,
      extra: item,
    );
    if (updated != null && mounted) setState(() => _item = updated);
  }

  /// Refresh the closet and return this piece's latest server state.
  Future<WardrobeItem?> _refreshAndFind(String id) async {
    await ref.read(wardrobeItemsProvider.notifier).refresh();
    final items = ref.read(wardrobeItemsProvider).asData?.value ?? const [];
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Poll the closet until the background-removal cutout settles — or time out
  /// and reveal; the piece keeps finishing server-side. Transient fetch errors
  /// just retry.
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
      await ref
          .read(wardrobeRepositoryProvider)
          .updateItem(
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
    final credits = ref.watch(creditsProvider).asData?.value;
    final isSubscriber = credits?.isSubscriber ?? false;
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
        height: 200,
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
      // "Choose how to add this piece" — the shipped composer's free bg-removal
      // vs premium AI Enhance choice, in Atelier dress.
      EyebrowLabel(l10n.addPieceHowTitle),
      const SizedBox(height: WtmSpace.s10),
      _ModeCard(
        selected: !_enhance,
        glyph: WtmGlyph.erase,
        title: l10n.addPieceRemoveBgTitle,
        subtitle: l10n.addPieceRemoveBgSub,
        onTap: () => setState(() => _enhance = false),
      ),
      const SizedBox(height: WtmSpace.s8),
      _ModeCard(
        selected: _enhance,
        glyph: WtmGlyph.sparkle,
        title: l10n.addPieceEnhanceTitle,
        subtitle: l10n.addPieceEnhanceSub,
        description: l10n.addPieceEnhanceDesc,
        locked: !isSubscriber,
        onTap: () {
          // Free users see AI Enhance but it's locked → paywall (§18).
          if (!isSubscriber) {
            context.push(AppRoute.wtmPaywall);
            return;
          }
          setState(() => _enhance = true);
        },
      ),
      const SizedBox(height: WtmSpace.s8),
      Text(l10n.aiUploadDisclaimer, style: WtmType.micro),
      const SizedBox(height: WtmSpace.s14),
      GradientCta(
        label: l10n.wtmAddTakePhoto,
        icon: const WtmIcon(
          WtmGlyph.camera,
          size: 15,
          color: WtmColors.ctaText,
        ),
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
      // The picked shot under the aurora treatment while the atelier works
      // (post-hoc enhance re-enters here with no fresh bytes — show the piece).
      SizedBox(
        height: 300,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WtmRadius.tile),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_bytes != null)
                Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
              else
                FabricTile(
                  imageUrl: _item?.displayImageUrl,
                  swatchIndex: (_item?.id.hashCode ?? 0).abs() % 8,
                  aspectRatio: null,
                  fit: BoxFit.contain,
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: WtmGradients.vignetteRadial,
                ),
              ),
              const GrainOverlay(),
            ],
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      Text(
        // BG removal steps through warming → clearing → refining → almost by
        // elapsed time; enhance keeps its own copy.
        _enhancePhase ? l10n.wardrobeEnhanceStarted : _stageText(l10n),
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        // Honest expectation-setting during the cutout wait (first item warms up,
        // next ones are faster).
        _enhancePhase ? l10n.wtmAddProcessingHint : l10n.wardrobeWaitNote,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      if (!_enhancePhase) ...[
        const SizedBox(height: WtmSpace.s10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            _tip(l10n),
            key: ValueKey(_tip(l10n)),
            textAlign: TextAlign.center,
            style: WtmType.sub.copyWith(color: WtmColors.gold),
          ),
        ),
      ],
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
                onTap: () =>
                    setState(() => _category = _category == c ? null : c),
              ),
        ],
      ),
      // The enhance job failed (e.g. the AI studio is unavailable) — say so
      // honestly with the server's reason; the plain cutout is still saved and
      // the credit was refunded (mobile QA #5: never end silently).
      if (_enhanceError != null) ...[
        const SizedBox(height: WtmSpace.s12),
        Container(
          padding: const EdgeInsets.all(WtmSpace.s12),
          decoration: BoxDecoration(
            color: WtmColors.iconBtnBg,
            borderRadius: BorderRadius.circular(WtmRadius.tile),
            border: Border.all(color: WtmColors.danger),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WtmIcon(WtmGlyph.shield, size: 15, color: WtmColors.danger),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.wtmEnhanceFailedTitle,
                      style: WtmType.labelMedium.copyWith(
                        color: WtmColors.danger,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _enhanceError!,
                      style: WtmType.micro.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: WtmSpace.s16),
      GradientCta(
        label: l10n.wtmAddSaveCta,
        icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
        onPressed: _saving ? null : _save,
      ),
      // Post-hoc AI Enhance on the fresh cutout (Pro/Pro Max; free → paywall).
      // Doubles as the retry after a failed enhance.
      if (!item.aiEnhanced && !item.isEnhancing) ...[
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: _enhanceError == null
              ? l10n.wardrobeEnhanceItem
              : l10n.commonRetry,
          icon: const WtmIcon(
            WtmGlyph.sparkle,
            size: 15,
            color: WtmColors.gold,
          ),
          foregroundColor: WtmColors.gold,
          borderColor: WtmColors.pillBorder,
          onPressed: _saving ? null : _enhanceExisting,
        ),
      ],
      // Free manual cutout correction (gated), on the freshly removed cutout.
      if (kCutoutEditorEnabled && item.cutoutUrl != null) ...[
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.wardrobeFixCutout,
          icon: const WtmIcon(WtmGlyph.erase, size: 15, color: WtmColors.text),
          onPressed: _saving ? null : _fixCutout,
        ),
      ],
    ];
  }
}

/// "Choose how to add this piece" option card — free Remove background vs the
/// premium AI Enhance (locked for free users), Atelier-dressed version of the
/// shipped composer's choice.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.description,
    this.locked = false,
  });

  final bool selected;
  final WtmGlyph glyph;
  final String title;
  final String subtitle;
  final String? description;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s12),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(
                color: selected ? WtmColors.chipOnBorder : WtmColors.line,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WtmColors.riconBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WtmColors.riconBorder),
                  ),
                  alignment: Alignment.center,
                  child: WtmIcon(
                    glyph,
                    size: 15,
                    color: selected ? WtmColors.gold : WtmColors.muted,
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: WtmType.labelMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: WtmType.micro),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(description!, style: WtmType.micro),
                      ],
                    ],
                  ),
                ),
                if (locked)
                  const Padding(
                    padding: EdgeInsets.only(left: WtmSpace.s8),
                    child: WtmIcon(
                      WtmGlyph.shield,
                      size: 14,
                      color: WtmColors.faint,
                    ),
                  )
                else if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: WtmSpace.s8),
                    child: WtmIcon(
                      WtmGlyph.check,
                      size: 14,
                      color: WtmColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
