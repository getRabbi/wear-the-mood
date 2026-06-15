import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../social/compose_post_screen.dart';
import 'two_d_models.dart';
import 'two_d_tryon_service.dart';

/// Arguments for the 2D editor route (passed via `GoRouter` `extra`).
class TwoDEditorArgs {
  const TwoDEditorArgs({
    required this.bodyImageUrl,
    required this.garmentImageUrl,
    this.category,
  });

  final String bodyImageUrl;
  final String garmentImageUrl;
  final String? category;
}

/// The FREE 2D try-on flow: auto-places the garment over the body photo, lets the
/// user drag / pinch / rotate / flip / fade it, then composites a preview locally
/// (no AI endpoint, no credits). On done it shows the preview with save / share /
/// post actions.
class TwoDEditorScreen extends ConsumerStatefulWidget {
  const TwoDEditorScreen({super.key, required this.args});

  final TwoDEditorArgs args;

  @override
  ConsumerState<TwoDEditorScreen> createState() => _TwoDEditorScreenState();
}

enum _Phase { edit, result }

class _TwoDEditorScreenState extends ConsumerState<TwoDEditorScreen> {
  final _boundaryKey = GlobalKey();

  late final _bodyProvider = CachedNetworkImageProvider(widget.args.bodyImageUrl);
  late final _garmentProvider =
      CachedNetworkImageProvider(widget.args.garmentImageUrl);

  // Manual-adjustment transform (deltas on top of the auto placement).
  Offset _offset = Offset.zero;
  double _scale = 1;
  double _rotation = 0;
  double _opacity = 1;
  bool _flipH = false;

  // Gesture anchors.
  Offset _startOffset = Offset.zero;
  double _startScale = 1;
  double _startRotation = 0;
  Offset _startFocal = Offset.zero;

  bool _precached = false;
  bool _ready = false;
  bool _busy = false;
  _Phase _phase = _Phase.edit;
  Uint8List? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    Future.wait([
      precacheImage(_bodyProvider, context),
      precacheImage(_garmentProvider, context),
    ]).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startOffset = _offset;
    _startScale = _scale;
    _startRotation = _rotation;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_startScale * d.scale).clamp(0.2, 5.0);
      _rotation = _startRotation + d.rotation;
      _offset = _startOffset + (d.focalPoint - _startFocal);
    });
  }

  void _reset() => setState(() {
    _offset = Offset.zero;
    _scale = 1;
    _rotation = 0;
    _opacity = 1;
    _flipH = false;
  });

  Future<void> _done() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    // Let the final frame paint before capturing.
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
    // Save the result with mode '2d' (separate from AI history).
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
      ),
      body: SafeArea(
        child: !_ready
            ? const Center(child: CircularProgressIndicator())
            : isResult
                ? _ResultView(
                    bytes: _result!,
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: ColoredBox(
                        color: AppColors.paperAlt,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(image: _bodyProvider, fit: BoxFit.contain),
                            LayoutBuilder(
                              builder: (context, c) {
                                final place =
                                    garmentPlacement(widget.args.category);
                                final baseW = c.maxWidth * place.widthFactor;
                                final autoDy =
                                    (place.verticalCenter - 0.5) * c.maxHeight;
                                return Center(
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..translateByDouble(
                                        _offset.dx,
                                        autoDy + _offset.dy,
                                        0,
                                        1,
                                      )
                                      ..rotateZ(_rotation)
                                      ..scaleByDouble(
                                        _flipH ? -_scale : _scale,
                                        _scale,
                                        1,
                                        1,
                                      ),
                                    child: Opacity(
                                      opacity: _opacity,
                                      child: Image(
                                        image: _garmentProvider,
                                        width: baseW,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Controls(
              opacity: _opacity,
              onOpacity: (v) => setState(() => _opacity = v),
              onFlip: () => setState(() => _flipH = !_flipH),
              onReset: _reset,
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.opacity,
    required this.onOpacity,
    required this.onFlip,
    required this.onReset,
    required this.onDone,
  });

  final double opacity;
  final ValueChanged<double> onOpacity;
  final VoidCallback onFlip;
  final VoidCallback onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.tryOn2dHint, style: text.bodySmall),
              Row(
                children: [
                  const Icon(Icons.opacity_rounded,
                      size: 18, color: AppColors.lavender),
                  Expanded(
                    child: Slider(
                      value: opacity,
                      min: 0.3,
                      max: 1,
                      onChanged: onOpacity,
                    ),
                  ),
                  _ControlButton(
                    icon: Icons.flip_rounded,
                    label: l10n.tryOn2dFlip,
                    onTap: onFlip,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  _ControlButton(
                    icon: Icons.restart_alt_rounded,
                    label: l10n.tryOn2dReset,
                    onTap: onReset,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              PrimaryButton(
                label: l10n.tryOn2dDone,
                icon: Icons.check_rounded,
                onPressed: onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.lavender),
        style: IconButton.styleFrom(backgroundColor: AppColors.glassFill),
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({
    required this.bytes,
    required this.onAnother,
    required this.onEdit,
  });

  final Uint8List bytes;
  final VoidCallback onAnother;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    void snack(String m) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
                  Text(l10n.tryOn2dResultNote, style: text.bodySmall),
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
                    icon: Icons.add_a_photo_outlined,
                    label: l10n.tryOnPostCommunity,
                    onTap: () => context.push(
                      AppRoute.socialCompose,
                      extra: ComposeArgs(presetPhoto: bytes),
                    ),
                  ),
                  _Action(
                    icon: Icons.ios_share_rounded,
                    label: l10n.tryOnShare,
                    onTap: () => snack(l10n.tryOnShareComingSoon),
                  ),
                  _Action(
                    icon: Icons.tune_rounded,
                    label: l10n.commonEdit,
                    onTap: onEdit,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              PrimaryButton(
                label: l10n.tryOnTryAnother,
                icon: Icons.refresh_rounded,
                onPressed: onAnother,
              ),
            ],
          ),
        ),
      ],
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
