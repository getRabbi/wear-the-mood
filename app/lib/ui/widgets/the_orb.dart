import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';

/// The Orb — the app's signature object (board `.orb`; nav center "+", splash
/// mark, assistant avatar). A lit sphere with an outer halo ring and a violet
/// glow that "breathes" on a 4.5s ease-in-out loop.
///
/// Breathing animates the GLOW only (board keyframes scale the box-shadow,
/// never the size) and is disabled under OS reduce-motion
/// (`MediaQuery.disableAnimations`), where the orb renders at its resting
/// state. All metrics scale from the board's 47px reference ([TheOrb.navSize];
/// mini is 34).
class TheOrb extends StatefulWidget {
  const TheOrb({
    super.key,
    this.size = navSize,
    this.breathing = true,
    this.ring = true,
  });

  /// Board reference sizes.
  static const navSize = 47.0;
  static const miniSize = 34.0;

  final double size;
  final bool breathing;

  /// The detached halo ring 5px outside the sphere (board `.orb::before`).
  /// Note it OVERFLOWS the widget's layout bounds by 5px+1px stroke, exactly
  /// like the CSS.
  final bool ring;

  @override
  State<TheOrb> createState() => _TheOrbState();
}

class _TheOrbState extends State<TheOrb> with SingleTickerProviderStateMixin {
  // repeat(reverse) plays half the CSS cycle per pass: 0% → 50% keyframe and
  // back, so the controller runs at half the 4.5s loop.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WtmMotion.breathe ~/ 2,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final animate = widget.breathing && !reduceMotion;
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }

    final f = widget.size / TheOrb.navSize; // scale from the 47px reference
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, sphere) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Board glows: `0 0 26px rgba(160,110,255,.6)` and
            // `0 0 70px -14px rgba(190,130,255,.6)`, breathing to 34px/.75 and
            // 84px -12px/.75 at the 50% keyframe.
            boxShadow: [
              BoxShadow(
                color: Color.lerp(
                  WtmColors.orbGlowInner,
                  WtmColors.orbGlowInnerPeak,
                  t,
                )!,
                blurRadius: ui.lerpDouble(26, 34, t)! * f,
              ),
              BoxShadow(
                color: Color.lerp(
                  WtmColors.orbGlowOuter,
                  WtmColors.orbGlowOuterPeak,
                  t,
                )!,
                blurRadius: ui.lerpDouble(70, 84, t)! * f,
                spreadRadius: ui.lerpDouble(-14, -12, t)! * f,
              ),
            ],
          ),
          child: sphere,
        );
      },
      child: _sphere(f),
    );
  }

  Widget _sphere(double f) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Halo ring — fixed 5px outside at every size, like the CSS.
          if (widget.ring)
            const Positioned(
              left: -5,
              top: -5,
              right: -5,
              bottom: -5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: WtmColors.orbRing),
                  ),
                ),
              ),
            ),
          // Sphere body.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: WtmGradients.orbCore,
              ),
            ),
          ),
          // Inner shadows the CSS does with inset box-shadows: a dark bottom
          // well (`inset 0 -6px 14px`) and a light top rim (`inset 0 3px 7px`).
          Positioned.fill(
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: const [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [WtmColors.orbInsetShadow, Color(0x00140832)],
                        stops: [0.0, 0.42],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [WtmColors.orbSheen, Color(0x00FFFFFF)],
                        stops: [0.0, 0.22],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Specular highlight — 9×5 blurred blob at (11, 9), rotated −22°.
          Positioned(
            left: 11 * f,
            top: 9 * f,
            child: Transform.rotate(
              angle: -22 * math.pi / 180,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 1.6 * f,
                  sigmaY: 1.6 * f,
                ),
                child: Container(
                  width: 9 * f,
                  height: 5 * f,
                  decoration: BoxDecoration(
                    color: WtmColors.orbHighlight,
                    borderRadius: BorderRadius.circular(WtmRadius.chip),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
