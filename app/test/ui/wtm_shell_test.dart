import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/closet/wtm_closet_screen.dart';
import 'package:app/ui/closet/wtm_garment_detail_screen.dart';
import 'package:app/ui/home/wtm_home_screen.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/discover/wtm_giveaways_screen.dart';
import 'package:app/ui/discover/wtm_inbox_screen.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';
import 'package:app/ui/discover/wtm_offers_screen.dart';
import 'package:app/ui/mirror/wtm_mirror_step1.dart';
import 'package:app/ui/profile/wtm_profile_screen.dart';
import 'package:app/ui/shell/upload_hub_sheet.dart';

import '../helpers/fake_wardrobe_items.dart';
import 'package:app/ui/widgets/widgets.dart';

/// P1 gate: the WTM shell tap-through has zero dead ends (§5/§8). These boot
/// the real app router (debug build → /wtm exists, auth gate bypassed) and
/// walk the §8 graph. No pumpAndSettle — the orb breathes forever; transitions
/// are advanced with an explicit pump-pair (first pump starts tickers, second
/// advances them).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Material 3's Android page transition (FadeForwards) runs 800ms — settle
  // must outlast it. First pump starts tickers, second advances them, the
  // trailing pump lets a finished pop remove its overlay entry.
  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(WidgetTester tester) async {
    // Phone-shaped surface (360×780 logical) so board-metric layouts fit and
    // tap targets aren't below the test fold.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      // Real Inbox / Discover screens fetch over the network here (no data) and
      // land on their error/empty faces; disable the backoff retry so it never
      // trips the pending-timer check at teardown.
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        // Real Mirror Step 1 (P4) reads the try-on photo gallery; an empty list
        // keeps it off the network and on its "add a body photo" empty face.
        tryonPhotosProvider.overrideWith((ref) => const <TryonPhoto>[]),
        // Real closet screen (P3) needs wardrobe data; null image URLs keep
        // tiles on their swatch faces (no network in widget tests).
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [
            WardrobeItem(id: 'w1', title: 'Noir silk blouse', category: 'tops'),
            WardrobeItem(id: 'w2', title: 'Wide trousers', category: 'bottoms'),
            WardrobeItem(id: 'w3', title: 'Trench', category: 'outerwear'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmHome);
    await settle(tester);
    return container;
  }

  // Tap, scrolling into view first ONLY when needed — a blind ensureVisible
  // aligns the target to the viewport top even when it's already visible,
  // silently disturbing every list's scroll state.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    final target = finder.first;
    final rect = tester.getRect(target);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // Keep clear of the floating bottom nav (~100px) too.
    final visible = rect.center.dy >= 0 &&
        rect.center.dy <= screen.height - 100 &&
        rect.center.dx >= 0 &&
        rect.center.dx <= screen.width;
    if (!visible) {
      await tester.ensureVisible(target);
      await tester.pump();
    }
    await tester.tap(target);
    await settle(tester);
  }

  // Scope a finder to the CURRENTLY VISIBLE stub — offstage IndexedStack
  // branches (and pages under the top route) stay in the tree, so bare
  // `.first`/text finders can match invisible widgets.
  Finder onScreen(Type screen, Finder inner) =>
      find.descendant(of: find.byType(screen), matching: inner);

  testWidgets('shell renders Home with the 4-tab nav + orb', (tester) async {
    await boot(tester);
    expect(find.byType(WtmHomeScreen), findsOneWidget);
    expect(find.byType(WtmBottomNav), findsOneWidget);
    expect(find.byType(TheOrb), findsWidgets);
    expect(find.text('SOCIAL'), findsOneWidget);
    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('tabs switch branches: Social, Inbox, Profile, back Home', (
    tester,
  ) async {
    await boot(tester);
    await tapAndSettle(tester, find.text('SOCIAL'));
    expect(find.byType(WtmSocialScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('INBOX'));
    expect(find.byType(WtmInboxScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('PROFILE'));
    expect(find.byType(WtmProfileScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('HOME'));
    expect(find.byType(WtmHomeScreen), findsOneWidget);
  });

  testWidgets('orb opens the Upload Hub sheet; Try It On lands on Step 1', (
    tester,
  ) async {
    await boot(tester);
    // The nav orb is the last TheOrb in the tree (stubs may render minis).
    await tapAndSettle(tester, find.byType(TheOrb).last);
    // The hub now opens 140ms into the orb's tap burst — one more settle so
    // the sheet's entrance ticker gets real elapsed frames in test time.
    await settle(tester);
    expect(find.byType(UploadHubSheet), findsOneWidget);
    expect(find.text('Upload Hub'), findsOneWidget);

    await tapAndSettle(tester, find.text('Try It On'));
    expect(find.byType(WtmMirrorStep1Screen), findsOneWidget);
  });

  testWidgets(
      'orb tap plays the LIVE burst (ring visible) before the Upload Hub '
      'opens (mobile QA)', (tester) async {
    await boot(tester);
    await tester.tap(find.byType(TheOrb).last, warnIfMissed: false);
    // Mid-burst (before the 140ms head start elapses): the expanding halo
    // ring is on screen and the sheet hasn't opened yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(wtmOrbBurstRingKey), findsOneWidget);
    expect(find.byType(UploadHubSheet), findsNothing);

    // Head start over → the Upload Hub opens while the burst finishes.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UploadHubSheet), findsOneWidget);
  });

  testWidgets('orb respects reduced motion: no burst, still navigates', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await boot(tester);
    await tester.tap(find.byType(TheOrb).last, warnIfMissed: false);
    await tester.pump();
    // No burst ring, and navigation is immediate (no 140ms head start).
    expect(find.byKey(wtmOrbBurstRingKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UploadHubSheet), findsOneWidget);
  });

  // The deep MoodMirror flow (step transitions, credit gating, generate →
  // generating → result → adjust) needs the real credits/controller providers
  // mocked — it lives in wtm_mirror_test.dart. The shell only proves every
  // ENTRY POINT reaches Step 1 (no dead ends), like the closet's deep money
  // path lives in wtm_closet_test.dart rather than here.

  testWidgets('Home quick actions: closet grid → garment detail', (
    tester,
  ) async {
    await boot(tester);
    await tapAndSettle(tester, find.text('Smart\nCloset'));
    expect(find.byType(WtmClosetScreen), findsOneWidget);

    await tapAndSettle(
        tester, onScreen(WtmClosetScreen, find.byType(FabricTile)).first);
    expect(find.byType(WtmGarmentDetailScreen), findsOneWidget);

    await tapAndSettle(
        tester, onScreen(WtmGarmentDetailScreen, find.text('Try It On')));
    expect(find.byType(WtmMirrorStep1Screen), findsOneWidget);
  });

  testWidgets('Discover: Home row reaches Giveaways / Offers / Newsroom',
      (tester) async {
    final container = await boot(tester);
    // The Discover row sits below the fold on Home — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Giveaways'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester, 200);
    await tapAndSettle(tester, find.text('Giveaways'));
    expect(find.byType(WtmGiveawaysScreen), findsOneWidget);

    // The deep giveaway enter-flow (browse → detail → claim) needs the real
    // giveaway providers mocked — it lives in wtm_discover_test.dart.
    final router = container.read(goRouterProvider);
    router.go(AppRoute.wtmOffers);
    await settle(tester);
    expect(find.byType(WtmOffersScreen), findsOneWidget);

    router.go(AppRoute.wtmNewsroom);
    await settle(tester);
    expect(find.byType(WtmNewsroomScreen), findsOneWidget);
  });

  // The deep Profile flow (stats → follow lists, ⋯ → Settings, Delete Account)
  // needs the real profile/account providers mocked — it lives in
  // wtm_profile_test.dart. The shell only proves the Profile tab renders.
}
