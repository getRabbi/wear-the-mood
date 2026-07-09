import 'package:flutter/material.dart';

import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import 'wtm_icons.dart';

/// Square hairline icon button (board `.iconbtn`) — 34px, radius 11, muted
/// 15px glyph. Used in app headers (bell, search) and nav-head back slots.
/// The visual is board-exact; the hit target is padded out to ≥44px.
class WtmIconButton extends StatelessWidget {
  const WtmIconButton(
    this.glyph, {
    super.key,
    this.onTap,
    this.semanticLabel,
    this.color = WtmColors.muted,
  });

  final WtmGlyph glyph;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color color;

  static const _size = 34.0; // .iconbtn
  static const _hitPad = 5.0; // → 44px effective target

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: WtmColors.iconBtnBg,
        borderRadius: BorderRadius.circular(11), // .iconbtn radius
        border: Border.all(color: WtmColors.line),
      ),
      alignment: Alignment.center,
      child: WtmIcon(glyph, size: 15, color: color), // .ic-s
    );
    if (onTap == null) return button;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(_hitPad),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}
