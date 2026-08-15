import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/theme/wtm_colors.dart';
import 'package:app/theme/wtm_surface.dart';
import 'package:app/ui/widgets/widgets.dart';

/// The four faces of a control — resting, pressed, selected, disabled — and the
/// nav's active/inactive pair.
///
/// These assert CONTRAST, not prettiness. Each one pins a value that used to be
/// low enough for the control to disappear on a `#08060F` page or on top of a
/// photograph, so the regression they guard against is "someone restores the
/// design board's browser-mock alpha and the button vanishes on a real phone".
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  BoxDecoration decorationOf(WidgetTester tester, Finder of) =>
      tester
              .widget<AnimatedContainer>(
                find.descendant(
                  of: of,
                  matching: find.byType(AnimatedContainer),
                ),
              )
              .decoration!
          as BoxDecoration;

  Color borderColorOf(BoxDecoration decoration) =>
      (decoration.border! as Border).top.color;

  group('WtmIconButton', () {
    testWidgets('rests on the glass surface, not a 2% ghost', (tester) async {
      await tester.pumpWidget(
        host(WtmIconButton(WtmGlyph.search, onTap: () {})),
      );
      final decoration = decorationOf(tester, find.byType(WtmIconButton));
      expect(decoration.color, WtmGlass.fill);
      expect(borderColorOf(decoration), WtmGlass.border);
    });

    testWidgets('brightens under the finger and returns on release', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(WtmIconButton(WtmGlyph.search, onTap: () {})),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WtmIconButton)),
      );
      await tester.pump();
      expect(
        decorationOf(tester, find.byType(WtmIconButton)).color,
        WtmGlass.fillPressed,
      );

      await gesture.up();
      await tester.pump();
      expect(
        decorationOf(tester, find.byType(WtmIconButton)).color,
        WtmGlass.fill,
      );
    });

    testWidgets('selected turns gold and carries a halo', (tester) async {
      await tester.pumpWidget(
        host(WtmIconButton(WtmGlyph.heart, selected: true, onTap: () {})),
      );
      final decoration = decorationOf(tester, find.byType(WtmIconButton));
      expect(decoration.color, WtmGlass.selectedFill);
      expect(borderColorOf(decoration), WtmGlass.selectedBorder);
      expect(decoration.boxShadow, isNotNull);

      final icon = tester.widget<WtmIcon>(
        find.descendant(
          of: find.byType(WtmIconButton),
          matching: find.byType(WtmIcon),
        ),
      );
      expect(icon.color, WtmColors.gold);
    });

    testWidgets('disabled stays readable and takes no taps', (tester) async {
      await tester.pumpWidget(host(const WtmIconButton(WtmGlyph.dots)));
      final decoration = decorationOf(tester, find.byType(WtmIconButton));
      expect(decoration.color, WtmGlass.fillDisabled);

      final icon = tester.widget<WtmIcon>(
        find.descendant(
          of: find.byType(WtmIconButton),
          matching: find.byType(WtmIcon),
        ),
      );
      // Readable, not a ghost: the disabled glyph keeps most of its alpha.
      expect(icon.color, WtmGlass.foregroundDisabled);
      expect(WtmGlass.foregroundDisabled.a, greaterThan(0.4));

      expect(
        find.descendant(
          of: find.byType(WtmIconButton),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('on imagery it brings its own puck and rim', (tester) async {
      await tester.pumpWidget(
        host(
          WtmIconButton(
            WtmGlyph.back,
            surface: WtmIconButtonSurface.image,
            onTap: () {},
          ),
        ),
      );
      final decoration = decorationOf(tester, find.byType(WtmIconButton));
      expect(decoration.color, WtmGlass.overlayFill);
      expect(borderColorOf(decoration), WtmGlass.overlayBorder);
      // A contact shadow, so the puck holds on a blown-out studio shot.
      expect(decoration.boxShadow, isNotNull);

      final icon = tester.widget<WtmIcon>(
        find.descendant(
          of: find.byType(WtmIconButton),
          matching: find.byType(WtmIcon),
        ),
      );
      expect(icon.color, WtmGlass.overlayForeground);
    });

    testWidgets('an explicit colour still wins (destructive actions)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          WtmIconButton(WtmGlyph.erase, color: WtmColors.danger, onTap: () {}),
        ),
      );
      final icon = tester.widget<WtmIcon>(
        find.descendant(
          of: find.byType(WtmIconButton),
          matching: find.byType(WtmIcon),
        ),
      );
      expect(icon.color, WtmColors.danger);
    });
  });

  group('WtmBottomNav', () {
    Widget nav(int index) => MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: WtmBottomNav(
          items: const [
            WtmNavItem(glyph: WtmGlyph.home, label: 'Home'),
            WtmNavItem(glyph: WtmGlyph.compass, label: 'Discover'),
            WtmNavItem(glyph: WtmGlyph.inbox, label: 'Inbox'),
            WtmNavItem(glyph: WtmGlyph.user, label: 'Profile'),
          ],
          currentIndex: index,
          onTap: (_) {},
          onOrbTap: () {},
        ),
      ),
    );

    testWidgets('the active destination is gold, the rest stay legible', (
      tester,
    ) async {
      // No pumpAndSettle anywhere near the nav — the orb breathes forever.
      await tester.pumpWidget(nav(1));
      await tester.pump();

      Color labelColor(String text) =>
          tester.widget<Text>(find.text(text.toUpperCase())).style!.color!;

      expect(labelColor('Discover'), WtmColors.gold);
      for (final inactive in ['Home', 'Inbox', 'Profile']) {
        expect(labelColor(inactive), WtmGlass.navInactive);
      }
      // The whole point: an inactive tab is not a disabled tab, and an 8px
      // label over a blurred backdrop cannot be translucent about it.
      expect(WtmGlass.navInactive.a, 1.0);
      expect(WtmGlass.navInactive.computeLuminance(), greaterThan(0.35));
    });

    testWidgets('the halo follows the selection without moving anything', (
      tester,
    ) async {
      await tester.pumpWidget(nav(0));
      await tester.pump();
      final before = tester.getRect(find.text('PROFILE'));

      await tester.pumpWidget(nav(3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getRect(find.text('PROFILE')),
        before,
        reason: 'the active treatment is a shadow, so layout cannot shift',
      );
    });
  });
}
