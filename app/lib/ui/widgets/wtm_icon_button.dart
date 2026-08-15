import 'package:flutter/material.dart';

import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import 'wtm_icons.dart';

/// Where a [WtmIconButton] is sitting — which decides how much contrast it has
/// to carry on its own.
enum WtmIconButtonSurface {
  /// On the noir page or a card. Borrows contrast from a known background.
  page,

  /// On top of a photo. The background could be anything from black to a
  /// blown-out white, so the control brings its own puck and rim.
  image,
}

/// Square hairline icon button (board `.iconbtn`) — 34px, radius 11, 15px
/// glyph. Used in app headers (bell, search), nav-head back slots, and over
/// imagery.
///
/// The metrics are board-exact and unchanged; the hit target is padded out to
/// ≥44px. What this owns is the four faces of the control — resting, pressed,
/// selected, disabled — because a glyph at 56% opacity on a fill at 2% was
/// legible on the design board's bright mock and close to invisible on a phone.
class WtmIconButton extends StatefulWidget {
  const WtmIconButton(
    this.glyph, {
    super.key,
    this.onTap,
    this.semanticLabel,
    this.color,
    this.selected = false,
    this.surface = WtmIconButtonSurface.page,
  });

  final WtmGlyph glyph;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Overrides the glyph tint (e.g. destructive actions). Leave null to take
  /// the tint that matches the current state.
  final Color? color;

  /// On/active — gold glyph over a gold wash, with a soft halo.
  final bool selected;

  final WtmIconButtonSurface surface;

  static const _size = 34.0; // .iconbtn
  static const _hitPad = 5.0; // → 44px effective target

  @override
  State<WtmIconButton> createState() => _WtmIconButtonState();
}

class _WtmIconButtonState extends State<WtmIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final onImage = widget.surface == WtmIconButtonSurface.image;

    final Color fill;
    final Color border;
    final Color foreground;
    List<BoxShadow>? shadow;

    if (!enabled) {
      fill = WtmGlass.fillDisabled;
      border = WtmGlass.borderDisabled;
      foreground = WtmGlass.foregroundDisabled;
    } else if (widget.selected) {
      fill = WtmGlass.selectedFill;
      border = WtmGlass.selectedBorder;
      foreground = WtmGlass.selectedForeground;
      shadow = WtmGlass.selectedGlow;
    } else if (onImage) {
      fill = _pressed ? WtmGlass.overlayFillPressed : WtmGlass.overlayFill;
      border = _pressed
          ? WtmGlass.overlayBorderPressed
          : WtmGlass.overlayBorder;
      foreground = WtmGlass.overlayForeground;
      shadow = WtmGlass.overlayShadow;
    } else {
      fill = _pressed ? WtmGlass.fillPressed : WtmGlass.fill;
      border = _pressed ? WtmGlass.borderPressed : WtmGlass.border;
      foreground = WtmGlass.foreground;
    }

    final button = AnimatedContainer(
      duration: WtmMotion.fast,
      curve: WtmMotion.easing,
      width: WtmIconButton._size,
      height: WtmIconButton._size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(11), // .iconbtn radius
        border: Border.all(color: border),
        boxShadow: shadow,
      ),
      alignment: Alignment.center,
      child: WtmIcon(
        widget.glyph,
        size: 15, // .ic-s
        color: widget.color ?? foreground,
      ),
    );

    if (!enabled) {
      return Padding(
        padding: const EdgeInsets.all(WtmIconButton._hitPad),
        child: button,
      );
    }

    return Semantics(
      button: true,
      enabled: true,
      selected: widget.selected ? true : null,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: Padding(
              padding: const EdgeInsets.all(WtmIconButton._hitPad),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}
