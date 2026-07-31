import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/config/feature_gates.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/ui/closet/wtm_cutout_editor_screen.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/theme/wtm_colors.dart';
import 'package:app/ui/closet/wtm_cutout_gate.dart';
import 'package:app/ui/closet/wtm_garment_detail_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// "Fix cutout" parity regression tests.
///
/// The bug: the affordance shipped on Android but not iOS. It was never a UI
/// condition — [canFixCutout] has no platform branch — but [kCutoutEditorEnabled]
/// is a compile-time `bool.fromEnvironment`, and only the Android pipeline was
/// passing `--dart-define=CUTOUT_EDITOR_ENABLED=true`. iOS builds compiled the
/// button away entirely. These tests pin the *rule* to be platform-independent;
/// `env/prod.json` + the codemagic `write_prod_env` step keep the *flag* so.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const eligible = WardrobeItem(
    id: 'w1',
    title: 'Noir silk blouse',
    category: 'tops',
    imageUrl: 'https://cdn.example/w1.jpg',
    cutoutUrl: 'https://cdn.example/w1-cutout.png',
  );
  const ineligible = WardrobeItem(
    id: 'w2',
    title: 'Wide trousers',
    category: 'bottoms',
    imageUrl: 'https://cdn.example/w2.jpg',
  );

  group('eligibility rule', () {
    test('needs both the gate and a cutout to correct', () {
      expect(canFixCutout(eligible, enabled: true), isTrue);
      // No background-removed cutout → genuinely ineligible, not hidden for
      // parity's sake.
      expect(canFixCutout(ineligible, enabled: true), isFalse);
      expect(canFixCutout(null, enabled: true), isFalse);
      // Gate off → never a dead button.
      expect(canFixCutout(eligible, enabled: false), isFalse);
    });

    test('gate still defaults OFF for an un-flagged build', () {
      // Guards the shipped-build promise: no define, no feature. `flutter test`
      // passes no --dart-define, so this reads the real const.
      expect(kCutoutEditorEnabled, isFalse);
      expect(canFixCutout(eligible, enabled: kCutoutEditorEnabled), isFalse);
    });
  });

  group('build config carries the gate to every platform', () {
    // The real defect was here, not in Dart: CI OVERWROTE app/env/prod.json from
    // a hand-written generator, and iOS only ever builds through Codemagic. A
    // gate missing from that generator compiled OFF on iOS however it was set
    // locally — which is precisely how Android got "Fix cutout" and iOS did not.
    //
    // The generator is no longer hand-written. Both the local build and every CI
    // workflow render prod.json from ONE committed policy file, so a gate cannot
    // be present in one path and absent from the other.
    test('the committed production policy states CUTOUT_EDITOR_ENABLED', () {
      final policy =
          jsonDecode(File('env/feature_policy.prod.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        policy['gates'] as Map<String, dynamic>,
        containsPair('CUTOUT_EDITOR_ENABLED', 'true'),
        reason: 'every gate the app reads must be stated in the one committed '
            'authority, or some build path silently compiles it away',
      );
    });

    test('prod dart-define example documents CUTOUT_EDITOR_ENABLED', () {
      final example = File('env/prod.json.example').readAsStringSync();
      expect(jsonDecode(example), containsPair('CUTOUT_EDITOR_ENABLED', 'true'));
    });
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required TargetPlatform platform,
    required WardrobeItem item,
    required bool enabled,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cutoutEditorEnabledProvider.overrideWithValue(enabled)],
        child: MaterialApp(
          theme: AppTheme.dark().copyWith(platform: platform),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WtmGarmentDetailScreen(item: item),
        ),
      ),
    );
    await tester.pump();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final name = platform == TargetPlatform.iOS ? 'iOS' : 'Android';

    testWidgets('$name shows Fix cutout for an eligible piece', (tester) async {
      await pumpDetail(
        tester,
        platform: platform,
        item: eligible,
        enabled: true,
      );
      expect(find.text('Fix cutout'), findsOneWidget);
      // Dark-mode contrast: the label rides the primary text token, not a
      // dimmed/transparent one.
      final button = tester.widget<GhostButton>(
        find.ancestor(
          of: find.text('Fix cutout'),
          matching: find.byType(GhostButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      expect(button.foregroundColor, WtmColors.text);
      expect(button.foregroundColor.a, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name hides Fix cutout for a piece with no cutout', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        platform: platform,
        item: ineligible,
        enabled: true,
      );
      expect(find.text('Fix cutout'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name hides Fix cutout when the gate is off', (tester) async {
      await pumpDetail(
        tester,
        platform: platform,
        item: eligible,
        enabled: false,
      );
      expect(find.text('Fix cutout'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name renders the eligible action list without overflow', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        platform: platform,
        item: eligible,
        enabled: true,
      );
      // A RenderFlex overflow paints an error and records an exception.
      expect(tester.takeException(), isNull);
      expect(find.byType(GhostButton), findsWidgets);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final name = platform == TargetPlatform.iOS ? 'iOS' : 'Android';

    testWidgets('$name Fix cutout opens the real editor route', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/detail',
        routes: [
          GoRoute(
            path: '/detail',
            builder: (_, _) => const WtmGarmentDetailScreen(item: eligible),
          ),
          GoRoute(
            path: AppRoute.wtmClosetFixCutout,
            // The real editor, so this also proves it mounts on iOS.
            builder: (_, _) => const WtmCutoutEditorScreen(item: eligible),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [cutoutEditorEnabledProvider.overrideWithValue(true)],
          child: MaterialApp.router(
            theme: AppTheme.dark().copyWith(platform: platform),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Fix cutout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Same route on both platforms, and the editor really built.
      expect(
        router.state.matchedLocation,
        AppRoute.wtmClosetFixCutout,
        reason: 'both platforms must invoke the identical route',
      );
      expect(find.byType(WtmCutoutEditorScreen), findsOneWidget);
    });
  }

  testWidgets('both platforms build the identical eligible action list', (
    tester,
  ) async {
    Future<List<String>> labelsOn(TargetPlatform platform) async {
      await pumpDetail(
        tester,
        platform: platform,
        item: eligible,
        enabled: true,
      );
      return tester
          .widgetList<GhostButton>(find.byType(GhostButton))
          .map((b) => b.label)
          .toList();
    }

    final android = await labelsOn(TargetPlatform.android);
    final ios = await labelsOn(TargetPlatform.iOS);
    expect(ios, equals(android));
    expect(ios, contains('Fix cutout'));
  });
}
