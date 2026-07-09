import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';

/// Filter/tag chip (board `.chip`) — muted hairline capsule; `on` turns the
/// text and border gold over a faint gold wash.
class WtmChip extends StatelessWidget {
  const WtmChip({super.key, required this.label, this.on = false, this.onTap});

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: WtmMotion.fast,
      curve: WtmMotion.easing,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: on ? WtmColors.chipOnBg : WtmColors.chipBg,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: on ? WtmColors.chipOnBorder : WtmColors.line),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: on
            ? WtmType.chip.copyWith(color: WtmColors.gold)
            : WtmType.chip,
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: chip,
        ),
      ),
    );
  }
}

/// Horizontal chip strip (board `.chiprow`) — edge-bleed scroll, 7px gaps, no
/// scrollbar. Give it the screen's horizontal padding via [padding] so chips
/// scroll under the screen edge.
class WtmChipRow extends StatelessWidget {
  const WtmChipRow({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  static const _gap = 7.0; // .chiprow gap

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: padding ?? const EdgeInsets.all(2), // glow/border headroom
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            children[i],
          ],
        ],
      ),
    );
  }
}
