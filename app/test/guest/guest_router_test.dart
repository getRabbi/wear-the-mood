import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/auth/guest_intercept.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/auth/wtm_auth_screen.dart';
import 'package:app/ui/auth/wtm_guest_preview.dart';
import 'package:app/ui/auth/wtm_welcome_screen.dart';
import 'package:app/ui/shell/wtm_shell.dart';

/// THE ROUTER GATE, on both platforms.
///
/// Two things are being proved here, and the second matters as much as the
/// first: that an iOS guest can browse the public app, and that ANDROID DID NOT
/// MOVE. Android's launch experience is already in users' hands; a guest button
/// appearing there, or a different signed-out landing, would be a regression
/// shipped in the name of an iOS fix.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  tearDown(() => guestIntercepts.value = null);

  /// Advances past a route transition WITHOUT `pumpAndSettle`.
  ///
  /// Every WTM entry screen draws `TheOrb`, which breathes forever — so
  /// `pumpAndSettle` never returns and times the test out. Fixed pumps are also
  /// what makes these deterministic rather than timing-dependent.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Captures router intercepts before the shell consumes them.
  ///
  /// The shell takes an intercept on the next frame to raise the conversion
  /// sheet, so reading `guestIntercepts.value` after pumping would always find
  /// null. Listening is how the test sees what the router actually recorded.
  List<GuestIntercept> recordIntercepts() {
    final seen = <GuestIntercept>[];
    void listener() {
      final value = guestIntercepts.value;
      if (value != null) seen.add(value);
    }

    guestIntercepts.addListener(listener);
    addTearDown(() => guestIntercepts.removeListener(listener));
    return seen;
  }

  /// Boots the real app with a pinned platform and session state.
  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required TargetPlatform platform,
    required AppSessionState session,
  }) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          PlatformCapabilities(platform: platform),
        ),
        appSessionProvider.overrideWithValue(session),
        isAuthenticatedProvider.overrideWithValue(
          session == AppSessionState.authenticated,
        ),
        onboardingSeenProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    // Through the splash (700ms orb beat) and its routing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  group('iOS signed-out lands on the account-choice gate', () {
    testWidgets('the welcome screen is shown, not the sign-in form', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.signedOut,
      );

      expect(find.byType(WtmWelcomeScreen), findsOneWidget);
      expect(find.byType(WtmAuthScreen), findsNothing);
    });

    testWidgets('all three choices are present and readable', (tester) async {
      await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.signedOut,
      );

      expect(find.text('Create My Wardrobe'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
      expect(find.text('Already have an account? Sign In'), findsOneWidget);
    });

    testWidgets(
      'Continue as Guest is a full-height tap target, not a footnote',
      (tester) async {
        await boot(
          tester,
          platform: TargetPlatform.iOS,
          session: AppSessionState.signedOut,
        );

        final guest = tester.getRect(find.text('Continue as Guest'));
        final create = tester.getRect(find.text('Create My Wardrobe'));
        // Same width class as the primary CTA — a real button, side by side in
        // the hierarchy rather than hidden at the bottom of a scroll.
        expect((guest.width - create.width).abs(), lessThan(40));
        // And it is above the fold on a default test viewport.
        expect(guest.top, lessThan(tester.view.physicalSize.height));
      },
    );

    testWidgets('Create My Wardrobe opens the auth screen in SIGN-UP mode', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.signedOut,
      );

      await tester.tap(find.text('Create My Wardrobe'));
      await settle(tester);

      expect(find.byType(WtmAuthScreen), findsOneWidget);
      final screen = tester.widget<WtmAuthScreen>(find.byType(WtmAuthScreen));
      expect(screen.initialSignUp, isTrue);
    });

    testWidgets('Sign In opens the auth screen in SIGN-IN mode', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.signedOut,
      );

      await tester.tap(find.text('Already have an account? Sign In'));
      await settle(tester);

      final screen = tester.widget<WtmAuthScreen>(find.byType(WtmAuthScreen));
      expect(screen.initialSignUp, isFalse);
    });
  });

  group('ANDROID IS UNCHANGED', () {
    testWidgets('signed-out Android still lands on the sign-in screen', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.android,
        session: AppSessionState.signedOut,
      );

      expect(find.byType(WtmAuthScreen), findsOneWidget);
      expect(find.byType(WtmWelcomeScreen), findsNothing);
    });

    testWidgets('Android never shows Continue as Guest', (tester) async {
      await boot(
        tester,
        platform: TargetPlatform.android,
        session: AppSessionState.signedOut,
      );

      expect(find.text('Continue as Guest'), findsNothing);
      expect(find.text('Create My Wardrobe'), findsNothing);
    });

    testWidgets('the Android auth screen opens in sign-in mode, as before', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.android,
        session: AppSessionState.signedOut,
      );

      final screen = tester.widget<WtmAuthScreen>(find.byType(WtmAuthScreen));
      expect(screen.initialSignUp, isFalse);
    });

    testWidgets(
      'an Android user who somehow reaches /wtm/welcome is corrected',
      (tester) async {
        final container = await boot(
          tester,
          platform: TargetPlatform.android,
          session: AppSessionState.signedOut,
        );

        container.read(goRouterProvider).go(AppRoute.wtmWelcome);
        await settle(tester);

        expect(find.byType(WtmAuthScreen), findsOneWidget);
        expect(find.byType(WtmWelcomeScreen), findsNothing);
      },
    );

    testWidgets('an authenticated Android user still lands in the shell', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.android,
        session: AppSessionState.authenticated,
      );

      expect(find.byType(WtmShell), findsOneWidget);
    });
  });

  group('an iOS guest browses the public app', () {
    Future<ProviderContainer> guestApp(WidgetTester tester) => boot(
      tester,
      platform: TargetPlatform.iOS,
      session: AppSessionState.guest,
    );

    testWidgets('a returning guest lands in the shell, not on the gate', (
      tester,
    ) async {
      await guestApp(tester);

      expect(find.byType(WtmShell), findsOneWidget);
      expect(find.byType(WtmWelcomeScreen), findsNothing);
      expect(find.byType(WtmAuthScreen), findsNothing);
    });

    for (final route in const [
      AppRoute.wtmHome,
      AppRoute.wtmDiscover,
      AppRoute.wtmShopSearch,
      AppRoute.wtmShopBrowse,
      AppRoute.wtmNewsroom,
      AppRoute.wtmGiveaways,
    ]) {
      testWidgets('$route stays open for a guest', (tester) async {
        final container = await guestApp(tester);
        final router = container.read(goRouterProvider);

        router.go(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          route,
          reason: '$route is public and must not be redirected',
        );
        expect(guestIntercepts.value, isNull);
      });
    }

    for (final route in const [
      AppRoute.wtmClosetAdd,
      AppRoute.wtmMirrorGarments,
      AppRoute.wtmMirrorGenerating,
      AppRoute.wtmBodyPhoto,
      AppRoute.wtmOutfits,
      AppRoute.wtmLooks,
      AppRoute.wtmTryOnHistory,
      AppRoute.wtmSaved,
      AppRoute.wtmInbox,
      AppRoute.wtmSettings,
      AppRoute.wtmPaywall,
      AppRoute.wtmStylist,
      AppRoute.wtmGiveawayCreate,
      AppRoute.wtmCompose,
    ]) {
      testWidgets('$route is intercepted for a guest', (tester) async {
        final container = await guestApp(tester);
        final router = container.read(goRouterProvider);

        // A DEEP LINK / push route, i.e. the path that bypasses every button.
        router.go(route);
        await settle(tester);

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          isNot(route),
          reason: '$route must never open for a guest',
        );
        // Landed somewhere PUBLIC, not on the sign-in gate — a guest bounced
        // out of the app entirely would be the same trap in a new place.
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoute.wtmHome,
        );
        expect(find.byType(WtmWelcomeScreen), findsNothing);
      });
    }

    testWidgets('an intercepted route records WHY, for the right sheet', (
      tester,
    ) async {
      final container = await guestApp(tester);
      final seen = recordIntercepts();
      container.read(goRouterProvider).go(AppRoute.wtmClosetAdd);
      await tester.pump();

      expect(seen.single.action, ProtectedAction.closet);
    });

    testWidgets('an intercepted product-shaped link keeps its public id', (
      tester,
    ) async {
      final container = await guestApp(tester);
      final seen = recordIntercepts();
      container
          .read(goRouterProvider)
          .go('${AppRoute.wtmSaved}?id=public-product-1');
      await tester.pump();

      expect(seen.single.action, ProtectedAction.saveProduct);
      // A PUBLIC id only — never a photo, a draft or anything private.
      expect(seen.single.resourceId, 'public-product-1');
    });

    testWidgets('the Closet tab shows a feature preview, not the real closet', (
      tester,
    ) async {
      final container = await guestApp(tester);
      container.read(goRouterProvider).go(AppRoute.wtmCloset);
      await settle(tester);

      expect(find.byType(WtmGuestClosetPreview), findsOneWidget);
      expect(find.text('A wardrobe that is only yours'), findsOneWidget);
    });

    testWidgets(
      'the try-on entry shows an honest explainer, never a fake result',
      (tester) async {
        final container = await guestApp(tester);
        container.read(goRouterProvider).go(AppRoute.wtmMirror);
        await settle(tester);

        expect(find.byType(WtmGuestTryOnPreview), findsOneWidget);
        expect(find.text('How Virtual Try-On works'), findsOneWidget);
        // The honesty clause is on screen, not implied by an absence.
        expect(
          find.textContaining('generated from your own photo'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Profile tab is an honest guest panel, not a fake profile',
      (tester) async {
        final container = await guestApp(tester);
        container.read(goRouterProvider).go(AppRoute.wtmProfile);
        await settle(tester);

        expect(find.byType(WtmGuestProfilePreview), findsOneWidget);
        expect(find.text('Browsing as a guest'), findsOneWidget);
      },
    );
  });

  group('an authenticated user is unaffected by any of it', () {
    testWidgets('protected routes open normally on iOS', (tester) async {
      final container = await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.authenticated,
      );
      final router = container.read(goRouterProvider);

      final seen = recordIntercepts();
      router.go(AppRoute.wtmCloset);
      await settle(tester);

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoute.wtmCloset,
      );
      // The real closet, not the preview.
      expect(find.byType(WtmGuestClosetPreview), findsNothing);
      expect(seen, isEmpty);
    });

    testWidgets('an authenticated iOS user never sees the welcome gate', (
      tester,
    ) async {
      await boot(
        tester,
        platform: TargetPlatform.iOS,
        session: AppSessionState.authenticated,
      );

      expect(find.byType(WtmWelcomeScreen), findsNothing);
      expect(find.byType(WtmShell), findsOneWidget);
    });
  });
}
