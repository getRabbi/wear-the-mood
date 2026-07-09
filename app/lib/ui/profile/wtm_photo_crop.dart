import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Square crop step for the profile photo (mobile QA #4) — pure Flutter, no
/// native plugin: the picked image pans/zooms inside a square frame
/// (InteractiveViewer) and the frame is captured via RepaintBoundary at save.
/// Resolves with the cropped PNG bytes, or null when dismissed.
Future<Uint8List?> showWtmPhotoCrop(BuildContext context, Uint8List bytes) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xF2050308),
    builder: (_) => _WtmPhotoCropDialog(bytes: bytes),
  );
}

class _WtmPhotoCropDialog extends StatefulWidget {
  const _WtmPhotoCropDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_WtmPhotoCropDialog> createState() => _WtmPhotoCropDialogState();
}

class _WtmPhotoCropDialogState extends State<_WtmPhotoCropDialog> {
  final _frameKey = GlobalKey();
  bool _capturing = false;

  Future<void> _use() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final boundary = _frameKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('crop frame not ready');
      // ~1080px square at a typical dpr — plenty for a display avatar.
      final image = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(data?.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() => _capturing = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog.fullscreen(
      backgroundColor: WtmColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WtmSpace.screenH),
          child: Column(
            children: [
              Text(l10n.wtmPhotoCropTitle,
                  style: WtmType.h2.copyWith(fontSize: 19)),
              const SizedBox(height: WtmSpace.s6),
              Text(l10n.wtmPhotoCropHint,
                  textAlign: TextAlign.center, style: WtmType.sub),
              const Spacer(),
              // The square frame IS the crop: whatever shows inside is saved.
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: WtmColors.pillBorder),
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: RepaintBoundary(
                          key: _frameKey,
                          child: ColoredBox(
                            color: WtmColors.bg,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5,
                              boundaryMargin:
                                  EdgeInsets.all(side), // roam past edges
                              child: Center(
                                child: Image.memory(
                                  widget.bytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              GradientCta(
                label: l10n.wtmPhotoCropUse,
                icon: const WtmIcon(WtmGlyph.check,
                    size: 15, color: WtmColors.ctaText),
                onPressed: _capturing ? null : _use,
              ),
              const SizedBox(height: WtmSpace.s10),
              GhostButton(
                label: MaterialLocalizations.of(context).cancelButtonLabel,
                onPressed: _capturing
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
