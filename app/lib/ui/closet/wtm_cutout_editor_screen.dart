import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Free manual Erase/Restore cutout editor (§ BG upgrade Phase 8).
///
/// The automatic BiRefNet cutout is the fast path; this is the deterministic
/// safety net for its rare errors — a low-contrast sleeve that faded, or fabric
/// left between trouser legs. It spends NO credits and runs NO AI.
///
/// Memory-safe by design (§12): edits are stored as normalized VECTOR strokes,
/// never full-resolution bitmap snapshots, so Undo/Redo and history stay cheap.
/// The final full-resolution mask is rasterised once, on Save, via a
/// PictureRecorder whose rasterisation is offloaded to the raster thread
/// (`Picture.toImage`) — the UI thread never composites the 1600px bitmap.
class WtmCutoutEditorScreen extends ConsumerStatefulWidget {
  const WtmCutoutEditorScreen({super.key, required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<WtmCutoutEditorScreen> createState() =>
      _WtmCutoutEditorScreenState();
}

enum _Brush { erase, restore }

enum _Bg { checker, white, black }

/// One editable stroke: normalized points ([0,1] of the image), a normalized
/// radius (fraction of the image's shorter edge), and whether it removes or
/// restores alpha. Cheap to store, transform and replay at any resolution.
class _Stroke {
  _Stroke(this.brush, this.radius);
  final _Brush brush;
  final double radius;
  final List<Offset> points = <Offset>[];
}

// History caps so an adversarial or fidgety session can't grow memory unbounded.
const int _maxStrokes = 240;
const int _maxPointsPerStroke = 3000;

// Brush radii as a fraction of the image's shorter edge.
const Map<int, double> _brushRadii = {0: 0.02, 1: 0.045, 2: 0.08};

class _WtmCutoutEditorScreenState extends ConsumerState<WtmCutoutEditorScreen> {
  ui.Image? _original;
  ui.Image? _cutout;
  bool _loading = true;
  String? _loadError;

  final List<_Stroke> _strokes = [];
  final List<_Stroke> _redo = [];
  _Brush _brush = _Brush.erase;
  int _brushSize = 1;
  _Bg _bg = _Bg.checker;
  bool _moveMode = false;
  bool _dirty = false;
  bool _saving = false;
  bool _atLimit = false;

  final TransformationController _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _original?.dispose();
    _cutout?.dispose();
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final item = widget.item;
    final originalUrl = item.imageUrl;
    final cutoutUrl = item.cutoutUrl ?? item.imageUrl;
    if (originalUrl == null || cutoutUrl == null) {
      setState(() {
        _loading = false;
        _loadError = 'missing';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _decodeFromUrl(originalUrl),
        _decodeFromUrl(cutoutUrl),
      ]);
      if (!mounted) return;
      setState(() {
        _original = results[0];
        _cutout = results[1];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'load';
      });
    }
  }

  /// Decode a network image WITHOUT the app's auth interceptors (signed URLs need
  /// none) — Flutter's own image loader, which also caches the bytes.
  Future<ui.Image> _decodeFromUrl(String url) {
    final completer = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  // ── stroke input ───────────────────────────────────────────────────────────

  Size _fitSize(Size box, double aspect) {
    // BoxFit.contain: fit the image's aspect ratio inside [box].
    if (box.width / box.height > aspect) {
      return Size(box.height * aspect, box.height);
    }
    return Size(box.width, box.width / aspect);
  }

  Offset _norm(Offset local, Size fit) => Offset(
    (local.dx / fit.width).clamp(0.0, 1.0),
    (local.dy / fit.height).clamp(0.0, 1.0),
  );

  void _startStroke(Offset local, Size fit) {
    if (_strokes.length >= _maxStrokes) {
      if (!_atLimit) {
        _atLimit = true;
        wtmSnack(context, AppLocalizations.of(context).cutoutEditorLimit);
      }
      return;
    }
    _redo.clear();
    final stroke = _Stroke(_brush, _brushRadii[_brushSize]!);
    stroke.points.add(_norm(local, fit));
    setState(() {
      _strokes.add(stroke);
      _dirty = true;
    });
  }

  void _extendStroke(Offset local, Size fit) {
    if (_strokes.isEmpty) return;
    final stroke = _strokes.last;
    if (stroke.points.length >= _maxPointsPerStroke) return;
    setState(() => stroke.points.add(_norm(local, fit)));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redo.add(_strokes.removeLast());
      _dirty = _strokes.isNotEmpty;
      _atLimit = false;
    });
  }

