import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';

/// Thin editorial slider (board `.track`/`.fill`/`.knob`).
///
/// Two board looks:
/// - **gold** (default): white@11% track, gold-gradient fill, champagne knob —
///   the editor's adjustment rows;
/// - **mood** (pass [trackGradient], [fill] false): full-spectrum gradient
///   track with a white glowing knob — Home's mood slider.
///
/// Reports live drags via [onChanged] and the release value via
/// [onChangeEnd] (persist there, not on every frame). Exposes semantic
/// increase/decrease actions.
class WtmSlider extends StatelessWidget {
  const WtmSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.fill = true,
    this.trackGradient,
    this.height = 3,
    this.semanticLabel,
  });

  /// 0–1.
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Draw the gold fill up to the knob. The mood variant hides it.
  final bool fill;
  final Gradient? trackGradient;
  final double height;
  final String? semanticLabel;

  static const _knobSize = 13.0; // .knob
  static const _hitHeight = 28.0; // drag comfort around the thin track

  @override
  Widget build(BuildContext context) {
    final mood = trackGradient != null;
    String percent(double v) => '${(v * 100).round()}%';
    final up = (value + 0.1).clamp(0.0, 1.0);
    final down = (value - 0.1).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: semanticLabel,
      value: percent(value),
      increasedValue: percent(up),
      decreasedValue: percent(down),
      onIncrease: () {
        onChanged(up);
        onChangeEnd?.call(up);
      },
      onDecrease: () {
        onChanged(down);
        onChangeEnd?.call(down);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double at(Offset local) => (local.dx / width).clamp(0.0, 1.0);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Track from the touch-down point so fast flicks (which can carry
            // their whole travel into the drag-start event) still land.
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (d) => onChanged(at(d.localPosition)),
            onTapUp: (d) => onChangeEnd?.call(at(d.localPosition)),
            onHorizontalDragStart: (d) => onChanged(at(d.localPosition)),
            onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition)),
            onHorizontalDragEnd: (_) => onChangeEnd?.call(value),
            child: SizedBox(
              height: _hitHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: mood ? null : const Color(0x1CFFFFFF), // .track
                      gradient: trackGradient,
                      borderRadius: BorderRadius.circular(WtmRadius.chip),
                    ),
                  ),
                  if (fill)
                    Container(
                      height: height,
                      width: width * value,
                      decoration: BoxDecoration(
                        gradient: WtmGradients.sliderFill,
                        borderRadius: BorderRadius.circular(WtmRadius.chip),
                      ),
                    ),
                  Positioned(
                    left: (width * value - _knobSize / 2)
                        .clamp(0.0, width - _knobSize),
                    child: Container(
                      width: _knobSize,
                      height: _knobSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mood
                            ? Colors.white
                            : const Color(0xFFF4EBDC), // .knob
                        border: Border.all(
                          color: mood ? Colors.white : WtmColors.gold,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            // .knob gold halo / .track.mood white-violet halo
                            color: mood
                                ? const Color(0xCCC88CFF)
                                : const Color(0x73D9BE95),
                            blurRadius: mood ? 12 : 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
