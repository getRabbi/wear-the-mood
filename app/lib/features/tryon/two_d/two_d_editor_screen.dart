import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../social/compose_post_screen.dart';
import '../models/studio_models.dart';
import 'body_anchor.dart';
import 'color_variants.dart';
import 'pose_service.dart';
import 'two_d_models.dart';
import 'two_d_tryon_service.dart';

/// Arguments for the 2D editor route (passed via `GoRouter` `extra`): a base photo
/// + the outfit stack of layers to compose.
class TwoDEditorArgs {
  const TwoDEditorArgs({required this.bodyImageUrl, required this.layers});

  final String bodyImageUrl;
  final List<TryOnLayer> layers;
}

/// The FREE 2D Outfit Stack editor: drops every selected piece over the body
/// photo (auto-placed by category), then lets the user select a layer and
/// move / pinch-resize / rotate / flip / fade / reorder / delete it — and
/// composites the result locally (no AI endpoint, no credits).
class TwoDEditorScreen extends ConsumerStatefulWidget {
  const TwoDEditorScreen({super.key, required this.args});

  final TwoDEditorArgs args;

  @override
  ConsumerState<TwoDEditorScreen> createState() => _TwoDEditorScreenState();
}

enum _Phase { edit, result }

/// Bundled, procedural backdrops behind the body (Capability 5) — gradients only,
/// no image assets and no network, so they stay instant + free. Rendered in the
/// canvas (incl. the contain letterbox) and baked into the export.
enum _Backdrop {
  photo,
  studio,
  gradient,
  editorial;

  String label(AppLocalizations l10n) => switch (this) {
        _Backdrop.photo => l10n.tryOn2dBgPhoto,
        _Backdrop.studio => l10n.tryOn2dBgStudio,
        _Backdrop.gradient => l10n.tryOn2dBgGradient,
        _Backdrop.editorial => l10n.tryOn2dBgEditorial,
      };

  Decoration get decoration => switch (this) {
        _Backdrop.photo => const BoxDecoration(color: AppColors.paperAlt),
        _Backdrop.studio => const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.15,
              colors: [Color(0xFFFDFCFA), Color(0xFFE4E0DA)],
            ),
          ),
        _Backdrop.gradient => const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.accentSoft, AppColors.paper],
            ),
          ),
        _Backdrop.editorial => const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B2B2B), Color(0xFF555154)],
            ),
          ),
      };
}

/// One-tap colour-grade "look" applied to the WHOLE composite (Capability 6) —
/// subtle ColorFilter.matrix grades, baked into the export.
enum _LookFilter {
  none,
  warm,
  cool,
  mono;

  String label(AppLocalizations l10n) => switch (this) {
        _LookFilter.none => l10n.tryOn2dLookNone,
        _LookFilter.warm => l10n.tryOn2dLookWarm,
        _LookFilter.cool => l10n.tryOn2dLookCool,
        _LookFilter.mono => l10n.tryOn2dColorMono,
      };

