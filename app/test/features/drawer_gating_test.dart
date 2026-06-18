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

    test('free users below the limit have no locks', () {
      final drawers = [
        _d('def', isDefault: true),
        _d('u0', sort: 0),
        _d('u1', sort: 1),
        _d('u2', sort: 2),
      ];
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

    test('default/system drawers are never counted or locked', () {
      // 13 default drawers + 2 user drawers → nothing locked (defaults are free).
      final drawers = [
        for (var i = 0; i < 13; i++) _d('def$i', isDefault: true, sort: i),
        _d('u0', sort: 100),
        _d('u1', sort: 101),
      ];
      expect(lockedDrawerIds(drawers, isPremium: false), isEmpty);
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

    test('default drawers do not count against the create limit', () {
      final drawers = [
        for (var i = 0; i < 13; i++) _d('def$i', isDefault: true),
        _d('u0'),
        _d('u1'),
      ];
      // 2 user drawers < 3 → can still create even with 13 defaults present.
      expect(canCreateDrawer(drawers, isPremium: false), isTrue);
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
}
