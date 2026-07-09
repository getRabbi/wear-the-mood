import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/uuid.dart';
import '../../../theme/wtm_colors.dart';
import '../../../theme/wtm_shapes.dart';
import '../../../theme/wtm_typography.dart';
import '../../../ui/community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../../../ui/mirror/wtm_mirror_flow.dart';
import '../../../ui/widgets/widgets.dart' as wtm;
import '../save_look_service.dart';
import '../models/studio_models.dart';
import 'body_anchor.dart';
import 'color_variants.dart';
import 'fit_memory.dart';
import 'mannequin.dart';
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
        _Backdrop.photo => const BoxDecoration(color: WtmColors.bg2),
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

class _TwoDEditorScreenState extends ConsumerState<TwoDEditorScreen>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();

  // ── Canvas zoom/pan (TWOD_ZOOM_ADJUST) ────────────────────────────────────
  // The whole composition (body + all layers) zooms/pans together so alignment
  // is preserved. Zoom is a view transform only — the export captures the
  // untransformed boundary, so it stays full-resolution at any zoom.
  static const _kMinScale = 0.8;
  static const _kMaxScale = 4.0;
  final _canvasController = TransformationController();
  late final AnimationController _zoomCtrl;
  Animation<Matrix4>? _zoomAnim;
  Offset _doubleTapLocal = Offset.zero;

  /// Canvas mode (pinch/pan the whole canvas) when nothing is selected;
  /// edit-item mode (move/scale/rotate THAT piece) when a layer is selected.
  bool get _canvasMode => _selectedId == null;

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

  // Avatar / mannequin mode (Capability 7): when there's no usable body photo we
  // map garments onto a procedural mannequin instead, so try-on always works.
  late final bool _hasPhoto = widget.args.bodyImageUrl.trim().isNotEmpty;
  late bool _mannequin = !_hasPhoto;

  // ── Fit memory (Phase 4) ───────────────────────────────────────────────────
  // Remembered manual placement per (user + body + wardrobe item), so adjusting a
  // piece once sticks next time. Local + free (secure storage) — no backend, no
  // credits. Keyed by the PRIMARY body chosen on entry; the transient mannequin
  // toggle doesn't create a separate memory.
  late final String _primaryBodyId = _hasPhoto
      ? FitMemoryService.normalizeBodyId(widget.args.bodyImageUrl)
      : 'mannequin';

  /// Saved fits for THIS session's layers, keyed by the layer's session id.
  Map<String, FitPlacement> _savedFits = {};
  bool _fitLoaded = false;
  bool _fitApplyScheduled = false;

  /// Pose + aspect actually driving placement: the synthetic mannequin pose when
  /// in mannequin mode, else the detected photo pose.
  BodyPose? get _activePose => _mannequin ? mannequinPose() : _pose;
  double? get _activeAspect => _mannequin ? kMannequinAspect : _imageAspect;

  @override
  void initState() {
    super.initState();
    _zoomCtrl = AnimationController(vsync: this, duration: AppMotion.base)
      ..addListener(() {
        final anim = _zoomAnim;
        if (anim != null) _canvasController.value = anim.value;
      });
  }

  @override
  void dispose() {
    _zoomCtrl.dispose();
    _canvasController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    if (kDebugMode) {
      debugPrint('[MoodMirror] 2D editor open → '
          'bodyImageUrl=${_hasPhoto ? widget.args.bodyImageUrl : "(mannequin)"}, '
          'layers=${widget.args.layers.length}');
    }
    Future.wait([
      if (_hasPhoto) precacheImage(_bodyProvider, context),
      for (final p in _providers.values) precacheImage(p, context),
    ]).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
    // Anchor garments to the real body (on-device, free) — refines placement
    // once it resolves; the editor is usable immediately on the heuristic.
    if (_hasPhoto) _detectPose();
    // Load any remembered manual fits for these pieces on this body (Phase 4).
    _loadFitMemory();
  }

  /// Load saved fits for the current layers (best-effort). Only wardrobe-backed
  /// layers can be remembered (a stable id is required); everything else keeps
  /// the smart auto-placement.
  Future<void> _loadFitMemory() async {
    Map<String, FitPlacement> byLayer = {};
    try {
      final userId = ref.read(authUserIdProvider);
      final all = await ref.read(fitMemoryServiceProvider).loadAll();
      for (final l in _layers) {
        final itemId = l.wardrobeItemId;
        if (itemId == null) continue;
        final saved = all[FitMemoryService.keyFor(
          userId: userId,
          bodyId: _primaryBodyId,
          itemId: itemId,
        )];
        if (saved != null) byLayer[l.id] = saved;
      }
    } catch (_) {
      byLayer = {}; // fit memory is optional — never block the editor
    }
    if (!mounted) return;
    setState(() {
      _savedFits = byLayer;
      _fitLoaded = true;
    });
  }

  /// Once the canvas is measured and saved fits are loaded, apply them a single
  /// time (converting the normalized offsets back to canvas pixels). Runs after
  /// the frame so it never calls setState during layout.
  void _maybeApplySavedFits(Size canvas) {
    if (_fitApplyScheduled ||
        !_fitLoaded ||
        _savedFits.isEmpty ||
        canvas.width <= 0 ||
        canvas.height <= 0) {
      return;
    }
    _fitApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _layers = [
          for (final l in _layers)
            if (_savedFits[l.id] case final p?)
              l.copyWith(
                x: p.nx * canvas.width,
                y: p.ny * canvas.height,
                scale: p.scale,
                rotation: p.rotation,
                opacity: p.opacity,
                flipX: p.flipX,
              )
            else
              l,
        ];
      });
    });
  }

  /// Persist the current manual placement of every wardrobe-backed layer, keyed
  /// by (user + body + item), so it reloads next time (Phase 4). Best-effort.
  Future<void> _persistFitMemory() async {
    final canvas = _canvasSize;
    if (canvas == null || canvas.width <= 0 || canvas.height <= 0) return;
    final userId = ref.read(authUserIdProvider);
    final now = DateTime.now();
    final entries = <String, FitPlacement>{};
    for (var i = 0; i < _layers.length; i++) {
      final l = _layers[i];
      final itemId = l.wardrobeItemId;
      if (itemId == null) continue;
      entries[FitMemoryService.keyFor(
        userId: userId,
        bodyId: _primaryBodyId,
        itemId: itemId,
      )] = FitPlacement(
        nx: l.x / canvas.width,
        ny: l.y / canvas.height,
        scale: l.scale,
        rotation: l.rotation,
        opacity: l.opacity,
        flipX: l.flipX,
        zIndex: i,
        aspect: canvas.width / canvas.height,
        updatedAt: now,
      );
    }
    if (entries.isEmpty) return;
    try {
      await ref.read(fitMemoryServiceProvider).saveAll(entries);
    } catch (_) {
      // fit memory is best-effort; a save failure never blocks the reveal
    }
  }

  /// The stored fit-memory key for a layer, or null if it can't be remembered.
  String? _fitKeyForLayer(TryOnLayer layer) {
    final itemId = layer.wardrobeItemId;
    if (itemId == null) return null;
    return FitMemoryService.keyFor(
      userId: ref.read(authUserIdProvider),
      bodyId: _primaryBodyId,
      itemId: itemId,
    );
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
    // Divide the finger movement by the current canvas zoom so dragging stays
    // 1:1 with the finger on-screen — i.e. fine, precise placement when zoomed
    // in (TWOD_ZOOM_ADJUST). Pinch scale/rotation are ratios, unaffected.
    final cs = _canvasController.value.getMaxScaleOnAxis();
    final delta = (d.focalPoint - _startFocal) / (cs == 0 ? 1 : cs);
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

  /// A tap on the canvas deselects → back to canvas (zoom/pan) mode. Selecting a
  /// piece (the strip below) re-enters edit-item mode.
  void _onCanvasTap() {
    if (_selectedId != null) setState(() => _selectedId = null);
  }

  /// Double-tap zooms in toward the tapped point, or resets to fit if already
  /// zoomed (TWOD_ZOOM_ADJUST).
  void _onDoubleTapZoom() {
    final scale = _canvasController.value.getMaxScaleOnAxis();
    if (scale > 1.05) {
      _animateCanvasTo(Matrix4.identity());
      return;
    }
    const target = 2.5;
    final p = _doubleTapLocal;
    _animateCanvasTo(
      Matrix4.identity()
        ..translateByDouble(p.dx, p.dy, 0, 1)
        ..scaleByDouble(target, target, 1, 1)
        ..translateByDouble(-p.dx, -p.dy, 0, 1),
    );
  }

  bool get _isZoomed => _canvasController.value.getMaxScaleOnAxis() > 1.05;

  /// Animate the canvas transform to [target] (instant under reduce-motion).
  void _animateCanvasTo(Matrix4 target) {
    if (MediaQuery.of(context).disableAnimations) {
      _canvasController.value = target;
      return;
    }
    _zoomAnim = Matrix4Tween(begin: _canvasController.value, end: target).animate(
      CurvedAnimation(parent: _zoomCtrl, curve: AppMotion.easing),
    );
    _zoomCtrl.forward(from: 0);
  }

  /// The selected layer's auto vertical centre (canvas fraction) — mirrors
  /// [_LayerView]: pose-anchored when available, else the category heuristic.
  double _layerVerticalCenter(TryOnLayer layer, Size canvas) {
    final pose = _activePose;
    final aspect = _activeAspect;
    if (pose != null && aspect != null) {
      final ap = anchoredPlacement(layer.category, pose);
      if (ap != null) {
        return toCanvasPlacement(ap, canvas, aspect).verticalCenter;
      }
    }
    return garmentPlacement(layer.category).verticalCenter;
  }

  /// Canvas-Y positions of the body landmarks (shoulders/hips/knees/ankles) to
  /// draw + snap to. Empty when there's no pose.
  List<double> _guideYs(Size canvas) {
    final pose = _activePose;
    final aspect = _activeAspect;
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

  /// One-tap "Center on body": snap the selected garment back to its sensible
  /// default placement (centred, upright, default scale) without touching its
  /// opacity/colour. The auto-placement math lives in [_LayerView]; clearing the
  /// manual x/y/scale/rotation returns the piece to it.
  void _autoFitSelected() {
    if (_selected == null) return;
    _mutateSelected(
      (l) => l.copyWith(x: 0, y: 0, scale: 1, rotation: 0, flipX: false),
    );
  }

  /// Reset the selected layer's transform back to its smart auto-placement
  /// default (position, scale, rotation, opacity, flip) and forget any saved fit
  /// for it (Phase 4), so it stays on the smart default next time too.
  void _resetSelected() {
    final layer = _selected;
    if (layer == null) return;
    final key = _fitKeyForLayer(layer);
    _mutateSelected(
      (l) => l.copyWith(
        x: 0,
        y: 0,
        scale: 1,
        rotation: 0,
        opacity: 1,
        flipX: false,
      ),
    );
    _savedFits.remove(layer.id);
    if (key != null) {
      // Fire-and-forget: forgetting a fit must never block the UI.
      ref.read(fitMemoryServiceProvider).remove(key);
    }
  }

  /// Reset EVERY piece to its smart auto-placement and forget all saved fits for
  /// this body (Phase 7). Non-destructive to the pieces themselves.
  void _resetAll() {
    if (_layers.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final keys = <String>[];
    for (final l in _layers) {
      final key = _fitKeyForLayer(l);
      if (key != null) keys.add(key);
    }
    setState(() {
      _layers = [
        for (final l in _layers)
          l.copyWith(x: 0, y: 0, scale: 1, rotation: 0, opacity: 1, flipX: false),
      ];
      _savedFits = {};
    });
    if (keys.isNotEmpty) ref.read(fitMemoryServiceProvider).removeAll(keys);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.tryOn2dResetAllDone)));
  }

  Future<void> _done() async {
    if (_busy || _layers.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    // Deselect so no selection chrome is baked into the export.
    setState(() {
      _selectedId = null;
      _busy = true;
    });
    // Remember every piece's manual fit for next time (Phase 4) — free + local.
    await _persistFitMemory();
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
      backgroundColor: WtmColors.bg,
      appBar: AppBar(
        backgroundColor: WtmColors.bg,
        foregroundColor: WtmColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isResult ? l10n.tryOn2dResultTitle : l10n.tryOn2dEditorTitle,
          style: WtmType.h2.copyWith(fontSize: 18),
        ),
        actions: [
          if (!isResult) ...[
            // Toggle photo ↔ mannequin (Capability 7) — only when a photo exists;
            // with no photo we stay on the mannequin.
            if (_hasPhoto)
              IconButton(
                icon: Icon(
                  Icons.accessibility_new_rounded,
                  color: _mannequin ? WtmColors.gold : WtmColors.muted,
                ),
                tooltip: l10n.tryOn2dMannequin,
                onPressed: () => setState(() => _mannequin = !_mannequin),
              ),
            IconButton(
              icon: const Icon(Icons.auto_fix_high_rounded,
                  color: WtmColors.muted),
              tooltip: l10n.tryOn2dLook,
              onPressed: _pickLook,
            ),
            IconButton(
              icon: const Icon(Icons.wallpaper_rounded, color: WtmColors.muted),
              tooltip: l10n.tryOn2dBackground,
              onPressed: _pickBackdrop,
            ),
            // Reset EVERY piece to its smart auto-fit (Phase 7); disabled when
            // there's nothing to reset.
            IconButton(
              icon: const Icon(Icons.settings_backup_restore_rounded,
                  color: WtmColors.muted),
              tooltip: l10n.tryOn2dResetAll,
              onPressed: _layers.isEmpty ? null : _resetAll,
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
                    // No "before" photo to compare against in mannequin mode.
                    bodyImageUrl: _mannequin ? '' : widget.args.bodyImageUrl,
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
                child: _stage(l10n),
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
              onAutoFit: _autoFitSelected,
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

  /// The try-on canvas with zoom/pan (TWOD_ZOOM_ADJUST). Two conflict-free modes:
  /// canvas mode (nothing selected) uses [InteractiveViewer] for pinch-zoom +
  /// clamped pan of the whole composition; edit-item mode (a piece selected)
  /// applies the same transform statically and routes pinch/drag to that piece.
  /// The export captures the untransformed [RepaintBoundary], so zoom never
  /// changes the saved image.
  Widget _stage(AppLocalizations l10n) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: RepaintBoundary(
        key: _boundaryKey,
        // The look grades the whole composite (incl. backdrop), captured in
        // the export.
        child: _Graded(
          filter: _look.filter,
          child: DecoratedBox(
            decoration: _backdrop.decoration,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _canvasSize = constraints.biggest; // cache for snap math
                // Apply remembered fits once the canvas is measured (Phase 4).
                _maybeApplySavedFits(constraints.biggest);
                final guides = _dragging
                    ? _guideYs(constraints.biggest)
                    : const <double>[];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_mannequin)
                      const Center(
                        child: AspectRatio(
                          aspectRatio: kMannequinAspect,
                          child: CustomPaint(painter: MannequinPainter()),
                        ),
                      )
                    else
                      Image(image: _bodyProvider, fit: BoxFit.contain),
                    for (final layer in _layers)
                      if (!_hidden.contains(layer.id))
                        _LayerView(
                          layer: layer,
                          provider: _providers[layer.id]!,
                          selected: layer.id == _selectedId,
                          imageAspect: _activeAspect,
                          colorFilter:
                              kColorVariants[_variant[layer.id] ?? 0].filter,
                        ),
                    // Subtle body-landmark guides, only while dragging (so they
                    // are never baked into the export).
                    if (guides.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _SnapGuidePainter(guides)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final Widget stage = _canvasMode
        // Canvas mode: pinch-zoom + clamped pan of the whole canvas.
        ? InteractiveViewer(
            transformationController: _canvasController,
            minScale: _kMinScale,
            maxScale: _kMaxScale,
            boundaryMargin: const EdgeInsets.all(64),
            clipBehavior: Clip.none,
            child: content,
          )
        // Edit-item mode: apply the current canvas transform statically, and let
        // the per-item gestures move/scale/rotate the selected piece.
        : AnimatedBuilder(
            animation: _canvasController,
            builder: (_, child) =>
                Transform(transform: _canvasController.value, child: child),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: content,
            ),
          );

    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onCanvasTap,
        onDoubleTapDown: (d) => _doubleTapLocal = d.localPosition,
        onDoubleTap: _onDoubleTapZoom,
        child: Stack(
          fit: StackFit.expand,
          children: [
            stage,
            // Subtle mode hint (top-left).
            Positioned(
              left: AppSpace.sm,
              top: AppSpace.sm,
              child: IgnorePointer(
                child: _ModeHint(
                  icon: _canvasMode
                      ? Icons.open_with_rounded
                      : Icons.touch_app_outlined,
                  text: _canvasMode
                      ? l10n.tryOn2dHintCanvas
                      : l10n.tryOn2dHintEdit,
                ),
              ),
            ),
            // Fit-to-screen, only when zoomed (top-right).
            Positioned(
              right: AppSpace.sm,
              top: AppSpace.sm,
              child: AnimatedBuilder(
                animation: _canvasController,
                builder: (_, _) => _isZoomed
                    ? _FitButton(
                        tooltip: l10n.tryOn2dFit,
                        onTap: () => _animateCanvasTo(Matrix4.identity()),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small, subtle pill hinting the active canvas/edit mode (TWOD_ZOOM_ADJUST).
class _ModeHint extends StatelessWidget {
  const _ModeHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.scrim,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact "fit to screen" control shown while the canvas is zoomed.
class _FitButton extends StatelessWidget {
  const _FitButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.scrim,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.fit_screen_outlined, color: Colors.white),
        onPressed: onTap,
      ),
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
    this.imageAspect,
    this.colorFilter,
  });

  final TryOnLayer layer;
  final ImageProvider provider;
  final bool selected;
  final double? imageAspect;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Deterministic, body-relative auto-placement (no pose anchoring): the
        // garment spawns UPRIGHT, sized to the body's contained width and
        // centred on the right region for its category — never huge, tilted, or
        // off-body. The user fine-tunes from this sensible default.
        final canvasSize = Size(c.maxWidth, c.maxHeight);
        final bodyRect = imageAspect != null
            ? containImageRect(canvasSize, imageAspect!)
            : Offset.zero & canvasSize;
        final place = garmentPlacement(layer.category);
        final baseW = bodyRect.width * place.widthFactor;
        final autoDy = bodyRect.top +
            place.verticalCenter * bodyRect.height -
            c.maxHeight / 2;
        return Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(layer.x, autoDy + layer.y, 0, 1)
              ..rotateZ(layer.rotation)
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
                // Subtle, premium selection (TWOD_ZOOM_ADJUST): a thin soft
                // accent outline + faint glow — not a loud box. The stroke/glow
                // are divided by the layer's own scale so they read ~constant
                // on screen however large the piece is scaled.
                decoration: selected
                    ? BoxDecoration(
                        border: Border.all(
                          // Clear, obvious gold selection outline (the stroke is
                          // divided by the layer's scale so it reads ~constant
                          // on screen however large the piece is scaled).
                          color: WtmColors.gold.withValues(alpha: 0.95),
                          width: (2.0 / layer.scale).clamp(0.75, 3.0),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [
                          BoxShadow(
                            color: WtmColors.gold.withValues(alpha: 0.3),
                            blurRadius: (12 / layer.scale).clamp(4.0, 16.0),
                            spreadRadius: 0.5,
                          ),
                        ],
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
                    // Corner handles — a clear "this piece is selected and can be
                    // moved / pinched / rotated" affordance. Purely visual
                    // (IgnorePointer); the whole layer stays the drag target.
                    // Deselected before export, so handles never bake in.
                    if (selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _HandlePainter(scale: layer.scale),
                          ),
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

/// Selection corner handles for the active layer — four rounded accent squares
/// pinned inside the piece's corners so it clearly reads as manipulable. Sized
/// inversely to the layer's [scale] so they stay ~constant on screen. Drawn
/// inset (not centred on the corner) so they're never clipped by the Stack.
class _HandlePainter extends CustomPainter {
  const _HandlePainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (11 / scale).clamp(4.0, 20.0);
    final fill = Paint()
      ..color = WtmColors.gold
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.5 / scale).clamp(0.5, 3.0)
      ..isAntiAlias = true;
    final radius = Radius.circular(s * 0.32);
    final corners = <Rect>[
      Rect.fromLTWH(0, 0, s, s),
      Rect.fromLTWH(size.width - s, 0, s, s),
      Rect.fromLTWH(0, size.height - s, s, s),
      Rect.fromLTWH(size.width - s, size.height - s, s, s),
    ];
    for (final r in corners) {
      final rr = RRect.fromRectAndRadius(r, radius);
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, ring);
    }
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.scale != scale;
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
      ..color = WtmColors.gold.withValues(alpha: 0.5)
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
    required this.onAutoFit,
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
  final VoidCallback onAutoFit;
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
    final hasSelection = selectedId != null;
    return Container(
      decoration: const BoxDecoration(
        color: WtmColors.panel,
        border: Border(top: BorderSide(color: WtmColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.s12,
            WtmSpace.s10,
            WtmSpace.s12,
            WtmSpace.s10,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layer thumbnails (front-most first). Tap to select.
              if (layers.isNotEmpty) ...[
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: layers.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: WtmSpace.s8),
                    itemBuilder: (_, i) {
                      final layer = layers[i];
                      final sel = layer.id == selectedId;
                      final hidden = hiddenIds.contains(layer.id);
                      return GestureDetector(
                        onTap: () => onSelect(layer.id),
                        child: Container(
                          width: 44,
                          decoration: BoxDecoration(
                            color: WtmColors.bg,
                            borderRadius: BorderRadius.circular(WtmRadius.tile),
                            border: Border.all(
                              color: sel ? WtmColors.gold : WtmColors.line,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Opacity(
                                  opacity: hidden ? 0.3 : 1,
                                  child: CachedNetworkImage(
                                    imageUrl: layer.imageUrl,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, _, _) => const Icon(
                                      Icons.checkroom_outlined,
                                      size: 16,
                                      color: WtmColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                              if (hidden)
                                const Center(
                                  child: Icon(Icons.visibility_off_rounded,
                                      size: 16, color: WtmColors.muted),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: WtmSpace.s8),
              ],
              // Opacity of the selected piece (gold track).
              Row(
                children: [
                  const Icon(Icons.opacity_rounded,
                      size: 16, color: WtmColors.muted),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: WtmColors.gold,
                        inactiveTrackColor: WtmColors.line,
                        thumbColor: WtmColors.gold,
                        overlayColor: WtmColors.gold.withValues(alpha: 0.12),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: opacity,
                        min: 0.3,
                        max: 1,
                        onChanged: hasSelection ? onOpacity : null,
                      ),
                    ),
                  ),
                ],
              ),
              // Tools — horizontally scrollable so nothing overflows on 360dp.
              // "Center" (auto-fit) leads, in gold, as the primary placement aid.
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _Tool(
                        icon: Icons.center_focus_strong_rounded,
                        label: l10n.tryOn2dCenter,
                        onTap: hasSelection ? onAutoFit : null,
                        highlight: true),
                    _Tool(
                        icon: Icons.flip_rounded,
                        label: l10n.tryOn2dFlip,
                        onTap: hasSelection ? onFlip : null),
                    _Tool(
                        icon: Icons.palette_outlined,
                        label: l10n.tryOn2dColor,
                        onTap: hasSelection ? onColor : null),
                    _Tool(
                        icon: selectedHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        label: l10n.tryOn2dToggleVisible,
                        onTap: hasSelection ? onToggleHidden : null),
                    _Tool(
                        icon: Icons.restart_alt_rounded,
                        label: l10n.tryOn2dReset,
                        onTap: hasSelection ? onReset : null),
                    _Tool(
                        icon: Icons.flip_to_front_rounded,
                        label: l10n.studioBringForward,
                        onTap: hasSelection ? onForward : null),
                    _Tool(
                        icon: Icons.flip_to_back_rounded,
                        label: l10n.studioSendBack,
                        onTap: hasSelection ? onBack : null),
                    _Tool(
                        icon: Icons.delete_outline_rounded,
                        label: l10n.studioDeleteLayer,
                        onTap: hasSelection ? onDelete : null,
                        danger: true),
                  ],
                ),
              ),
              const SizedBox(height: WtmSpace.s8),
              wtm.GradientCta(
                label: l10n.tryOn2dDone,
                icon: const wtm.WtmIcon(wtm.WtmGlyph.check,
                    size: 15, color: WtmColors.ctaText),
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
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  /// The primary "Center / Auto-fit" tool is tinted gold to stand out.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? WtmColors.muted.withValues(alpha: 0.4)
        : danger
            ? WtmColors.danger
            : highlight
                ? WtmColors.gold
                : WtmColors.text;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.micro.copyWith(fontSize: 9, color: color),
                ),
              ],
            ),
          ),
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
  bool _savingLook = false;

  /// Stable id for THIS result so a double-tap / re-save doesn't duplicate the
  /// look (§9). The 2D composite is in-memory, so there's no server id to reuse.
  late final String _lookId = uuidV4();

  /// Save the 2D look to Looks: upload the composite bytes to durable storage,
  /// then record it (§8). Awaited; surfaces a real error on failure.
  Future<void> _saveLook() async {
    if (_savingLook) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _savingLook = true);
    try {
      await ref
          .read(saveLookServiceProvider)
          .saveBytes(id: _lookId, bytes: widget.bytes);
      if (mounted) wtm.wtmSnack(context, l10n.tryOn2dSaved);
    } catch (_) {
      if (mounted) wtm.wtmSnack(context, l10n.tryOnLookSaveError);
    } finally {
      if (mounted) setState(() => _savingLook = false);
    }
  }

  /// Reveal the composite full-screen (pinch-zoom) — mirrors the Looks viewer.
  void _openFullscreen() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xF2050308),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: Image.memory(widget.bytes, fit: BoxFit.contain),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(WtmSpace.screenH),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: wtm.WtmIconButton(
                    wtm.WtmGlyph.back,
                    semanticLabel: MaterialLocalizations.of(dialogContext)
                        .backButtonTooltip,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Share the composite via the OS sheet (2D looks are free → watermarked).
  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(shareServiceProvider).shareImageBytes(
            widget.bytes,
            text: l10n.postShareText,
            watermark: true,
          );
    } catch (_) {
      if (mounted) wtm.wtmSnack(context, l10n.shareFailed);
    }
  }

  /// See it rendered for real: pre-select AI Couture and return to Step 3, which
  /// still holds this look's garments + the Step-1 body — so the metered render
  /// runs on the SAME body + garments, and the credit / Pro-Max gate still applies.
  void _seeInAi() {
    ref.read(wtmMirrorFlowProvider.notifier).setMode(WtmMirrorMode.aiCouture);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // No "before" photo to compare against in mannequin mode.
    final canCompare = widget.bodyImageUrl.isNotEmpty;
    final showingBefore = _showBefore && canCompare;

    return Column(
      children: [
        // The result: a full, uncropped composite in a premium frame; tap to
        // open it full-screen (Compare swaps to the Step-1 body photo).
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WtmSpace.screenH,
              WtmSpace.s12,
              WtmSpace.screenH,
              WtmSpace.s10,
            ),
            // One-shot reveal (scale + fade); instant under reduce-motion.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion ? Duration.zero : WtmMotion.base,
              curve: WtmMotion.easing,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
              ),
              child: Semantics(
                button: true,
                label: l10n.tryOn2dResultTitle,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: showingBefore ? null : _openFullscreen,
                    child: Container(
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: WtmColors.panel,
                        borderRadius: BorderRadius.circular(WtmRadius.card),
                        border: Border.all(color: WtmColors.line),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: showingBefore
                                ? CachedNetworkImage(
                                    imageUrl: widget.bodyImageUrl,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, _, _) =>
                                        const ColoredBox(color: WtmColors.bg2),
                                  )
                                : Image.memory(widget.bytes,
                                    fit: BoxFit.contain),
                          ),
                          if (canCompare)
                            Positioned(
                              top: WtmSpace.s10,
                              left: WtmSpace.s10,
                              child: _RevealTag(showingBefore
                                  ? l10n.tryOnBefore
                                  : l10n.tryOnAfter),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Actions.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            0,
            WtmSpace.screenH,
            WtmSpace.s14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // On-device / free info row — GoldPill + note (§0.4 styling).
              Row(
                children: [
                  wtm.GoldPill(label: l10n.tryOnBadgeFree),
                  const SizedBox(width: WtmSpace.s8),
                  Expanded(
                    child: Text(l10n.tryOn2dResultNote, style: WtmType.micro),
                  ),
                ],
              ),
              const SizedBox(height: WtmSpace.s12),
              // Quick actions — wrap so nothing overflows on 360dp.
              Wrap(
                spacing: WtmSpace.s8,
                runSpacing: WtmSpace.s8,
                children: [
                  _WtmResultAction(
                    icon: const wtm.WtmIcon(wtm.WtmGlyph.bookmark,
                        size: 15, color: WtmColors.gold),
                    label:
                        _savingLook ? l10n.tryOn2dSaving : l10n.tryOnSaveLook,
                    busy: _savingLook,
                    onTap: _saveLook,
                  ),
                  if (canCompare)
                    _WtmResultAction(
                      icon: const wtm.WtmIcon(wtm.WtmGlyph.swap,
                          size: 15, color: WtmColors.gold),
                      label: l10n.tryOnCompare,
                      active: _showBefore,
                      onTap: () => setState(() => _showBefore = !_showBefore),
                    ),
                  _WtmResultAction(
                    icon: const wtm.WtmIcon(wtm.WtmGlyph.users,
                        size: 15, color: WtmColors.gold),
                    label: l10n.tryOnPostCommunity,
                    onTap: () => context.push(
                      AppRoute.wtmCompose,
                      extra: WtmComposeArgs(imageBytes: widget.bytes),
                    ),
                  ),
                  _WtmResultAction(
                    icon: const Icon(Icons.ios_share_rounded,
                        size: 15, color: WtmColors.gold),
                    label: l10n.tryOnShare,
                    onTap: _share,
                  ),
                  _WtmResultAction(
                    icon: const wtm.WtmIcon(wtm.WtmGlyph.sliders,
                        size: 15, color: WtmColors.gold),
                    label: l10n.commonEdit,
                    onTap: widget.onEdit,
                  ),
                ],
              ),
              const SizedBox(height: WtmSpace.s12),
              // Premium next step — the metered AI render on the SAME look.
              wtm.GradientCta(
                label: l10n.tryOn2dUpgradeHd,
                icon: const wtm.WtmIcon(wtm.WtmGlyph.sparkle,
                    size: 15, color: WtmColors.ctaText),
                onPressed: _seeInAi,
              ),
              const SizedBox(height: WtmSpace.s8),
              wtm.GhostButton(
                label: l10n.tryOnTryAnother,
                icon: const wtm.WtmIcon(wtm.WtmGlyph.rotate,
                    size: 15, color: WtmColors.text),
                onPressed: widget.onAnother,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A WTM result action — a panel chip with a gold glyph + label, a busy spinner
/// (Save → "Saving…"), and an active (gold) state for the Compare toggle.
class _WtmResultAction extends StatelessWidget {
  const _WtmResultAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      selected: active,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s12,
              vertical: WtmSpace.s10,
            ),
            decoration: BoxDecoration(
              color: active ? WtmColors.chipOnBg : WtmColors.panel,
              borderRadius: BorderRadius.circular(WtmRadius.button),
              border: Border.all(
                  color: active ? WtmColors.chipOnBorder : WtmColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: busy
                      ? const CircularProgressIndicator(
                          strokeWidth: 2, color: WtmColors.gold)
                      : Center(child: icon),
                ),
                const SizedBox(width: WtmSpace.s6),
                Text(
                  label,
                  style: WtmType.chip.copyWith(
                      color: active ? WtmColors.gold : WtmColors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The before/after pill overlaid on the result while comparing.
class _RevealTag extends StatelessWidget {
  const _RevealTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC050308),
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: WtmColors.line),
      ),
      child: Text(
        label,
        style: WtmType.micro
            .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
