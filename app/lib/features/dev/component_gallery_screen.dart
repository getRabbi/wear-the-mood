import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../../ui/widgets/widgets.dart';

/// DEV-ONLY component gallery (`/dev/gallery`, debug builds only) — renders
/// every P0 widget in all states on the noir scaffold for side-by-side
/// comparison with `app/design/wear-the-mood-ui.html`. Not part of the product
/// surface: never linked from app UI, never shipped in release, strings
/// intentionally not localized.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  int _chipOn = 0;
  bool _tileSelected = true;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return WtmScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            WtmSpace.s22 * 2,
          ),
          children: [
            // ---- Header ----
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      border: Border.all(color: WtmColors.line),
                      borderRadius: BorderRadius.circular(11),
                      color: WtmColors.chipBg,
                    ),
                    alignment: Alignment.center,
                    child: const WtmIcon(
                      WtmGlyph.back,
                      size: 15,
                      color: WtmColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                const EyebrowLabel('WTM Kit · P0 Gallery'),
              ],
            ),
            const SizedBox(height: WtmSpace.s16),
            Text.rich(
              TextSpan(
                text: 'Wear the ',
                style: WtmType.display,
                children: [
                  TextSpan(
                    text: 'Mood',
                    style: WtmType.goldItalic(WtmType.display),
                  ),
                ],
              ),
            ),
            Text('Atelier Edition — compare against the HTML board.',
                style: WtmType.sub),
            const SizedBox(height: WtmSpace.s10),
            Row(
              children: [
                GoldPill(
                  label: 'Open P1 shell',
                  onTap: () => context.go(AppRoute.wtmHome),
                ),
              ],
            ),

            _section('Palette'),
            Wrap(
              spacing: WtmSpace.s10,
              runSpacing: WtmSpace.s10,
              children: const [
                _ColorDot('bg', WtmColors.bg),
                _ColorDot('bg2', WtmColors.bg2),
                _ColorDot('panel', WtmColors.panel),
                _ColorDot('gold', WtmColors.gold),
                _ColorDot('gold2', WtmColors.gold2),
                _ColorDot('text', WtmColors.text),
                _ColorDot('muted', WtmColors.muted),
                _ColorDot('faint', WtmColors.faint),
                _ColorDot('orchid', WtmColors.orchid),
                _ColorDot('violet', WtmColors.violet),
                _ColorDot('pinkish', WtmColors.pinkish),
                _ColorDot('ctaText', WtmColors.ctaText),
              ],
            ),

            _section('Typography'),
            Text.rich(
              TextSpan(
                text: 'Good evening,\n',
                style: WtmType.display,
                children: [
                  TextSpan(
                    text: 'Anika',
                    style: WtmType.goldItalic(WtmType.display),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s10),
            Text('H1 — Smart Closet', style: WtmType.h1),
            const SizedBox(height: WtmSpace.s6),
            Text('H2 — Moonlit Confidence', style: WtmType.h2),
            const SizedBox(height: WtmSpace.s8),
            Text(
              'Body — Express your mood. Define your style. The quick brown '
              'fox jumps over the lazy dog.',
              style: WtmType.body,
            ),
            const SizedBox(height: WtmSpace.s6),
            Text('Sub — Great lighting. Front pose. Arms by side.',
                style: WtmType.sub),
            const SizedBox(height: WtmSpace.s6),
            Text('Label — Upload a Garment', style: WtmType.label),
            const SizedBox(height: WtmSpace.s6),
            Text('Label medium — 2D Try-On', style: WtmType.labelMedium),
            const SizedBox(height: WtmSpace.s8),
            const EyebrowLabel("Eyebrow — Today's mood"),
            const SizedBox(height: WtmSpace.s6),
            Text('Micro — Evening · 22°C', style: WtmType.micro),

            _section('The Orb — breathing glow'),
            const SizedBox(height: WtmSpace.s12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TheOrb(size: 120),
                TheOrb(), // 47 — nav reference
                TheOrb(size: TheOrb.miniSize), // 34 — assistant mini
              ],
            ),
            const SizedBox(height: WtmSpace.s14),
            Text(
              reduceMotion
                  ? 'Reduced motion is ON — orb glow is static (resting state).'
                  : 'Glow breathes on a 4.5s ease-in-out loop (shadow only, '
                        'never size). Turns static under OS reduced motion.',
              style: WtmType.micro,
              textAlign: TextAlign.center,
            ),

            _section('Buttons'),
            GradientCta(
              label: 'Generate Look',
              icon: const WtmIcon(
                WtmGlyph.sparkle,
                size: 15,
                color: WtmColors.ctaText,
              ),
              onPressed: () {},
            ),
            const SizedBox(height: WtmSpace.s10),
            GradientCta(label: 'Next · Choose Mode', onPressed: () {}),
            const SizedBox(height: WtmSpace.s10),
            const GradientCta(label: 'Disabled CTA'),
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: 'Select from Gallery',
              icon: const WtmIcon(
                WtmGlyph.camera,
                size: 15,
                color: WtmColors.text,
              ),
              onPressed: () {},
            ),
            const SizedBox(height: WtmSpace.s10),
            GhostButton(
              label: 'Done',
              foregroundColor: WtmColors.gold,
              borderColor: WtmColors.chipOnBorder,
              icon: const WtmIcon(
                WtmGlyph.check,
                size: 15,
                color: WtmColors.gold,
              ),
              onPressed: () {},
            ),
            const SizedBox(height: WtmSpace.s10),
            const GhostButton(label: 'Disabled ghost'),
            const SizedBox(height: WtmSpace.s14),
            Row(
              children: [
                GoldPill(label: 'Enter Now', onTap: () {}),
                const SizedBox(width: WtmSpace.s10),
                const GoldPill(label: 'Shop Now'),
                const SizedBox(width: WtmSpace.s10),
                GoldPill(
                  label: 'Update',
                  icon: const WtmIcon(
                    WtmGlyph.plus,
                    size: 12,
                    color: WtmColors.gold,
                  ),
                  onTap: () {},
                ),
              ],
            ),

            _section('Chips — tap to select'),
            WtmChipRow(
              children: [
                for (final (i, label) in const [
                  'All',
                  'Tops',
                  'Bottoms',
                  'Dresses',
                  'Outerwear',
                ].indexed)
                  WtmChip(
                    label: label,
                    on: _chipOn == i,
                    onTap: () => setState(() => _chipOn = i),
                  ),
              ],
            ),

            _section('Fabric tiles — swatch colorways c1–c8'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9, // board .tilegrid gap
              crossAxisSpacing: 9,
              childAspectRatio: 3 / 4,
              children: [
                for (var i = 0; i < 8; i++)
                  FabricTile(swatchIndex: i, aspectRatio: null),
              ],
            ),
            const SizedBox(height: WtmSpace.s14),
            Text('Badges (tap left tile), square, image load, error → swatch:',
                style: WtmType.sub),
            const SizedBox(height: WtmSpace.s10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FabricTile(
                    swatchIndex: 2,
                    badge:
                        _tileSelected ? FabricBadge.selected : FabricBadge.add,
                    onTap: () =>
                        setState(() => _tileSelected = !_tileSelected),
                    semanticLabel: 'Selection demo tile',
                  ),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: FabricTile(
                    swatchIndex: 5,
                    badge: FabricBadge.add,
                  ),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: FabricTile(
                    swatchIndex: 1,
                    aspectRatio: 1, // board .tile.sq
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FabricTile(
                    imageUrl: 'https://picsum.photos/seed/wtm/600/800',
                    swatchIndex: 6,
                  ),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: FabricTile(
                    imageUrl: 'https://invalid.wearthemood.example/nope.jpg',
                    swatchIndex: 7,
                  ),
                ),
                SizedBox(width: 9),
                Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: WtmSpace.s6),
            Text(
              'Left: network image (shimmer → fade-in; falls back to swatch '
              'offline). Right: broken URL — swatch face stays.',
              style: WtmType.micro,
            ),

            _section('Aurora imagery'),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AuroraBox(height: 150),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: AuroraBox(height: 150, vignette: true),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: AuroraBox(height: 150, grain: false),
                ),
              ],
            ),
            const SizedBox(height: WtmSpace.s6),
            Text('Standard · with vignette · grain off', style: WtmType.micro),
            const SizedBox(height: WtmSpace.s10),
            AuroraBox(
              height: 170,
              vignette: true,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(WtmSpace.s14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const EyebrowLabel("Today's look"),
                    const SizedBox(height: WtmSpace.s6),
                    Text.rich(
                      TextSpan(
                        text: 'Moonlit ',
                        style: WtmType.h2.copyWith(fontSize: 20),
                        children: [
                          TextSpan(
                            text: 'Confidence',
                            style: WtmType.goldItalic(
                              WtmType.h2.copyWith(fontSize: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: WtmSpace.s4),
                    Text('Evening · 22°C', style: WtmType.micro),
                  ],
                ),
              ),
            ),

            _section('Card recipe (§1.1 fill + line border)'),
            Container(
              padding: const EdgeInsets.all(WtmSpace.s14 + 1), // .card 15
              decoration: BoxDecoration(
                gradient: WtmGradients.cardFill,
                border: Border.all(color: WtmColors.line),
                borderRadius: BorderRadius.circular(WtmRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EyebrowLabel('Style DNA'),
                  const SizedBox(height: WtmSpace.s10),
                  const Wrap(
                    spacing: WtmSpace.s6,
                    runSpacing: WtmSpace.s6,
                    children: [
                      WtmChip(label: 'Romantic', on: true),
                      WtmChip(label: 'Street', on: true),
                      WtmChip(label: 'Bold', on: true),
                    ],
                  ),
                  const SizedBox(height: WtmSpace.s10),
                  Text.rich(
                    TextSpan(
                      text: 'AI insight',
                      style: WtmType.micro.copyWith(color: WtmColors.gold),
                      children: [
                        TextSpan(
                          text:
                              ' — you blend soft romance with a modern edge.',
                          style: WtmType.micro,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            _section('Icon glyphs (P0 set · 1.5-stroke)'),
            const Row(
              children: [
                WtmIcon(WtmGlyph.check, color: WtmColors.gold),
                SizedBox(width: WtmSpace.s14),
                WtmIcon(WtmGlyph.plus, color: WtmColors.gold),
                SizedBox(width: WtmSpace.s14),
                WtmIcon(WtmGlyph.sparkle, color: WtmColors.gold),
                SizedBox(width: WtmSpace.s14),
                WtmIcon(WtmGlyph.camera, color: WtmColors.gold),
                SizedBox(width: WtmSpace.s14),
                WtmIcon(WtmGlyph.back, color: WtmColors.gold),
                SizedBox(width: WtmSpace.s14),
                WtmIcon(WtmGlyph.chevron, color: WtmColors.gold),
              ],
            ),

            const SizedBox(height: WtmSpace.s22),
            const Divider(color: WtmColors.lineSoft, height: 1),
            const SizedBox(height: WtmSpace.s12),
            Text(
              'Grain: 140px tile · BlendMode.overlay @ 9%. Debug-only route — '
              'not shipped in release builds.',
              style: WtmType.micro,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: WtmSpace.s22, bottom: WtmSpace.s10),
      child: EyebrowLabel(title),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: WtmColors.line),
          ),
        ),
        const SizedBox(height: WtmSpace.s4),
        Text(name, style: WtmType.micro),
      ],
    );
  }
}