  void _redoStroke() {
    if (_redo.isEmpty) return;
    setState(() {
      _strokes.add(_redo.removeLast());
      _dirty = true;
    });
  }

  void _reset() {
    setState(() {
      _strokes.clear();
      _redo.clear();
      _dirty = false;
      _atLimit = false;
    });
  }

  // ── save ─────────────────────────────────────────────────────────────────────

  /// Rasterise the base cutout alpha + strokes at FULL resolution into an RGBA
  /// PNG whose alpha channel is the corrected mask. `Picture.toImage` offloads
  /// the raster to the engine's raster thread, so the UI thread never blocks.
  Future<Uint8List> _renderMaskPng() async {
    final w = _original!.width;
    final h = _original!.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintMask(canvas, Size(w.toDouble(), h.toDouble()), _cutout!, _strokes);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _save() async {
    if (_saving) return; // duplicate-tap guard
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final png = await _renderMaskPng();
      final updated = await ref
          .read(wardrobeRepositoryProvider)
          .uploadCutoutMask(widget.item.id, png);
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (!mounted) return;
      _dirty = false;
      wtmSnack(context, l10n.cutoutEditorSaved);
      context.pop(updated);
    } on ApiException catch (e) {
      if (mounted) {
        wtmSnack(context, e.message); // retryable — edits are preserved
        setState(() => _saving = false);
      }
    } catch (_) {
      if (mounted) {
        wtmSnack(context, l10n.cutoutEditorSaveFailed);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmBack() async {
    final l10n = AppLocalizations.of(context);
    if (!_dirty) {
      if (mounted) context.pop();
      return;
    }
    final leave = await wtmConfirmDialog(
      context,
      title: l10n.cutoutEditorDiscardTitle,
      message: l10n.cutoutEditorDiscardMessage,
      confirmLabel: l10n.cutoutEditorDiscardConfirm,
      danger: true,
    );
    if (leave && mounted) context.pop();
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmBack();
      },
      child: Scaffold(
        backgroundColor: WtmColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _navBar(l10n),
              Expanded(child: _bodyForState(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WtmSpace.screenH,
        WtmSpace.s8,
        WtmSpace.screenH,
        WtmSpace.s8,
      ),
      child: Row(
        children: [
          WtmIconButton(
            WtmGlyph.back,
            semanticLabel: l10n.commonBack,
            onTap: _saving ? null : _confirmBack,
          ),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cutoutEditorTitle,
                  style: WtmType.h2.copyWith(fontSize: 18),
                ),
                Text(l10n.cutoutEditorSubtitle, style: WtmType.micro),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyForState(AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: WtmColors.gold,
          ),
        ),
      );
    }
    if (_loadError != null || _original == null || _cutout == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(WtmSpace.s22),
          child: WtmErrorState(
            title: l10n.errorGenericTitle,
            message: l10n.cutoutEditorLoadFailed,
            retryLabel: l10n.commonRetry,
            onRetry: _load,
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: _canvas()),
        _controls(l10n),
      ],
    );
  }

  Widget _canvas() {
    final aspect = _original!.width / _original!.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fitSize(constraints.biggest, aspect);
        return Center(
          child: InteractiveViewer(
            transformationController: _tc,
            panEnabled: _moveMode,
            scaleEnabled: _moveMode,
            minScale: 1,
            maxScale: 6,
            child: SizedBox(
              width: fit.width,
              height: fit.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _moveMode
                    ? null
                    : (d) => _startStroke(d.localPosition, fit),
                onPanStart: _moveMode
                    ? null
                    : (d) => _startStroke(d.localPosition, fit),
                onPanUpdate: _moveMode
                    ? null
                    : (d) => _extendStroke(d.localPosition, fit),
                child: CustomPaint(
                  size: fit,
                  painter: _CutoutPainter(
                    original: _original!,
                    cutout: _cutout!,
                    strokes: _strokes,
                    bg: _bg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controls(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WtmSpace.screenH,
        WtmSpace.s12,
        WtmSpace.screenH,
        WtmSpace.s10,
      ),
      decoration: const BoxDecoration(
        color: WtmColors.panel,
        border: Border(top: BorderSide(color: WtmColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Background preview toggle.
          Row(
            children: [
              _pill(
                l10n.cutoutEditorBgChecker,
                _bg == _Bg.checker,
                () => setState(() => _bg = _Bg.checker),
              ),
              const SizedBox(width: WtmSpace.s6),
              _pill(
                l10n.cutoutEditorBgWhite,
                _bg == _Bg.white,
                () => setState(() => _bg = _Bg.white),
              ),
              const SizedBox(width: WtmSpace.s6),
              _pill(
                l10n.cutoutEditorBgBlack,
                _bg == _Bg.black,
                () => setState(() => _bg = _Bg.black),
              ),
              const Spacer(),
              _iconBtn(
                Icons.open_with,
                l10n.cutoutEditorMove,
                _moveMode,
                () => setState(() => _moveMode = !_moveMode),
              ),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          // Brush mode + size.
          Row(
            children: [
              _pill(
                l10n.cutoutEditorErase,
                !_moveMode && _brush == _Brush.erase,
                () => setState(() {
                  _brush = _Brush.erase;
                  _moveMode = false;
                }),
              ),
              const SizedBox(width: WtmSpace.s6),
              _pill(
                l10n.cutoutEditorRestore,
                !_moveMode && _brush == _Brush.restore,
                () => setState(() {
                  _brush = _Brush.restore;
                  _moveMode = false;
                }),
              ),
              const Spacer(),
              _sizeDot(l10n.cutoutEditorBrushS, 0),
              const SizedBox(width: WtmSpace.s6),
              _sizeDot(l10n.cutoutEditorBrushM, 1),
              const SizedBox(width: WtmSpace.s6),
              _sizeDot(l10n.cutoutEditorBrushL, 2),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          // Undo / Redo / Reset.
          Row(
            children: [
              _iconBtn(
                Icons.undo,
                l10n.cutoutEditorUndo,
                false,
                _strokes.isEmpty ? null : _undo,
              ),
              const SizedBox(width: WtmSpace.s6),
              _iconBtn(
                Icons.redo,
                l10n.cutoutEditorRedo,
                false,
                _redo.isEmpty ? null : _redoStroke,
              ),
              const SizedBox(width: WtmSpace.s6),
              _iconBtn(
                Icons.restart_alt,
                l10n.cutoutEditorReset,
                false,
                _strokes.isEmpty ? null : _reset,
              ),
            ],
          ),
          const SizedBox(height: WtmSpace.s12),
          GradientCta(
            label: _saving ? l10n.cutoutEditorSaving : l10n.cutoutEditorSave,
            icon: _saving
                ? null
                : const WtmIcon(
                    WtmGlyph.check,
                    size: 15,
                    color: WtmColors.ctaText,
                  ),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? WtmColors.gold.withValues(alpha: 0.16) : WtmColors.bg,
          borderRadius: BorderRadius.circular(WtmRadius.chip),
          border: Border.all(color: on ? WtmColors.gold : WtmColors.line),
        ),
        child: Text(
          label,
          style: WtmType.micro.copyWith(
            color: on ? WtmColors.gold : WtmColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _sizeDot(String label, int size) {
    final on = !_moveMode && _brushSize == size;
    final diameter = 10.0 + size * 6;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => setState(() {
          _brushSize = size;
          _moveMode = false;
        }),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? WtmColors.gold.withValues(alpha: 0.16) : WtmColors.bg,
            borderRadius: BorderRadius.circular(WtmRadius.chip),
            border: Border.all(color: on ? WtmColors.gold : WtmColors.line),
          ),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? WtmColors.gold : WtmColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, bool on, VoidCallback? onTap) {
    final color = onTap == null
        ? WtmColors.faint
        : (on ? WtmColors.gold : WtmColors.text);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? WtmColors.gold.withValues(alpha: 0.16) : WtmColors.bg,
            borderRadius: BorderRadius.circular(WtmRadius.button),
            border: Border.all(color: on ? WtmColors.gold : WtmColors.line),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Draws the base cutout alpha + [strokes] into [canvas] at [size], as the layer's
/// alpha channel (used both for the live preview mask and the saved mask PNG).
/// Erase strokes REMOVE alpha (dstOut); Restore strokes ADD alpha (opaque white).
/// A blurred boundary gives a soft, non-jagged edge. Shared so the preview and the
/// saved output replay the IDENTICAL normalized strokes.
void _paintMask(
  Canvas canvas,
  Size size,
  ui.Image cutout,
  List<_Stroke> strokes,
) {
  final dst = Offset.zero & size;
  final cutSrc = Rect.fromLTWH(
    0,
    0,
    cutout.width.toDouble(),
    cutout.height.toDouble(),
  );
  canvas.drawImageRect(
    cutout,
    cutSrc,
    dst,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final minEdge = size.shortestSide;
  for (final stroke in strokes) {
    final r = stroke.radius * minEdge;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * 2
      ..color = const Color(0xFFFFFFFF)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        (r * 0.35).clamp(0.5, 40.0),
      )
      ..blendMode = stroke.brush == _Brush.erase
          ? BlendMode.dstOut
          : BlendMode.srcOver;
    if (stroke.points.length == 1) {
      final p = Offset(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = paint.color
          ..maskFilter = paint.maskFilter
          ..blendMode = paint.blendMode,
      );
      continue;
    }
    final path = Path()
      ..moveTo(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
    for (final pt in stroke.points.skip(1)) {
      path.lineTo(pt.dx * size.width, pt.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }
}

class _CutoutPainter extends CustomPainter {
  _CutoutPainter({
    required this.original,
    required this.cutout,
    required this.strokes,
    required this.bg,
  });

  final ui.Image original;
  final ui.Image cutout;
  final List<_Stroke> strokes;
  final _Bg bg;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintBackground(canvas, size, rect);
    // Original, masked by (base cutout alpha ± strokes), over the background.
    canvas.saveLayer(rect, Paint());
    canvas.drawImageRect(
      original,
      Rect.fromLTWH(
        0,
        0,
        original.width.toDouble(),
        original.height.toDouble(),
      ),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
    _paintMask(canvas, size, cutout, strokes);
    canvas.restore();
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, Size size, Rect rect) {
    switch (bg) {
      case _Bg.white:
        canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
        return;
      case _Bg.black:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
        return;
      case _Bg.checker:
        const cell = 14.0;
        final light = Paint()..color = const Color(0xFF2A2436);
        final dark = Paint()..color = const Color(0xFF1B1626);
        canvas.drawRect(rect, dark);
        for (double y = 0; y < size.height; y += cell) {
          for (double x = 0; x < size.width; x += cell) {
            if (((x ~/ cell) + (y ~/ cell)).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(x, y, cell, cell).intersect(rect),
                light,
              );
            }
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter old) =>
      old.original != original ||
      old.cutout != cutout ||
      old.bg != bg ||
      old.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          old.strokes.isNotEmpty &&
          old.strokes.last.points.length != strokes.last.points.length);
}
