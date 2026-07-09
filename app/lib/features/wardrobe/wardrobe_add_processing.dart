import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'drawers/drawer_store.dart';
import 'wardrobe_image_service.dart';
import 'wardrobe_providers.dart';

/// Runs the FULL add pipeline — upload → create → optional AI enhance — behind a
/// blocking progress sheet, waiting until the background removal (and enhance)
/// are actually DONE server-side, then refreshes the closet. The closet only
/// ever receives finished pieces, so it never shows an in-progress / flickering
/// tile. Returns true once the piece is in the closet.
Future<bool> showWardrobeAddProcessing(
  BuildContext context,
  WidgetRef ref, {
  required Uint8List bytes,
  String? title,
  String? category,
  String? drawerId,
  required bool enhance,
}) {
  return _open(
    context,
    _ProcessingSheet(
      bytes: bytes,
      title: title,
      category: category,
      drawerId: drawerId,
      enhance: enhance,
    ),
  );
}

/// Enhance an item already in the closet, behind the same progress sheet.
Future<bool> showWardrobeEnhanceProcessing(
  BuildContext context,
  WidgetRef ref, {
  required WardrobeItem item,
}) {
  return _open(context, _ProcessingSheet(existing: item, enhance: true));
}

Future<bool> _open(BuildContext context, Widget sheet) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => PopScope(canPop: false, child: sheet),
  );
  return done ?? false;
}

enum _Phase { removingBg, enhancing, done, failed }

class _ProcessingSheet extends ConsumerStatefulWidget {
  const _ProcessingSheet({
    this.bytes,
    this.existing,
    this.title,
    this.category,
    this.drawerId,
    required this.enhance,
  });

  final Uint8List? bytes; // add flow
  final WardrobeItem? existing; // enhance-an-existing-item flow
  final String? title;
  final String? category;
  final String? drawerId;
  final bool enhance;

  @override
  ConsumerState<_ProcessingSheet> createState() => _ProcessingSheetState();
}

class _ProcessingSheetState extends ConsumerState<_ProcessingSheet> {
  _Phase _phase = _Phase.removingBg;
  String? _error;

  static const _pollEvery = Duration(milliseconds: 800);
  static const _firstCheck = Duration(milliseconds: 350);
  static const _timeout = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _phase = widget.enhance && widget.existing != null
        ? _Phase.enhancing
        : _Phase.removingBg;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    try {
      final String itemId;
      var wantEnhance = widget.enhance;

      if (widget.existing != null) {
        // Enhance an item already in the closet.
        itemId = widget.existing!.id;
        await ref.read(aiStudioRepositoryProvider).enhanceItem(itemId);
        ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
      } else {
        // Fresh add: upload → create → (optional) enhance.
        final media = await ref
            .read(wardrobeImageServiceProvider)
            .upload(widget.bytes!);
        final item = await ref
            .read(wardrobeRepositoryProvider)
            .addItem(
              title: widget.title,
              category: widget.category,
              imageUrl: media.legacyUrl,
              objectKey: media.objectKey,
            );
        itemId = item.id;
        if (widget.drawerId != null) {
          ref
              .read(closetAssignmentsProvider.notifier)
              .assign(item.id, widget.drawerId!);
        }
        if (wantEnhance) {
          try {
            await ref.read(aiStudioRepositoryProvider).enhanceItem(item.id);
            ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
          } on ApiException {
            // Enhance couldn't start (e.g. out of credits) — still finish the
            // background removal and add the piece.
            wantEnhance = false;
          }
        }
      }

      await _pollUntilReady(itemId, enhance: wantEnhance);

      // Pull the finished piece into the closet before we reveal it.
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail(l10n.addItemError);
    }
  }

  /// Poll the item until its background removal (and enhance) have settled.
  Future<void> _pollUntilReady(String id, {required bool enhance}) async {
    final deadline = DateTime.now().add(_timeout);
    var first = true;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(first ? _firstCheck : _pollEvery);
      first = false;
      if (!mounted) return;
      List<WardrobeItem> items;
      try {
        items = await ref.read(wardrobeRepositoryProvider).getItems();
      } catch (_) {
        continue; // transient network blip — retry next tick
      }
      WardrobeItem? it;
      for (final i in items) {
        if (i.id == id) {
          it = i;
          break;
        }
      }
      if (it == null) continue;
      final cutoutReady = !it.isProcessingCutout;
      final enhanceReady = !enhance || !it.isEnhancing;
      if (mounted) {
        setState(
          () => _phase = (enhance && cutoutReady)
              ? _Phase.enhancing
              : _Phase.removingBg,
        );
      }
      if (cutoutReady && enhanceReady) return;
    }
    // Timed out — the piece is added and will finish server-side; reveal it now.
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final failed = _phase == _Phase.failed;
    final done = _phase == _Phase.done;

    final status = switch (_phase) {
      _Phase.removingBg => l10n.wardrobeRemovingBackground,
      _Phase.enhancing => l10n.wardrobeEnhanceStarted,
      _Phase.done => l10n.addItemSaved,
      _Phase.failed => _error ?? l10n.addItemError,
    };

    // Big, comfortably-sized preview scaled to the screen (3:4), so the sheet
    // reads as a proper "studio" moment rather than a tiny toast.
    final screenW = MediaQuery.of(context).size.width;
    final previewW = (screenW * 0.58).clamp(210.0, 300.0);
    final previewH = previewW * 4 / 3;

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview of the piece being processed.
            SizedBox(
              width: previewW,
              height: previewH,
              child: _Preview(
                bytes: widget.bytes,
                imageUrl: widget.existing?.displayImageUrl,
                phase: _phase,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!failed && !done)
                  const PremiumInlineLoader(size: 22)
                else
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: done ? AppColors.success : AppColors.danger,
                    size: 24,
                  ),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Text(
                    status,
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (!failed && !done) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                l10n.addPieceProcessingHint,
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (failed) ...[
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: l10n.commonCancel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: PrimaryButton(
                      label: l10n.commonRetry,
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _phase = widget.enhance && widget.existing != null
                              ? _Phase.enhancing
                              : _Phase.removingBg;
                        });
                        _run();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The piece preview with a soft diagonal shimmer sweep while processing.
class _Preview extends StatefulWidget {
  const _Preview({this.bytes, this.imageUrl, required this.phase});

  final Uint8List? bytes;
  final String? imageUrl;
  final _Phase phase;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final processing =
        widget.phase == _Phase.removingBg || widget.phase == _Phase.enhancing;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GarmentTile(imageUrl: widget.imageUrl ?? '', bytes: widget.bytes),
          if (processing)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    final t = _sweep.value;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 + t * 2 - 0.4, -1),
                          end: Alignment(-1 + t * 2 + 0.4, 1),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
