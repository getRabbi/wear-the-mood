import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Lightweight pulsing placeholder for loading states — no extra dependency.
/// Use several stacked/sized instances to skeleton a screen while it loads.
/// One of the four required screen states (CLAUDE.md §4.3).
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 0.75,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor,
          borderRadius:
              widget.borderRadius ?? BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}
