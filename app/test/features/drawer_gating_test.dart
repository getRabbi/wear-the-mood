import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/wardrobe/drawers/closet_drawer.dart';
import 'package:app/features/wardrobe/drawers/drawer_card.dart';
import 'package:app/features/wardrobe/drawers/drawer_gating.dart';
import 'package:app/l10n/app_localizations.dart';

ClosetDrawer _d(String id, {bool isDefault = false, int sort = 0}) =>
    ClosetDrawer(
      id: id,
      name: id,
      iconKind: DrawerIconKind.drawer,
      accentValue: 0xFF000000,
      kind: ClosetDrawerKind.drawer,
      sortOrder: sort,
      isDefault: isDefault,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // ── gating logic (the money-adjacent path) ────────────────────────────────

  group('lockedDrawerIds', () {
    test('premium users never have locked drawers', () {
      final drawers = [for (var i = 0; i < 8; i++) _d('u$i', sort: i)];
      expect(lockedDrawerIds(drawers, isPremium: true), isEmpty);
    });

    test('free users at or below 3 total have no locks', () {
      final drawers = [
        _d('def', isDefault: true, sort: 0),
        _d('u0', sort: 0),
        _d('u1', sort: 1),
      ]; // 3 total
      expect(lockedDrawerIds(drawers, isPremium: false), isEmpty);
    });

    test('free users lock their own drawers beyond the first 3', () {
      final drawers = [
        _d('u0', sort: 0),
        _d('u1', sort: 1),
        _d('u2', sort: 2),
        _d('u3', sort: 3),
        _d('u4', sort: 4),
      ];
      expect(
        lockedDrawerIds(drawers, isPremium: false),
        {'u3', 'u4'},
      );
    });

    test('free users: every drawer beyond the first 3 is locked (incl. defaults)',
        () {
      final drawers = [
        for (var i = 0; i < 5; i++) _d('def$i', isDefault: true, sort: i),
      ];
      // first 3 defaults are free; the rest are locked.
      expect(lockedDrawerIds(drawers, isPremium: false), {'def3', 'def4'});
    });
  });

  group('canCreateDrawer', () {
    test('premium can always create', () {
      final drawers = [for (var i = 0; i < 9; i++) _d('u$i', sort: i)];
      expect(canCreateDrawer(drawers, isPremium: true), isTrue);
    });

    test('free can create below the limit, not at it', () {
      List<ClosetDrawer> mine(int n) => [for (var i = 0; i < n; i++) _d('u$i', sort: i)];
      expect(canCreateDrawer(mine(2), isPremium: false), isTrue);
      expect(canCreateDrawer(mine(kFreeUserDrawerLimit), isPremium: false), isFalse);
      expect(canCreateDrawer(mine(kFreeUserDrawerLimit + 1), isPremium: false), isFalse);
    });

    test('default drawers DO count — a free user with 3+ cannot create more', () {
      final drawers = [
        for (var i = 0; i < 13; i++) _d('def$i', isDefault: true, sort: i),
      ];
      // 13 defaults ≥ 3 → free user is capped, creating opens the paywall.
      expect(canCreateDrawer(drawers, isPremium: false), isFalse);
    });
  });

  // ── locked card renders the upgrade affordance ────────────────────────────

  testWidgets('a locked DrawerCard shows a lock + Premium badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 180,
              child: DrawerCard(
                drawer: _d('u3', sort: 3),
                count: 4,
                previews: const [],
                locked: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
  });

  testWidgets('an unlocked DrawerCard shows its label and fires onTap (the morph '
      'trigger)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 180,
              child: DrawerCard(
                drawer: _d('u0', sort: 0),
                count: 2,
                previews: const [],
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Labelled drawer front: name + item count are on the face; no lock.
    expect(find.text('u0'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    await tester.tap(find.byType(DrawerCard));
    expect(taps, 1);
  });
}
