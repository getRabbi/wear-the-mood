import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/auth/wtm_welcome_screen.dart';

/// LAYOUT — the welcome screen on the devices App Review actually uses.
///
/// The reviewer's environment is an **iPad Air 11-inch (M3)**; the smallest
/// device this ships to is an iPhone SE. Both have to show all three choices
/// without overflow, at the default type size and at the larger ones people
/// really use.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Logical sizes; the harness multiplies by the DPR set below.
  const iPhoneSe = Size(320, 568); // the narrowest supported
  const iPhone15 = Size(393, 852);
  const iPadAir11Portrait = Size(834, 1210); // the reviewer's device
  const iPadAir11Landscape = Size(1210, 834);
  const iPadSplitHalf = Size(507, 1210); // Split View, half width

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(platform: TargetPlatform.iOS),
        ),
        appSessionProvider.overrideWithValue(AppSessionState.signedOut),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WtmWelcomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void expectAllThreeChoices() {
    expect(find.text('Create My Wardrobe'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Already have an account? Sign In'), findsOneWidget);
  }

  final devices = <String, Size>{
    'iPhone SE (320pt)': iPhoneSe,
    'iPhone 15 (393pt)': iPhone15,
    'iPad Air 11" portrait — the reviewer device': iPadAir11Portrait,
    'iPad Air 11" landscape': iPadAir11Landscape,
    'iPad Split View, half width': iPadSplitHalf,
  };

  devices.forEach((name, size) {
    testWidgets('$name shows all three choices with no overflow', (
      tester,
    ) async {
      await pump(tester, size: size);

      expectAllThreeChoices();
      expect(tester.takeException(), isNull);
    });
  });

  group('Dynamic Type', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${scale}x on the smallest phone still fits', (tester) async {
        await pump(tester, size: iPhoneSe, textScale: scale);

        expectAllThreeChoices();
        // A RenderFlex overflow raises here; the screen scrolls instead.
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('3.0x scrolls rather than overflowing', (tester) async {
      await pump(tester, size: iPhoneSe, textScale: 3.0);

      // The primary CTA is what must remain reachable at any size.
      expect(find.text('Create My Wardrobe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('every choice is a semantic button', (tester) async {
      await pump(tester, size: iPhone15);
      final handle = tester.ensureSemantics();

      for (final label in const [
        'Create My Wardrobe',
        'Continue as Guest',
        'Already have an account? Sign In',
      ]) {
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason: '"$label" must be reachable by VoiceOver',
        );
      }
      handle.dispose();
    });

    testWidgets('the guest choice meets the 48dp tap-target floor', (
      tester,
    ) async {
      await pump(tester, size: iPhone15);

      // The rendered button, not the text inside it.
      final button = find.ancestor(
        of: find.text('Continue as Guest'),
        matching: find.byType(Container),
      );
      final box = tester.getSize(button.first);
      expect(box.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the Sign In text action is also a full 48dp target', (
      tester,
    ) async {
      await pump(tester, size: iPhone15);

      final box = tester.getSize(
        find
            .ancestor(
              of: find.text('Already have an account? Sign In'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(box.height, greaterThanOrEqualTo(48));
    });
  });

  group('the hierarchy is honest', () {
    testWidgets('Create is above Guest, and Guest is above Sign In', (
      tester,
    ) async {
      await pump(tester, size: iPhone15);

      final create = tester.getRect(find.text('Create My Wardrobe')).center.dy;
      final guest = tester.getRect(find.text('Continue as Guest')).center.dy;
      final signIn = tester
          .getRect(find.text('Already have an account? Sign In'))
          .center
          .dy;

      expect(create, lessThan(guest));
      expect(guest, lessThan(signIn));
    });

    testWidgets('the guest choice is NOT hidden below the fold', (
      tester,
    ) async {
      // The dark-pattern failure mode: a guest option that technically exists
      // but requires scrolling to find. On the smallest supported phone at the
      // default type size, it must be visible without scrolling.
      await pump(tester, size: iPhoneSe);

      final guest = tester.getRect(find.text('Continue as Guest'));
      expect(guest.bottom, lessThanOrEqualTo(iPhoneSe.height));
    });

    testWidgets('the guest choice is not a tiny footnote', (tester) async {
      await pump(tester, size: iPhone15);

      final guest = tester.getRect(find.text('Continue as Guest'));
      final create = tester.getRect(find.text('Create My Wardrobe'));
      // Comparable prominence: same width band as the primary CTA.
      expect(guest.width, greaterThan(create.width * 0.6));
    });
  });

  group('off iOS the guest choice is simply absent', () {
    testWidgets('an Android-pinned policy renders only the account actions', (
      tester,
    ) async {
      tester.view.physicalSize = iPhone15;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(platform: TargetPlatform.android),
          ),
          appSessionProvider.overrideWithValue(AppSessionState.signedOut),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WtmWelcomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The second lock (the router is the first): even mounted directly, the
      // screen offers no guest path off iOS.
      expect(find.text('Continue as Guest'), findsNothing);
      expect(find.text('Create My Wardrobe'), findsOneWidget);
    });
  });
}
