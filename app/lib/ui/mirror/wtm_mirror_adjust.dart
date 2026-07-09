import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Local, non-destructive adjustments for a rendered look (board 06, P4).
/// All values 0–1 with 0.5 = neutral.
class WtmAdjustments {
  const WtmAdjustments({
    this.brightness = 0.5,
    this.contrast = 0.5,
    this.saturation = 0.5,
    this.shadows = 0.5,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double shadows;

  bool get isNeutral =>
      brightness == 0.5 &&
      contrast == 0.5 &&
      saturation == 0.5 &&
      shadows == 0.5;

  WtmAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? shadows,
  }) =>
      WtmAdjustments(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        shadows: shadows ?? this.shadows,
      );

  /// 5×4 color matrix composing brightness (offset), contrast (scale around
  /// mid-gray), saturation (luma-weighted), and a shadow lift (offset + gentle
  /// contrast ease — a matrix approximation of a curves lift).
  ColorFilter toColorFilter() {
    final b = (brightness - 0.5) * 2; // −1..1
    final c = (contrast - 0.5) * 2;
    final s = (saturation - 0.5) * 2;
    final sh = (shadows - 0.5) * 2;

    final scale = 1 + c * 0.6 - sh * 0.12;
    final offset = 255 * (0.5 * (1 - scale)) + 255 * 0.22 * b + 255 * 0.14 * sh;
    final sat = 1 + s * 0.8;

    // Luma weights (Rec. 601).
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final ir = (1 - sat) * lr, ig = (1 - sat) * lg, ib = (1 - sat) * lb;

    return ColorFilter.matrix([
      scale * (ir + sat), scale * ig, scale * ib, 0, offset, //
      scale * ir, scale * (ig + sat), scale * ib, 0, offset,
      scale * ir, scale * ig, scale * (ib + sat), 0, offset,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Adjust editor (board 06, P4) — tool rail + the four live sliders over the
/// rendered look. Retouch is the working tool; the other rail entries select
/// (local edit state, §8) and note they arrive with the full studio pass.
/// Done pops with the adjustments — the result screen applies them (§2).
class WtmMirrorAdjustScreen extends StatefulWidget {
  const WtmMirrorAdjustScreen({
    super.key,
    required this.imageUrl,
    this.initial = const WtmAdjustments(),
  });

  final String imageUrl;
  final WtmAdjustments initial;

  @override
  State<WtmMirrorAdjustScreen> createState() => _WtmMirrorAdjustScreenState();
}

class _WtmMirrorAdjustScreenState extends State<WtmMirrorAdjustScreen> {
  late WtmAdjustments _adj = widget.initial;
  int _tool = 4; // Retouch

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tools = [
      (WtmGlyph.crop, l10n.wtmMirrorToolCrop),
      (WtmGlyph.rotate, l10n.wtmMirrorToolRotate),
      (WtmGlyph.erase, l10n.wtmMirrorToolErase),
      (WtmGlyph.swap, l10n.wtmMirrorToolSwap),
      (WtmGlyph.wand, l10n.wtmMirrorToolRetouch),
      (WtmGlyph.layers, l10n.wtmMirrorToolBackdrop),
    ];
    final sliders = [
      (l10n.wtmMirrorAdjBrightness, _adj.brightness,
          (double v) => _adj.copyWith(brightness: v)),
      (l10n.wtmMirrorAdjContrast, _adj.contrast,
          (double v) => _adj.copyWith(contrast: v)),
      (l10n.wtmMirrorAdjSaturation, _adj.saturation,
          (double v) => _adj.copyWith(saturation: v)),
      (l10n.wtmMirrorAdjShadows, _adj.shadows,
          (double v) => _adj.copyWith(shadows: v)),
    ];

    return WtmPage(
      fullBleed: true,
      title: l10n.wtmMirrorAdjustTitle,
      eyebrow: l10n.wtmMirrorAdjustEyebrow,
      onBack: () => Navigator.of(context).pop(_adj),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                for (final (i, tool) in tools.indexed) ...[
                  if (i > 0) const SizedBox(height: 7),
                  Semantics(
                    button: true,
                    selected: _tool == i,
                    label: tool.$2,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _tool = i);
                          if (i != 4) {
                            wtmSnack(context, l10n.wtmMirrorToolSoon);
                          }
                        },
                        child: Container(
                          width: 42,
                          height: 44, // .toolrail
                          decoration: BoxDecoration(
                            color: _tool == i
                                ? WtmColors.chipOnBg
                                : WtmColors.iconBtnBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _tool == i
                                  ? WtmColors.chipOnBorder
                                  : WtmColors.line,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              WtmIcon(
                                tool.$1,
                                size: 15,
                                color: _tool == i
                                    ? WtmColors.gold
                                    : WtmColors.muted,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tool.$2.toUpperCase(),
                                style: WtmType.micro.copyWith(
                                  fontSize: 6.3,
                                  letterSpacing: 0.38,
                                  color: _tool == i
                                      ? WtmColors.gold
                                      : WtmColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: WtmSpace.s10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColorFiltered(
                  colorFilter: _adj.toColorFilter(),
                  child: SizedBox(
                    height: 300,
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      cacheKey: stableImageCacheKey(widget.imageUrl),
                      fit: BoxFit.cover,
                      fadeInDuration: WtmMotion.base,
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      errorWidget: (_, _, _) => const AuroraBox(
                        borderRadius: BorderRadius.zero,
                        border: false,
                        vignette: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: WtmSpace.s12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: WtmGradients.cardFill,
            borderRadius: BorderRadius.circular(WtmRadius.card),
            border: Border.all(color: WtmColors.line),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  EyebrowLabel(l10n.wtmMirrorAdjustments),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: l10n.wtmMirrorReset,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _adj = const WtmAdjustments()),
                        child: Text(
                          l10n.wtmMirrorReset,
                          style: WtmType.micro.copyWith(color: WtmColors.gold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WtmSpace.s8),
              for (final (i, s) in sliders.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : WtmSpace.s6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(s.$1,
                            style:
                                WtmType.chip.copyWith(color: WtmColors.muted)),
                      ),
                      const SizedBox(width: WtmSpace.s10),
                      Expanded(
                        child: WtmSlider(
                          value: s.$2,
                          semanticLabel: s.$1,
                          onChanged: (v) => setState(() => _adj = s.$3(v)),
                        ),
                      ),
                      const SizedBox(width: WtmSpace.s10),
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${(s.$2 * 50 - 25).round()}',
                          textAlign: TextAlign.right,
                          style: WtmType.chip.copyWith(color: WtmColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        GhostButton(
          label: l10n.wtmMirrorDone,
          foregroundColor: WtmColors.gold,
          borderColor: WtmColors.chipOnBorder,
          icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.gold),
          onPressed: () => Navigator.of(context).pop(_adj),
        ),
      ],
    );
  }
}
