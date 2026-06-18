import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A press-scale wrapper for controls that already own their tap gesture — e.g.
/// an [InkWell]-based button that wants a ripple AND a subtle scale-down on press
/// (CLAUDE.md §4 — tactile, never bouncy).
///
/// Unlike [Pressable] (which provides its own tap [GestureDetector] for cards),
/// this uses a non-competing [Listener]: it observes pointer down/up to drive the
/// scale but never enters the gesture arena, so the child's own InkWell/onTap
/// still fires. Respects the OS reduce-motion setting (renders the child as-is).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.scale = 0.96,
    this.enabled = true,
  });

  final Widget child;

  /// Scale at full press (1.0 = no scale).
  final double scale;

  /// When false (e.g. a disabled button) the scale is suppressed.
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!widget.enabled || reduceMotion) return widget.child;

    return Listener(
      // deferToChild → only react to pointers the child actually handles, and
      // never claim the gesture (the child's InkWell/onTap keeps working).
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.easing,
        child: widget.child,
      ),
    );
  }
}
