import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/wardrobe/drawers/closet_drawer.dart';
import 'package:app/features/wardrobe/drawers/drawer_picker_sheet.dart';
import 'package:app/features/wardrobe/drawers/drawer_store.dart';
import 'package:app/l10n/app_localizations.dart';

ClosetDrawer _d(String id, {int sort = 0}) => ClosetDrawer(
      id: id,
      name: id,
      iconKind: DrawerIconKind.drawer,
      accentValue: 0xFF000000,
      kind: ClosetDrawerKind.drawer,
      sortOrder: sort,
    );

/// Stub store with a fixed drawer list (skips local-storage load).
class _FakeDrawers extends ClosetDrawersStore {
  _FakeDrawers(this._list);
  final List<ClosetDrawer> _list;
  @override
  List<ClosetDrawer> build() => _list;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // 5 drawers — for a FREE user the first 3 are usable; d3 + d4 are locked (§18).
  final drawers = [for (var i = 0; i < 5; i++) _d('d$i', sort: i)];

  Widget harness({required bool premium}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDrawerPickerSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoute.paywall,
          builder: (_, _) => const Scaffold(body: Text('PAYWALL')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        closetDrawersProvider.overrideWith(() => _FakeDrawers(drawers)),
        isPremiumProvider.overrideWithValue(premium),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('free user: drawers past the limit show Premium and route to the '
      'paywall instead of selecting', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(premium: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The two locked drawers (d3, d4) each carry the Premium badge.
    expect(find.text('Premium'), findsNWidgets(2));

    // Tapping a locked drawer opens the paywall — it is NOT chosen.
    await tester.tap(find.text('d3'));
    await tester.pumpAndSettle();
    expect(find.text('PAYWALL'), findsOneWidget);
  });

  testWidgets('premium user: no locked drawers, every drawer selectable',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(premium: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Premium'), findsNothing);

    // Selecting a drawer closes the sheet (returns its id) — no paywall.
    await tester.tap(find.text('d4'));
    await tester.pumpAndSettle();
    expect(find.text('PAYWALL'), findsNothing);
    expect(find.text('open'), findsOneWidget); // back home, sheet dismissed
  });
}
