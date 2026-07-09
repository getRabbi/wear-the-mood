import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/theme/wtm_colors.dart';
import 'package:app/theme/wtm_typography.dart';
import 'package:app/ui/widgets/widgets.dart';

/// P0 WTM kit smoke tests (UI_IMPLEMENTATION.md §5) — behavior only; visual
/// fidelity is verified against the board via /dev/gallery. Network-image
/// states (FabricTile.imageUrl) are exercised on device, not here.
void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('WtmScaffold builds its body on the noir base', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WtmScaffold(body: Text('content'))),
    );
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('GradientCta fires onPressed and disables when null', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(GradientCta(label: 'Generate Look', onPressed: () => tapped = true)),
    );
    expect(find.text('Generate Look'), findsOneWidget);
    await tester.tap(find.byType(GradientCta));
    expect(tapped, isTrue);

    await tester.pumpWidget(host(const GradientCta(label: 'Disabled')));
    // Disabled render dims via Opacity and has no gesture to fire.
    expect(
      find.descendant(
        of: find.byType(GradientCta),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );
  });

  testWidgets('GhostButton fires onPressed and honors the gold variant', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        GhostButton(
          label: 'Done',
          foregroundColor: WtmColors.gold,
          onPressed: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.byType(GhostButton));
    expect(tapped, isTrue);
    final text = tester.widget<Text>(find.text('Done'));
    expect(text.style?.color, WtmColors.gold);
  });

  testWidgets('GoldPill uppercases its label and taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(GoldPill(label: 'Enter Now', onTap: () => tapped = true)),
    );
    expect(find.text('ENTER NOW'), findsOneWidget);
    await tester.tap(find.byType(GoldPill));
    expect(tapped, isTrue);
  });

  testWidgets('WtmChip switches styling with `on` and fires onTap', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        WtmChipRow(
          children: [
            WtmChip(label: 'All', on: true, onTap: () => tapped = true),
            const WtmChip(label: 'Tops'),
          ],
        ),
      ),
    );
    final onText = tester.widget<Text>(find.text('All'));
    final offText = tester.widget<Text>(find.text('Tops'));
    expect(onText.style?.color, WtmColors.gold);
    expect(offText.style?.color, WtmType.chip.color);
    await tester.tap(find.text('All'));
    expect(tapped, isTrue);
  });

  testWidgets('FabricTile renders swatch face, badge, and taps', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 120,
          child: FabricTile(
            swatchIndex: 3,
            badge: FabricBadge.selected,
            onTap: () => tapped = true,
            semanticLabel: 'demo tile',
          ),
        ),
      ),
    );
    expect(find.byType(FabricTile), findsOneWidget);
    expect(find.byType(WtmIcon), findsOneWidget); // badge check glyph
    await tester.tap(find.byType(FabricTile));
    expect(tapped, isTrue);
  });

  testWidgets('AuroraBox layers child and grain without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const AuroraBox(width: 120, height: 160, vignette: true,
            child: Center(child: Text('fig'))),
      ),
    );
    expect(find.text('fig'), findsOneWidget);
    // Grain paints only after its texture decodes (a real-async decode that
    // stays pending in the fake-async test env — the overlay simply renders
    // empty here; on-device behavior is checked in the gallery).
    expect(find.byType(GrainOverlay), findsOneWidget);
  });

  testWidgets('TheOrb breathes normally and stays static under reduced '
      'motion', (tester) async {
    await tester.pumpWidget(host(const TheOrb()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(host(const TheOrb(), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 300));
    // Static under reduced motion: the breathe loop is stopped.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('EyebrowLabel uppercases and tints goldDim', (tester) async {
    await tester.pumpWidget(host(const EyebrowLabel("Today's mood")));
    final text = tester.widget<Text>(find.text("TODAY'S MOOD"));
    expect(text.style?.color, WtmColors.goldDim);
  });
}
