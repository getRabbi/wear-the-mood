import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Counts up from 0 to [value] when it first appears (and re-animates from the
/// current number whenever [value] changes) — used for profile stats (§4 motion).
/// Respects reduce-motion: renders the final number immediately. Pure formatting
/// of an int; pass an already-resolved value.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final int value;
  final TextStyle? style;
  final Duration duration;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  Widget _text(String s) => Text(
        s,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );

  @override
  Widget build(BuildContext context) {
    // Nothing to count to 0; and honour reduce-motion by showing the final value.
    if (value == 0 || MediaQuery.of(context).disableAnimations) {
      return _text('$value');
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.easing,
      builder: (context, v, _) => _text('${v.round()}'),
    );
  }
}