  ColorFilter? get filter => switch (this) {
        _LookFilter.none => null,
        _LookFilter.warm => const ColorFilter.matrix([
            1.07, 0, 0, 0, 4, //
            0, 1.0, 0, 0, 0, //
            0, 0, 0.92, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
        _LookFilter.cool => const ColorFilter.matrix([
            0.93, 0, 0, 0, 0, //
            0, 1.0, 0, 0, 0, //
            0, 0, 1.07, 0, 4, //
            0, 0, 0, 1, 0,
          ]),
        _LookFilter.mono => ColorFilter.matrix(greyscaleMatrix()),
      };
}

/// Applies a colour-grade only when [filter] is non-null (else passes [child]
/// through). Wraps the composite so the look is captured in the export.
class _Graded extends StatelessWidget {
  const _Graded({required this.filter, required this.child});

  final ColorFilter? filter;
  final Widget child;

  @override
  Widget build(BuildContext context) => filter == null
      ? child
      : ColorFiltered(colorFilter: filter!, child: child);
}

class _TwoDEditorScreenState extends ConsumerState<TwoDEditorScreen> {
  final _boundaryKey = GlobalKey();

  late final _bodyProvider = CachedNetworkImageProvider(widget.args.bodyImageUrl);
  late final Map<String, ImageProvider> _providers = {
    for (final l in widget.args.layers)
      l.id: CachedNetworkImageProvider(l.imageUrl),
  };

  // Render order = back → front, auto-ordered by garment type on entry so a full
  // outfit stacks sensibly (Capability 3); the user can still reorder by hand.
  late List<TryOnLayer> _layers = _orderByZ(widget.args.layers);
  late String? _selectedId = _layers.isEmpty ? null : _layers.last.id;

  /// Hidden layers (Capability 3 show/hide) — session-local, not on the model.
  /// Hidden pieces aren't rendered or exported but stay selectable to unhide.
  final Set<String> _hidden = {};

  /// Per-layer colour variant index into [kColorVariants] (Capability 4); absent
  /// or 0 = original. Session-local (no model change).
  final Map<String, int> _variant = {};

  /// Stable sort by 2D stacking rank (back → front), keeping selection order
  /// within the same rank.
  static List<TryOnLayer> _orderByZ(List<TryOnLayer> layers) {
    final indexed = [for (var i = 0; i < layers.length; i++) (i, layers[i])];
    indexed.sort((a, b) {
      final r = garmentZRank(a.$2.category).compareTo(garmentZRank(b.$2.category));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  // Gesture anchors for the selected layer.
  Offset _startOffset = Offset.zero;
  double _startScale = 1;
  double _startRotation = 0;
  Offset _startFocal = Offset.zero;

  bool _precached = false;
  bool _ready = false;
  bool _busy = false;
  _Phase _phase = _Phase.edit;
  Uint8List? _result;

  // Body-anchored placement (Capability 1): on-device pose + the body image's
  // aspect. Null until pose resolves (or if it fails) → category heuristic.
  BodyPose? _pose;
  double? _imageAspect;

  // Manual-fit snap guides (Capability 2): show body-landmark lines + snap the
  // dragged layer to them. _canvasSize is cached from the canvas LayoutBuilder so
  // the gesture handler can map landmarks ↔ canvas pixels.
  bool _dragging = false;
  Size? _canvasSize;

  // Selectable backdrop behind the body (Capability 5) — default keeps the photo.
  _Backdrop _backdrop = _Backdrop.photo;

  // Composite colour-grade "look" (Capability 6) — default none.
  _LookFilter _look = _LookFilter.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    Future.wait([
      precacheImage(_bodyProvider, context),
      for (final p in _providers.values) precacheImage(p, context),
    ]).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
    // Anchor garments to the real body (on-device, free) — refines placement
    // once it resolves; the editor is usable immediately on the heuristic.
    _detectPose();
  }

  /// Resolve the body image, then run on-device pose detection. Fully optional:
  /// any failure leaves [_pose] null so placement falls back to the heuristic.
  Future<void> _detectPose() async {
    try {
      final image = await _resolveImage(_bodyProvider);
      final aspect = image.width / image.height;
      final pose = await ref.read(poseServiceProvider).detect(image);
      if (!mounted) return;
      setState(() {
        _imageAspect = aspect;
        _pose = pose;
      });
    } catch (_) {
      // keep the heuristic — 2D stays fully functional
    }
  }

  Future<ui.Image> _resolveImage(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, _) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  TryOnLayer? get _selected {
    for (final l in _layers) {
      if (l.id == _selectedId) return l;
    }
    return null;
  }

  void _mutateSelected(TryOnLayer Function(TryOnLayer) f) {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _layers = [
        for (final l in _layers) if (l.id == id) f(l) else l,
      ];
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    final s = _selected;
    if (s == null) return;
    _startOffset = Offset(s.x, s.y);
    _startScale = s.scale;
    _startRotation = s.rotation;
    _startFocal = d.focalPoint;
    setState(() => _dragging = true); // surface the snap guides
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final sel = _selected;
    if (sel == null) return;
    final delta = d.focalPoint - _startFocal;
    var newY = _startOffset.dy + delta.dy;

    // Snap the layer's vertical centre to a nearby body-landmark guide — only
    // during a pure drag (one finger, no active pinch), so it never fights
    // resize/rotate (Capability 2).
    final canvas = _canvasSize;
    if (canvas != null && d.pointerCount <= 1 && (d.scale - 1).abs() < 0.02) {
      final guides = _guideYs(canvas);
      if (guides.isNotEmpty) {
        final vc = _layerVerticalCenter(sel, canvas);
        final centerY = vc * canvas.height + newY;
        const threshold = 14.0;
        var bestDist = threshold;
        for (final g in guides) {
          final dist = (g - centerY).abs();
          if (dist < bestDist) {
            bestDist = dist;
            newY = g - vc * canvas.height; // snap centre onto the guide
          }
        }
      }
    }

    _mutateSelected((l) => l.copyWith(
      x: _startOffset.dx + delta.dx,
      y: newY,
      scale: (_startScale * d.scale).clamp(0.2, 5.0),
      rotation: _startRotation + d.rotation,
    ));
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragging) setState(() => _dragging = false);
  }

  /// The selected layer's auto vertical centre (canvas fraction) — mirrors
  /// [_LayerView]: pose-anchored when available, else the category heuristic.
  double _layerVerticalCenter(TryOnLayer layer, Size canvas) {
    if (_pose != null && _imageAspect != null) {
      final ap = anchoredPlacement(layer.category, _pose!);
      if (ap != null) {
        return toCanvasPlacement(ap, canvas, _imageAspect!).verticalCenter;
      }
    }
    return garmentPlacement(layer.category).verticalCenter;
  }

  /// Canvas-Y positions of the body landmarks (shoulders/hips/knees/ankles) to
  /// draw + snap to. Empty when there's no pose.
  List<double> _guideYs(Size canvas) {
    final pose = _pose;
    final aspect = _imageAspect;
    if (pose == null || aspect == null) return const [];
    final rect = containImageRect(canvas, aspect);
    return [
      for (final p in [
        pose.shoulderCenter,
        pose.hipCenter,
        pose.kneeCenter,
        pose.ankleCenter,
      ])
        if (p != null) rect.top + p.dy * rect.height,
    ];
  }

  void _bringForward() {
    final id = _selectedId;
    if (id == null) return;
    final i = _layers.indexWhere((l) => l.id == id);
    if (i < 0 || i >= _layers.length - 1) return;
    setState(() {
      final next = [..._layers];
      final tmp = next[i];
      next[i] = next[i + 1];
      next[i + 1] = tmp;
      _layers = next;
    });
  }

  void _sendBack() {
    final id = _selectedId;
    if (id == null) return;
    final i = _layers.indexWhere((l) => l.id == id);
    if (i <= 0) return;
    setState(() {
      final next = [..._layers];
      final tmp = next[i];
      next[i] = next[i - 1];
      next[i - 1] = tmp;
      _layers = next;
    });
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _layers = [for (final l in _layers) if (l.id != id) l];
      _hidden.remove(id);
      _variant.remove(id);
      _selectedId = _layers.isEmpty ? null : _layers.last.id;
    });
  }

  /// Pick a colour variant for the selected garment (Capability 4).
  Future<void> _pickColor() async {
    final id = _selectedId;
    final layer = _selected;
    if (id == null || layer == null) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _ColorVariantSheet(
        imageUrl: layer.imageUrl,
        selected: _variant[id] ?? 0,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (picked == 0) {
          _variant.remove(id);
        } else {
          _variant[id] = picked;
        }
      });
    }
  }

  /// Pick the backdrop behind the body (Capability 5).
  Future<void> _pickBackdrop() async {
    final picked = await showModalBottomSheet<_Backdrop>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _BackdropSheet(selected: _backdrop),
    );
    if (picked != null && mounted) setState(() => _backdrop = picked);
  }

  /// Pick the composite colour-grade look (Capability 6).
  Future<void> _pickLook() async {
    final picked = await showModalBottomSheet<_LookFilter>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _LookSheet(selected: _look),
    );
    if (picked != null && mounted) setState(() => _look = picked);
  }

  /// Toggle the selected layer's visibility (Capability 3) — experiment with a
  /// look without deleting a piece.
  void _toggleHidden() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      if (!_hidden.remove(id)) _hidden.add(id);
    });
  }

  /// Reset the selected layer's transform back to its auto-placement default
  /// (position, scale, rotation, opacity, flip) — undo manual fiddling on one
  /// piece without removing it.
  void _resetSelected() => _mutateSelected(
        (l) => l.copyWith(
          x: 0,
          y: 0,
          scale: 1,
          rotation: 0,
          opacity: 1,
          flipX: false,
        ),
      );

  Future<void> _done() async {
    if (_busy || _layers.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    // Deselect so no selection chrome is baked into the export.
    setState(() {
      _selectedId = null;
      _busy = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    final bytes = await ref.read(twoDTryOnServiceProvider).capture(_boundaryKey);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.tryOn2dCaptureError)));
      return;
    }
    ref.read(twoDResultsProvider.notifier).add(TwoDResult(bytes: bytes));
    setState(() {
      _result = bytes;
      _phase = _Phase.result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isResult = _phase == _Phase.result;
    return Scaffold(
      appBar: AppBar(
        title: Text(isResult ? l10n.tryOn2dResultTitle : l10n.tryOn2dEditorTitle),
        actions: [
          if (!isResult) ...[
            IconButton(
              icon: const Icon(Icons.auto_fix_high_rounded),
              tooltip: l10n.tryOn2dLook,
              onPressed: _pickLook,
            ),
            IconButton(
              icon: const Icon(Icons.wallpaper_rounded),
              tooltip: l10n.tryOn2dBackground,
              onPressed: _pickBackdrop,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: !_ready
            ? const Center(child: CircularProgressIndicator())
            : isResult
                ? _ResultView(
                    bytes: _result!,
                    bodyImageUrl: widget.args.bodyImageUrl,
                    onAnother: () => context.pop(),
                    onEdit: () => setState(() => _phase = _Phase.edit),
                  )
                : _editor(l10n),
      ),
    );
  }

  Widget _editor(AppLocalizations l10n) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      // The look grades the whole composite (incl. backdrop),
                      // captured in the export.
                      child: _Graded(
                        filter: _look.filter,
                        child: DecoratedBox(
                          decoration: _backdrop.decoration,
                          child: LayoutBuilder(
                          builder: (context, constraints) {
                            _canvasSize = constraints.biggest; // cache for snap math
                            final guides = _dragging
                                ? _guideYs(constraints.biggest)
                                : const <double>[];
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image(image: _bodyProvider, fit: BoxFit.contain),
                                for (final layer in _layers)
                                  if (!_hidden.contains(layer.id))
                                    _LayerView(
                                      layer: layer,
                                      provider: _providers[layer.id]!,
                                      selected: layer.id == _selectedId,
                                      pose: _pose,
                                      imageAspect: _imageAspect,
                                      colorFilter: kColorVariants[
                                              _variant[layer.id] ?? 0]
                                          .filter,
                                    ),
                                // Subtle body-landmark guides, only while dragging
                                // (so they're never baked into the export).
                                if (guides.isNotEmpty)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _SnapGuidePainter(guides),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Controls(
              layers: _layers,
              selectedId: _selectedId,
              hiddenIds: _hidden,
              onSelect: (id) => setState(() => _selectedId = id),
              opacity: _selected?.opacity ?? 1,
              onOpacity: (v) => _mutateSelected((l) => l.copyWith(opacity: v)),
              onFlip: () => _mutateSelected((l) => l.copyWith(flipX: !l.flipX)),
              onReset: _resetSelected,
              onToggleHidden: _toggleHidden,
              selectedHidden:
                  _selectedId != null && _hidden.contains(_selectedId),
              onColor: _pickColor,
              onForward: _bringForward,
              onBack: _sendBack,
              onDelete: _deleteSelected,
              onDone: _done,
            ),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

/// One transformed garment layer rendered over the body. Auto-placed by real
/// body landmarks when a [pose] is available (Capability 1), else by the category
/// heuristic. Manual transforms (x/y/scale/rotation) layer on top of the auto-fit.
class _LayerView extends StatelessWidget {
  const _LayerView({
    required this.layer,
    required this.provider,
    required this.selected,
    this.pose,
    this.imageAspect,
    this.colorFilter,
  });

  final TryOnLayer layer;
  final ImageProvider provider;
  final bool selected;
  final BodyPose? pose;
  final double? imageAspect;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Prefer body-anchored placement (from pose landmarks); fall back to the
        // category heuristic when there's no usable pose for this garment.
        double widthFactor;
        double verticalCenter;
        double anchorTilt = 0;
        final ap = (pose != null && imageAspect != null)
            ? anchoredPlacement(layer.category, pose!)
            : null;
        if (ap != null) {
          final cp = toCanvasPlacement(
            ap,
            Size(c.maxWidth, c.maxHeight),
            imageAspect!,
          );
          widthFactor = cp.widthFactor;
          verticalCenter = cp.verticalCenter;
          anchorTilt = cp.tilt;
        } else {
          final place = garmentPlacement(layer.category);
          widthFactor = place.widthFactor;
          verticalCenter = place.verticalCenter;
        }
        final baseW = c.maxWidth * widthFactor;
        final autoDy = (verticalCenter - 0.5) * c.maxHeight;
        return Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(layer.x, autoDy + layer.y, 0, 1)
              ..rotateZ(layer.rotation + anchorTilt)
              ..scaleByDouble(
                layer.flipX ? -layer.scale : layer.scale,
                layer.scale,
                1,
                1,
              ),
            child: Opacity(
              opacity: layer.opacity,
              child: Container(
                width: baseW,
                decoration: selected
                    ? BoxDecoration(
                        border: Border.all(color: AppColors.accent, width: 2),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      )
                    : null,
                child: Stack(
                  children: [
                    // Soft drop shadow — grounds the cutout on the body so it
                    // doesn't look pasted (Capability 6). A blurred, offset black
                    // silhouette of the same garment alpha.
                    Transform.translate(
                      offset: const Offset(0, 4),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                        child: Opacity(
                          opacity: 0.22,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                                Colors.black, BlendMode.srcATop),
                            child: Image(
                              image: provider,
                              width: baseW,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (colorFilter == null)
                      Image(
                        image: provider,
                        width: baseW,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      )
                    else
                      ColorFiltered(
                        colorFilter: colorFilter!,
                        child: Image(
                          image: provider,
                          width: baseW,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Subtle dashed alignment guides at the body landmarks, shown only while
/// dragging (Capability 2). Lives over the canvas but is gated on `_dragging`,
/// so it's never baked into the exported composite.
class _SnapGuidePainter extends CustomPainter {
  const _SnapGuidePainter(this.ys);

  final List<double> ys;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const dash = 8.0;
    const gap = 6.0;
    for (final y in ys) {
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
        x += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_SnapGuidePainter old) {
    if (old.ys.length != ys.length) return true;
    for (var i = 0; i < ys.length; i++) {
      if (old.ys[i] != ys[i]) return true;
    }
    return false;
  }
}

/// Colour-variant picker (Capability 4): the selected garment recoloured by each
/// on-device filter, so the preview is the real piece in each colour.
class _ColorVariantSheet extends StatelessWidget {
  const _ColorVariantSheet({required this.imageUrl, required this.selected});

  final String imageUrl;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tryOn2dColor, style: text.headlineSmall),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (var i = 0; i < kColorVariants.length; i++)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.paperAlt,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: i == selected
                                  ? AppColors.accent
                                  : AppColors.glassBorder,
                              width: i == selected ? 2 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Builder(
                            builder: (_) {
                              final filter = kColorVariants[i].filter;
                              final img = CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.contain,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.checkroom_outlined,
                                  size: 18,
                                  color: AppColors.graphite,
                                ),
                              );
                              return filter == null
                                  ? img
                                  : ColorFiltered(colorFilter: filter, child: img);
                            },
                          ),
                        ),
                        if (i == 0 || i == kColorVariants.length - 1) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            i == 0
                                ? l10n.tryOn2dColorOriginal
                                : l10n.tryOn2dColorMono,
                            style: text.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }
}

/// Composite look picker (Capability 6): each grade previewed on a neutral
/// reference gradient so warm/cool/mono read at a glance.
class _LookSheet extends StatelessWidget {
  const _LookSheet({required this.selected});

  final _LookFilter selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tryOn2dLook, style: text.headlineSmall),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                for (final look in _LookFilter.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(look),
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  border: Border.all(
                                    color: look == selected
                                        ? AppColors.accent
                                        : AppColors.glassBorder,
                                    width: look == selected ? 2 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  child: _Graded(
                                    filter: look.filter,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            AppColors.accentSoft,
                                            AppColors.mist,
                                          ],
                                        ),
                                      ),
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              look.label(l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: look == selected
                                    ? AppColors.accent
                                    : AppColors.graphite,
                                fontWeight: look == selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }
}

/// Backdrop picker (Capability 5): preview swatches of each procedural backdrop.
class _BackdropSheet extends StatelessWidget {
  const _BackdropSheet({required this.selected});

  final _Backdrop selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tryOn2dBackground, style: text.headlineSmall),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                for (final b in _Backdrop.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(b),
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio: 0.72,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  border: Border.all(
                                    color: b == selected
                                        ? AppColors.accent
                                        : AppColors.glassBorder,
                                    width: b == selected ? 2 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  child: DecoratedBox(
                                    decoration: b.decoration,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              b.label(l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: b == selected
                                    ? AppColors.accent
                                    : AppColors.graphite,
                                fontWeight: b == selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.layers,
    required this.selectedId,
    required this.hiddenIds,
    required this.onSelect,
    required this.opacity,
    required this.onOpacity,
    required this.onFlip,
    required this.onReset,
    required this.onToggleHidden,
    required this.selectedHidden,
    required this.onColor,
    required this.onForward,
    required this.onBack,
    required this.onDelete,
    required this.onDone,
  });

  final List<TryOnLayer> layers;
  final String? selectedId;
  final Set<String> hiddenIds;
  final ValueChanged<String> onSelect;
  final double opacity;
  final ValueChanged<double> onOpacity;
  final VoidCallback onFlip;
  final VoidCallback onReset;
  final VoidCallback onToggleHidden;
  final bool selectedHidden;
  final VoidCallback onColor;
  final VoidCallback onForward;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final hasSelection = selectedId != null;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layers panel (top = front). Tap a thumbnail to select it.
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true, // show front-most first
                  itemCount: layers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
                  itemBuilder: (_, i) {
                    final layer = layers[i];
                    final sel = layer.id == selectedId;
                    final hidden = hiddenIds.contains(layer.id);
                    return GestureDetector(
                      onTap: () => onSelect(layer.id),
                      child: Container(
                        width: 48,
                        decoration: BoxDecoration(
                          color: AppColors.paperAlt,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: sel ? AppColors.accent : AppColors.glassBorder,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: Opacity(
                                opacity: hidden ? 0.35 : 1,
                                child: CachedNetworkImage(
                                  imageUrl: layer.imageUrl,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.checkroom_outlined,
                                    size: 16,
                                    color: AppColors.graphite,
                                  ),
                                ),
                              ),
                            ),
                            if (hidden)
                              const Center(
                                child: Icon(Icons.visibility_off_rounded,
                                    size: 16, color: AppColors.graphite),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  const Icon(Icons.opacity_rounded,
                      size: 18, color: AppColors.lavender),
                  Expanded(
                    child: Slider(
                      value: opacity,
                      min: 0.3,
                      max: 1,
                      onChanged: hasSelection ? onOpacity : null,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Tool(icon: Icons.flip_rounded, label: l10n.tryOn2dFlip, onTap: hasSelection ? onFlip : null),
                  _Tool(
                    icon: selectedHidden
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    label: l10n.tryOn2dToggleVisible,
                    onTap: hasSelection ? onToggleHidden : null,
                  ),
                  _Tool(
                    icon: Icons.palette_outlined,
                    label: l10n.tryOn2dColor,
                    onTap: hasSelection ? onColor : null,
                  ),
                  _Tool(icon: Icons.restart_alt_rounded, label: l10n.tryOn2dReset, onTap: hasSelection ? onReset : null),
                  _Tool(icon: Icons.flip_to_front_rounded, label: l10n.studioBringForward, onTap: hasSelection ? onForward : null),
                  _Tool(icon: Icons.flip_to_back_rounded, label: l10n.studioSendBack, onTap: hasSelection ? onBack : null),
                  _Tool(icon: Icons.delete_outline_rounded, label: l10n.studioDeleteLayer, onTap: hasSelection ? onDelete : null, danger: true),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(l10n.studioSelectLayerHint, style: text.bodySmall),
              const SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: l10n.tryOn2dDone,
                icon: Icons.check_rounded,
                onPressed: layers.isEmpty ? null : onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.muted
        : (danger ? AppColors.danger : AppColors.lavender);
    return Expanded(
      child: Tooltip(
        message: label,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// The polished 2D result (Capability 8): an editorial reveal of the styled look,
/// a before/after toggle (your photo ↔ styled), the free quick-actions, and a
/// soft "See it in HD — AI Realistic" upsell to the premium try-on.
class _ResultView extends ConsumerStatefulWidget {
  const _ResultView({
    required this.bytes,
    required this.bodyImageUrl,
    required this.onAnother,
    required this.onEdit,
  });

  final Uint8List bytes;
  final String bodyImageUrl;
  final VoidCallback onAnother;
  final VoidCallback onEdit;

  @override
  ConsumerState<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends ConsumerState<_ResultView> {
  bool _showBefore = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    void snack(String m) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            // One-shot reveal (scale + fade) on mount — reuses the try-on
            // "wow" pattern; instant under reduce-motion.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion ? Duration.zero : AppMotion.base,
              curve: AppMotion.easing,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _showBefore
                          ? CachedNetworkImage(
                              imageUrl: widget.bodyImageUrl,
                              fit: BoxFit.contain,
                              errorWidget: (_, _, _) =>
                                  const ColoredBox(color: AppColors.paperAlt),
                            )
                          : Image.memory(widget.bytes, fit: BoxFit.contain),
                    ),
                    Positioned(
                      top: AppSpace.sm,
                      left: AppSpace.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.scrim,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _showBefore ? l10n.tryOnBefore : l10n.tryOnAfter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      l10n.tryOnBadgeFree.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(l10n.tryOn2dResultNote, style: text.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  _Action(
                    icon: Icons.bookmark_added_rounded,
                    label: l10n.tryOnSaveLook,
                    onTap: () => snack(l10n.tryOn2dSaved),
                  ),
                  _Action(
                    icon: Icons.compare_arrows_rounded,
                    label: l10n.tryOnCompare,
                    onTap: () => setState(() => _showBefore = !_showBefore),
                  ),
                  _Action(
                    icon: Icons.add_a_photo_outlined,
                    label: l10n.tryOnPostCommunity,
                    onTap: () => context.push(
                      AppRoute.socialCompose,
                      extra: ComposeArgs(presetPhoto: widget.bytes),
                    ),
                  ),
                  _Action(
                    icon: Icons.ios_share_rounded,
                    label: l10n.tryOnShare,
                    onTap: () async {
                      try {
                        await ref
                            .read(shareServiceProvider)
                            .shareImageBytes(widget.bytes,
                                text: l10n.postShareText);
                      } catch (_) {
                        snack(l10n.shareFailed);
                      }
                    },
                  ),
                  _Action(
                    icon: Icons.tune_rounded,
                    label: l10n.commonEdit,
                    onTap: widget.onEdit,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              // Soft, non-nagging upsell to photoreal AI HD.
              _UpgradeChip(
                label: l10n.tryOn2dUpgradeHd,
                onTap: () => context.push(AppRoute.paywall),
              ),
              const SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: l10n.tryOnTryAnother,
                icon: Icons.refresh_rounded,
                onPressed: widget.onAnother,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A soft accent-tinted chip that nudges toward premium AI HD without nagging.
class _UpgradeChip extends StatelessWidget {
  const _UpgradeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: AppColors.accentSoft,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpace.sm),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.accent),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.lavender),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}
