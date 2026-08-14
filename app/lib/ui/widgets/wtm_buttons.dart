import 'package:flutter/material.dart';

import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import '../../theme/wtm_typography.dart';

// Board-extracted button metrics (CSS provenance in comments). Component-
// intrinsic — the shared scale lives in WtmSpace/WtmRadius.
const _ctaPadding = 13.0; // .cta padding
const _ghostPadding = 12.0; // .ghost padding
const _iconGap = 8.0; // .cta/.ghost gap
const _minTapHeight = 48.0; // CLAUDE.md §4.3 tap target floor

/// Builds a button that spans its slot where there IS a slot to span, and takes
/// its natural size where there is not.
///
/// Both buttons are designed to fill the column they sit in, which is what
/// `width: double.infinity` says. But a [Row] hands its non-flex children an
/// UNBOUNDED width, and resolving infinity against unbounded is a hard layout
/// assertion — `BoxConstraints forces an infinite width`. Once it throws, the
/// subtree never lays out and every subsequent frame throws again.
///
/// That is what froze Discover: the filter sheet's `Reset` sits after a
/// `Spacer()` in a Row, so opening Filter put the app into a per-frame
/// exception loop and nothing responded. The same trap was one Row away in the
/// feed's "load more failed" retry, and in any of the ~120 other call sites
/// that might one day put a button beside something.
Widget _spanning(Widget Function(double? width) build) => LayoutBuilder(
  builder: (context, constraints) =>
      build(constraints.hasBoundedWidth ? double.infinity : null),
);

/// Primary gradient CTA (board `.cta`) — violet→orchid→pinkish at 95°, deep
/// violet glow, hairline inner top highlight, Outfit 600 label on [WtmColors
/// .ctaText]. One per screen. Disabled = `onPressed: null`.
class GradientCta extends StatelessWidget {
  const GradientCta({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Leading 15px glyph (board `.ic-s`); tint it [WtmColors.ctaText].
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _spanning((width) {
      Widget button(bool pressed) => Container(
        width: width,
        constraints: const BoxConstraints(minHeight: _minTapHeight),
        decoration: BoxDecoration(
          gradient: WtmGradients.cta,
          borderRadius: BorderRadius.circular(WtmRadius.button),
          boxShadow: enabled ? WtmShadows.cta : null,
        ),
        // `inset 0 1px 0 rgba(255,255,255,.35)` — a hairline light along the
        // inner top edge, done as a fast top-down fade. Under the finger the
        // same layer carries a dark wash, so the gradient darkens on press
        // instead of only shrinking (a scale you cannot see past your thumb).
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pressed
                ? const [
                    WtmColors.ctaInnerHighlight,
                    _ctaPressScrim,
                    _ctaPressScrim,
                  ]
                : const [WtmColors.ctaInnerHighlight, Color(0x00FFFFFF)],
            stops: pressed ? const [0.0, 0.05, 1.0] : const [0.0, 0.05],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: _ctaPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: _iconGap)],
            Flexible(
              child: Text(
                label,
                style: WtmType.ctaLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
      return _PressRegion(
        label: label,
        onTap: onPressed,
        builder: (pressed) => enabled
            ? button(pressed)
            : Opacity(opacity: _disabledOpacity, child: button(false)),
      );
    });
  }
}

/// Pressed wash over the gradient CTA — black @ 14%.
const _ctaPressScrim = Color(0x24000000);

/// Secondary "ghost" button (board `.ghost`) — hairline border, near-invisible
/// fill, Outfit 400 label. [foregroundColor]/[borderColor] cover the board's
/// gold variant (e.g. the editor's Done).
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.foregroundColor = WtmColors.text,
    this.borderColor = WtmColors.line,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Leading 15px glyph (board `.ic-s`); tint it [foregroundColor].
  final Widget? icon;
  final Color foregroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return _spanning((width) {
      Widget button(bool pressed) => Container(
        width: width,
        constraints: const BoxConstraints(minHeight: _minTapHeight),
        decoration: BoxDecoration(
          color: pressed ? WtmGlass.fillPressed : WtmColors.ghostBg,
          borderRadius: BorderRadius.circular(WtmRadius.button),
          border: Border.all(
            // A pressed ghost brightens its own rim unless the caller has
            // chosen a rim colour (the gold "Done" variant), which stays gold.
            color: pressed && borderColor == WtmColors.line
                ? WtmGlass.borderPressed
                : borderColor,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: _ghostPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: _iconGap)],
            Flexible(
              child: Text(
                label,
                style: WtmType.ghostLabel.copyWith(color: foregroundColor),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
      return _PressRegion(
        label: label,
        onTap: onPressed,
        builder: (pressed) => enabled
            ? button(pressed)
            : Opacity(opacity: _disabledOpacity, child: button(false)),
      );
    });
  }
}

/// Gold outline pill (board `.pill`) — UPPERCASE Outfit 500 micro-label in
/// gold, used for inline actions ("Enter Now", "Shop Now", "Update"). Renders
/// at its natural compact size; give interactive placements breathing room
/// (the visual is smaller than the 48dp tap floor).
class GoldPill extends StatelessWidget {
  const GoldPill({super.key, required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;

  /// Leading 12–15px glyph, tinted gold.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    Widget pill(bool pressed) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: pressed ? WtmGlass.selectedFill : WtmColors.pillBg,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(
          color: pressed ? WtmColors.gold : WtmColors.pillBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: WtmSpace.s6)],
          Text(label.toUpperCase(), style: WtmType.pill),
        ],
      ),
    );
    if (onTap == null) return pill(false);
    return _PressRegion(label: label, onTap: onTap, builder: pill);
  }
}

/// Shared tap plumbing: semantics + press-scale (reduced-motion aware via
/// [PressableScale]) + gesture, with the press state handed back to [builder].
///
/// Scale alone was the only press feedback these buttons had, and a 4%
/// shrink is easy to miss under the thumb that is covering it — hence the
/// surface change too. Reduce-motion users lose the scale and keep the colour
/// shift, which is the more important half.
class _PressRegion extends StatefulWidget {
  const _PressRegion({
    required this.label,
    required this.onTap,
    required this.builder,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;

  @override
  State<_PressRegion> createState() => _PressRegionState();
}

class _PressRegionState extends State<_PressRegion> {
  bool _pressed = false;

  void _set(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: PressableScale(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: enabled ? (_) => _set(true) : null,
            onTapUp: enabled ? (_) => _set(false) : null,
            onTapCancel: enabled ? () => _set(false) : null,
            child: widget.builder(enabled && _pressed),
          ),
        ),
      ),
    );
  }
}

/// Disabled dim. The board had no disabled state; 0.45 was a first guess and
/// on a `#08060F` page it took a `GhostButton` below the "can you tell what
/// this says" line. 0.6 still reads unmistakably as off.
const _disabledOpacity = 0.6;
