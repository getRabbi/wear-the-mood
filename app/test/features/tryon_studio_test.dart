import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/tryon/models/studio_models.dart';
import 'package:app/features/tryon/tryon_preselect.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

const _closet = [
  WardrobeItem(
    id: 'w1',
    title: 'White tee',
    category: 'top',
    imageUrl: 'https://x/1',
    cutoutStatus: 'done',
  ),
  WardrobeItem(
    id: 'w2',
    title: 'Black jeans',
    category: 'pants',
    imageUrl: 'https://x/2',
    cutoutStatus: 'done',
  ),
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // ───────────────────────────────────────────────── unit ──────────────────

  group('studio models', () {
    test('TryOnLayer.fromSource carries category, id, zIndex', () {
      final l = TryOnLayer.fromSource(
        imageUrl: 'https://x/1',
        category: 'top',
        wardrobeItemId: 'w1',
        zIndex: 2,
      );
      expect(l.id, isNotEmpty);
      expect(l.category, 'top');
      expect(l.wardrobeItemId, 'w1');
      expect(l.zIndex, 2);
      expect(l.scale, 1);
      expect(l.opacity, 1);
      expect(l.flipX, isFalse);
    });

    test('copyWith preserves identity while updating transforms', () {
      final l = TryOnLayer.fromSource(imageUrl: 'https://x/1');
      final moved = l.copyWith(x: 10, y: -5, scale: 1.5, flipX: true);
      expect(moved.id, l.id); // same layer
      expect(moved.imageUrl, l.imageUrl);
      expect(moved.x, 10);
      expect(moved.y, -5);
      expect(moved.scale, 1.5);
      expect(moved.flipX, isTrue);
    });

    test('OutfitStack and TryOnSession default their ids', () {
      final stack = OutfitStack(
        items: [TryOnLayer.fromSource(imageUrl: 'https://x/1')],
        styleTags: const ['minimal'],
      );
      expect(stack.id, isNotEmpty);
      expect(stack.items, hasLength(1));

      final session = TryOnSession(
        basePhotoUrl: 'https://x/me',
        mode: TryOnSessionMode.twoD,
        selectedItems: stack.items,
      );
      expect(session.id, isNotEmpty);
      expect(session.status, 'draft');
      expect(session.mode, TryOnSessionMode.twoD);
    });
  });

  // ─────────────────────────────────────────────── widget ──────────────────

  Widget wrap({List<WardrobeItem> closet = _closet}) => ProviderScope(
    overrides: [
      creditsProvider.overrideWith(
        (ref) async => const Credits(
          balance: 0,
          dailyFreeUsed: 0,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 5,
        ),
      ),
      avatarSignedUrlProvider.overrideWith((ref) async => null),
      wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(closet)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  PrimaryButton cta(WidgetTester tester) => tester.widget<PrimaryButton>(
    find.ancestor(
      of: find.text('Build 2D outfit'),
      matching: find.byType(PrimaryButton),
    ),
  );

  testWidgets('free user builds a multi-item 2D outfit stack', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pump();

    // Nothing selected yet — the CTA is disabled.
    expect(cta(tester).onPressed, isNull);

    // Add both pieces to the stack.
    await tester.tap(find.byType(SmartImageCard).at(0));
    await tester.pump();
    await tester.tap(find.byType(SmartImageCard).at(1));
    await tester.pump();

    // Both pieces show a selected check badge and the CTA is now enabled.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(cta(tester).onPressed, isNotNull);

    // Remove one via the outfit strip's close button → one piece left, still on.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });

  testWidgets('"Try this look" preselect seeds the studio stack', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(cta(tester).onPressed, isNull);

    // Simulate the community post seeding the studio before switching tabs.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TryOnScreen)),
    );
    container
        .read(tryOnPreselectProvider.notifier)
        .setImages(['https://x/look.jpg']);
    await tester.pump();

    // The stack now has the look's reference piece and the CTA is enabled; the
    // preselect was consumed (cleared).
    expect(cta(tester).onPressed, isNotNull);
    expect(container.read(tryOnPreselectProvider), isNull);
  });
}
