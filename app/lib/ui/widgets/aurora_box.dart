import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import 'grain_overlay.dart';

/// Aurora colorway. [noir] is THE §1.1 recipe; [blush] is the board's
/// pink-led alternate used to vary editorial tile rows (Home inspiration,
/// story grids).
enum AuroraVariant { noir, blush }

/// Editorial "aurora" imagery placeholder (UI_IMPLEMENTATION.md §1.1, board
/// `.ed`) — three stacked radial glows (violet top-right, pink bottom-left,
/// plum center) over a `162°` noir base, finished with the film-grain overlay.
///
/// Layer order matches the board: base → glows → [child] → [vignette] → grain.
/// Size it from the parent, or pass [width]/[height] directly.
class AuroraBox extends StatelessWidget {
  const AuroraBox({
    super.key,
    this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.vignette = false,
    this.grain = true,
    this.border = true,
    this.variant = AuroraVariant.noir,
  });

  /// Content layered above the glows (e.g. a figure illustration), below the
  /// vignette + grain finish.
  final Widget? child;
  final double? width;
  final double? height;

  /// Defaults to the tile radius (12).
  final BorderRadius? borderRadius;

  /// Darkened edge falloff (board `.vig`) for text/figure legibility.
  final bool vignette;
  final bool grain;

  /// Hairline tile border (white @ 7%).
  final bool border;
  final AuroraVariant variant;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(WtmRadius.tile);
    final noir = variant == AuroraVariant.noir;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border ? Border.all(color: WtmColors.tileBorder) : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: noir
                    ? WtmGradients.auroraBase
                    : WtmGradients.auroraBaseBlush,
              ),
            ),
            if (noir) ...const [
              DecoratedBox(
                decoration:
                    BoxDecoration(gradient: WtmGradients.auroraVioletGlow),
              ),
              DecoratedBox(
                decoration:
                    BoxDecoration(gradient: WtmGradients.auroraPinkGlow),
              ),
              DecoratedBox(
                decoration:
                    BoxDecoration(gradient: WtmGradients.auroraPlumGlow),
              ),
            ] else ...const [
              DecoratedBox(
                decoration:
                    BoxDecoration(gradient: WtmGradients.auroraBlushPinkGlow),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                    gradient: WtmGradients.auroraBlushVioletGlow),
              ),
            ],
            ?child,
            if (vignette)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: WtmGradients.vignetteRadial),
              ),
            if (grain) const GrainOverlay(),
          ],
        ),
      ),
    );
  }
}
