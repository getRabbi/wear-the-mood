import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Premium loading system (feat/premium-ui-polish) — a cohesive, on-brand family
/// of loaders so no async flow falls back to a bare spinner. Everything is drawn
/// in code (no image asset), tuned to the "Midnight Plum + Neon Rose" fashion-
/// tech look, and honours reduce-motion (`MediaQuery.disableAnimations`): under
/// reduce-motion the mark renders static instead of animating.
///
/// - [PremiumLogoLoader]  — pulsing gradient brand orb + optional label.
/// - [PremiumAILoader]    — brand orb with a rotating AI "scan" aura + label.
/// - [PremiumProgressOverlay] — full-bleed scrim + loader + message (blocking).
/// - [PremiumInlineLoader] — small gradient arc for buttons / tiny inline waits.

/// The animated brand mark: a soft outer glow, a rotating sweep-gradient ring
/// (only when [scan] — the AI aura) and a gradient centre orb. Shared internals
/// for [PremiumLogoLoader] and [PremiumAILoader].
class _BrandMark extends StatefulWidget {
  const _BrandMark({required this.size, required this.scan});

  final double size;

  /// When true, adds the rotating AI "scan" ring (for AI/image processing).
  final bool scan;

  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  bool _animating = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start/stop the loop based on reduce-motion (read here so it reacts to a
    // live setting change and is safe to check with a valid context).
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_animating) {
        _c.stop();
        _animating = false;
      }
    } else if (!_animating) {
      _c.repeat();
      _animating = true;
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value; // 0..1
          // Gentle breathing pulse (still under reduce-motion).
          final pulse = reduceMotion ? 1.0 : 1.0 + 0.06 * math.sin(t * 2 * math.pi);
          return CustomPaint(
            painter: _BrandMarkPainter(
              turns: reduceMotion ? 0 : t,
              pulse: pulse,
              scan: widget.scan,
            ),
          );
        },
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({
    required this.turns,
    required this.pulse,
    required this.scan,
  });

  final double turns;
  final double pulse;
  final bool scan;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final stroke = r * 0.12;

    // Soft outer glow (breathing).
    final glow = Paint()
      ..color = AppColors.violet.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(center, (r * 0.78) * pulse, glow);

    // Faint full track ring.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.glassBorder;
    canvas.drawCircle(center, r - stroke, track);

    // Sweep-gradient arc — the moving highlight (the "scan" aura when [scan]).
    final rect = Rect.fromCircle(center: center, radius: r - stroke);
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(turns * 2 * math.pi),
        colors: const [
          Color(0x00F43F7F),
          AppColors.violet,
          AppColors.accent,
          AppColors.neon,
          Color(0x00F43F7F),
        ],
        stops: const [0.0, 0.35, 0.6, 0.8, 1.0],
      ).createShader(rect);
    // A longer arc for the AI scan, a shorter comet for the plain logo.
    final sweepAngle = scan ? math.pi * 1.6 : math.pi * 1.1;
    canvas.drawArc(rect, -math.pi / 2 + turns * 2 * math.pi, sweepAngle, false,
        sweep);

    // Centre orb — gradient fill with a soft inner glow.
    final orbR = r * 0.34 * pulse;
    final orb = Paint()
      ..shader = const RadialGradient(
        colors: [AppColors.accent, AppColors.violet],
      ).createShader(Rect.fromCircle(center: center, radius: orbR));
    canvas.drawCircle(center, orbR, orb);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) =>
      old.turns != turns || old.pulse != pulse || old.scan != scan;
}

/// The label under a loader — muted, centered, small-caps-ish weight.
class _LoaderLabel extends StatelessWidget {
  const _LoaderLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.graphite,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
      );
}

/// A pulsing gradient brand orb + optional [label]. The default "premium
/// loading" for pages/sections (replaces a bare centered spinner).
class PremiumLogoLoader extends StatelessWidget {
  const PremiumLogoLoader({super.key, this.size = 64, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandMark(size: size, scan: false),
          if (label != null) ...[
            const SizedBox(height: AppSpace.md),
            _LoaderLabel(label!),
          ],
        ],
      ),
    );
  }
}

/// The brand orb wrapped in a rotating AI "scan" aura + optional [label] — for
/// AI / image-processing waits (background remove, enhance, try-on, catalog).
class PremiumAILoader extends StatelessWidget {
  const PremiumAILoader({super.key, this.size = 76, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandMark(size: size, scan: true),
          if (label != null) ...[
            const SizedBox(height: AppSpace.md),
            _LoaderLabel(label!),
          ],
        ],
      ),
    );
  }
}

/// A full-bleed premium blocking overlay: a soft scrim + an AI/brand loader + a
/// message. Drop into a `Positioned.fill` (over a Stack) or use as a page body.
class PremiumProgressOverlay extends StatelessWidget {
  const PremiumProgressOverlay({
    super.key,
    required this.message,
    this.subMessage,
    this.ai = true,
  });

  final String message;
  final String? subMessage;

  /// AI aura (true) vs the plain brand pulse (false).
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.scrim),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ai)
                const PremiumAILoader(size: 84)
              else
                const PremiumLogoLoader(size: 72),
              const SizedBox(height: AppSpace.lg),
              Text(message, textAlign: TextAlign.center, style: text.titleMedium),
              if (subMessage != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  subMessage!,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.graphite),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small rotating gradient arc — the premium replacement for a tiny inline
/// `CircularProgressIndicator` (buttons, list-tail loaders). Reduce-motion safe.
class PremiumInlineLoader extends StatefulWidget {
  const PremiumInlineLoader({super.key, this.size = 20, this.strokeWidth = 2.4});

  final double size;
  final double strokeWidth;

  @override
  State<PremiumInlineLoader> createState() => _PremiumInlineLoaderState();
}

class _PremiumInlineLoaderState extends State<PremiumInlineLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  bool _animating = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_animating) {
        _c.stop();
        _animating = false;
      }
    } else if (!_animating) {
      _c.repeat();
      _animating = true;
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _InlinePainter(
            turns: reduceMotion ? 0 : _c.value,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _InlinePainter extends CustomPainter {
  _InlinePainter({required this.turns, required this.strokeWidth});

  final double turns;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0x008B35FF), AppColors.violet, AppColors.accent],
      ).createShader(rect);
    canvas.drawArc(rect, turns * 2 * math.pi, math.pi * 1.5, false, p);
  }

  @override
  bool shouldRepaint(_InlinePainter old) => old.turns != turns;
}
