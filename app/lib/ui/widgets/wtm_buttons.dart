import 'package:flutter/material.dart';

import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';

// Board-extracted button metrics (CSS provenance in comments). Component-
// intrinsic — the shared scale lives in WtmSpace/WtmRadius.
const _ctaPadding = 13.0; // .cta padding
const _ghostPadding = 12.0; // .ghost padding
const _iconGap = 8.0; // .cta/.ghost gap
const _minTapHeight = 48.0; // CLAUDE.md §4.3 tap target floor

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
    final button = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: _minTapHeight),
      decoration: BoxDecoration(
        gradient: WtmGradients.cta,
        borderRadius: BorderRadius.circular(WtmRadius.button),
        boxShadow: enabled ? WtmShadows.cta : null,
      ),
      // `inset 0 1px 0 rgba(255,255,255,.35)` — a hairline light along the
      // inner top edge, done as a fast top-down fade.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WtmRadius.button),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WtmColors.ctaInnerHighlight, Color(0x00FFFFFF)],
          stops: [0.0, 0.05],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _ctaPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
    return _tappable(
      label: label,
      onTap: onPressed,
      child: enabled ? button : Opacity(opacity: 0.45, child: button),
    );
  }
}

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
    final button = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: _minTapHeight),
      decoration: BoxDecoration(
        color: WtmColors.ghostBg,
        borderRadius: BorderRadius.circular(WtmRadius.button),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _ghostPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
    return _tappable(
      label: label,
      onTap: onPressed,
      child: enabled ? button : Opacity(opacity: 0.45, child: button),
    );
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
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: WtmColors.pillBg,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: WtmSpace.s6)],
          Text(label.toUpperCase(), style: WtmType.pill),
        ],
      ),
    );
    if (onTap == null) return pill;
    return _tappable(label: label, onTap: onTap, child: pill);
  }
}

/// Shared tap plumbing: semantics + press-scale (reduced-motion aware via
/// [PressableScale]) + gesture.
Widget _tappable({
  required String label,
  required VoidCallback? onTap,
  required Widget child,
}) {
  return Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: ExcludeSemantics(
      child: PressableScale(
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    ),
  );
}
