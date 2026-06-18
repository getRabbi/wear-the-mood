import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Wraps a list/grid item so it fades + rises in when first built, with a small
/// per-[index] delay for a staggered cascade (CLAUDE.md §4 — subtle, only on
/// appear). Animates transform/opacity only and is cheap; respects reduce-motion
/// (renders the child immediately).
///
/// Delay is capped at [maxStaggerIndex] so items far down a long list don't wait
/// (and feel instant when scrolled into view).
class StaggeredItem extends StatefulWidget {
  const StaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.perItemDelay = const Duration(milliseconds: 45),
    this.maxStaggerIndex = 8,
    this.rise = 12,
  });

  final int index;
  final Widget child;
  final Duration perItemDelay;
  final int maxStaggerIndex;

  /// Pixels the child rises from as it fades in.
  final double rise;

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  // Created eagerly in initState (not lazily) so dispose never has to construct a
  // ticker while the element is deactivated — even when reduce-motion skips the
  // animation entirely.
  late final AnimationController _controller;
  late final Animation<double> _anim;
  Timer? _start;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _anim = CurvedAnimation(parent: _controller, curve: AppMotion.easing);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decide once, here, where MediaQuery is available — so reduce-motion never
    // even schedules a timer (which would otherwise dangle).
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.of(context).disableAnimations) return;
    final steps = widget.index.clamp(0, widget.maxStaggerIndex);
    _start = Timer(widget.perItemDelay * steps, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _anim.value,
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - _anim.value)),
          child: child,
        ),
      ),
    );
  }
}
