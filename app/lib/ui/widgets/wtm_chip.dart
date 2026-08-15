import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import '../../theme/wtm_typography.dart';

/// Filter/tag chip (board `.chip`) — muted hairline capsule; `on` turns the
/// text and border gold over a faint gold wash, and adds a soft halo so the
/// active filter is findable at a glance in a scrolling strip of eight.
class WtmChip extends StatefulWidget {
  const WtmChip({super.key, required this.label, this.on = false, this.onTap});

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  State<WtmChip> createState() => _WtmChipState();
}

class _WtmChipState extends State<WtmChip> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final chip = AnimatedContainer(
      duration: WtmMotion.fast,
      curve: WtmMotion.easing,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: on
            ? WtmColors.chipOnBg
            : (_pressed ? WtmGlass.fillPressed : WtmColors.chipBg),
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(
          color: on
              ? WtmColors.chipOnBorder
              : (_pressed ? WtmGlass.borderPressed : WtmColors.line),
        ),
        boxShadow: on ? WtmGlass.selectedGlow : null,
      ),
      child: Text(
        widget.label,
        maxLines: 1,
        style: on ? WtmType.chip.copyWith(color: WtmColors.gold) : WtmType.chip,
      ),
    );
    if (widget.onTap == null) return chip;
    return Semantics(
      button: true,
      selected: on,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
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

  /// Vertical room left OUTSIDE the strip for a selected chip's halo.
  static const _bleed = 24.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // Horizontally clipped, vertically open.
      //
      // `Clip.none` used to let scrolled-past chips paint over whatever sat to
      // the right of the strip. Full-width strips got away with it (the
      // overflow lands off-screen), but the closet puts the strip in an
      // `Expanded` beside a Filter button, so "Outerwear" scrolled straight
      // under the button and showed through its glass.
      //
      // A plain clip is the obvious fix and the wrong one: it would also cut
      // the selected chip's halo, which needs to bleed past the strip's box.
      // So the clip rect is the strip's width and the strip's height plus
      // [_bleed] — the axis that was overflowing is contained, the axis that
      // is supposed to overflow still can.
      clipper: const _ChipStripClipper(_bleed),
      child: SingleChildScrollView(
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
      ),
    );
  }
}

class _ChipStripClipper extends CustomClipper<Rect> {
  const _ChipStripClipper(this.bleed);

  final double bleed;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -bleed, size.width, size.height + bleed);

  @override
  bool shouldReclip(_ChipStripClipper oldClipper) => oldClipper.bleed != bleed;
}
