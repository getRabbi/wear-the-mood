import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A staged, time-estimated progress bar — the same honest pattern as the AI
/// try-on reveal (§4.3, §7). The underlying job reports no real percent, so the
/// bar eases toward ~90% over [estimateSeconds] and never completes on its own;
/// the caller removes the widget when the work is actually done (the "snap to
/// done"). It's driven purely by elapsed time — information, not decoration — so
/// it keeps advancing under reduce-motion (only the tween between values is
/// dropped).
class StagedProgressBar extends StatefulWidget {
  const StagedProgressBar({
    super.key,
    required this.label,
    this.estimateSeconds = 8,
    this.width,
    this.color,
    this.labelStyle,
  });

  /// Stage label shown above the bar (e.g. "Removing background…").
  final String label;

  /// Roughly how long the work takes — tunes how fast the bar eases up.
  final double estimateSeconds;

  /// Optional fixed bar width; when null the bar fills the parent's width.
  final double? width;

  /// Bar accent (defaults to the brand accent).
  final Color? color;
  final TextStyle? labelStyle;

  @override
  State<StagedProgressBar> createState() => _StagedProgressBarState();
}

class _StagedProgressBarState extends State<StagedProgressBar> {
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Eases toward ~0.9 and never reaches 1 — the caller's "done" completes it.
  double get _value {
    final eased = 1 - math.exp(-_elapsed / widget.estimateSeconds);
    return (0.92 * eased).clamp(0.0, 0.92);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final color = widget.color ?? AppColors.accent;

    Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _value),
        duration: reduceMotion ? Duration.zero : AppMotion.base,
        curve: AppMotion.easing,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: 5,
          backgroundColor: AppColors.mist,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
    if (widget.width != null) bar = SizedBox(width: widget.width, child: bar);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          textAlign: TextAlign.center,
          style: widget.labelStyle ??
              const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpace.sm),
        bar,
      ],
    );
  }
}
