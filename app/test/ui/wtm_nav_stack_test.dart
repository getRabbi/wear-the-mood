import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/privacy/ai_consent_repository.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/route_stack.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/app_notification.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/stylist_suggestion.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/notifications_repository.dart';
import 'package:app/data/repositories/stylist_repository.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/social/post_image_service.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/features/tryon/tryon_trace.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_inbox_screen.dart';
import 'package:app/ui/discover/wtm_discover_screen.dart';
import 'package:app/ui/discover/wtm_newsroom_screen.dart';
import 'package:app/ui/home/wtm_home_screen.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_generating.dart';
import 'package:app/ui/mirror/wtm_mirror_result.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/ui/mirror/wtm_mirror_step3.dart';
import 'package:app/ui/profile/wtm_profile_screen.dart';

import '../helpers/fake_ai_consent.dart';
import '../helpers/fake_wardrobe_items.dart';

/// The route STACK, as a contract.
///
/// Navigation defects in this app have all had the same shape: the screen that
/// appears is right and the pages left underneath it are wrong. Nothing catches
/// that — a `findsOneWidget` on the destination passes just as happily over a
/// stack four copies deep as over a clean one — so this suite asserts the page
/// list itself, through [routeStackOf].
///
/// The defect it was written for: finishing a try-on and pressing Back walked
/// the user INTO the run they had just completed — the mode step, then the
/// Garments step they had already filled in, with a Generate button that would
/// spend credits again.

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

const _resultJob = TryOnJob(
  jobId: 'job1',
  status: TryOnStatus.done,
  resultImageUrl: 'https://cdn.test/look.png',
);

/// Submits into the in-flight state and finishes only when [finish] is called,
/// so a test can hold the render open and then land it deliberately.
class _ManualTryOnController extends TryOnController {
  @override
  Future<void> start({
    required String personImageUrl,
    required List<TryOnGarmentRef> garments,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,
    TryOnTrace? trace,
  }) async {
    state = const TryOnState.submitting();
  }

  void finish() => state = const TryOnState.success(_resultJob);

  void fail() => state = const TryOnState.failure(
    message: 'The render could not be made.',
  );
}

class _DoneTryOnController extends TryOnController {
  @override
  TryOnState build() => const TryOnState.success(_resultJob);
}

class _FakePostImageService implements PostImageService {
  @override
  Future<String> upload(Uint8List bytes, {String sector = 'post'}) async =>
      'https://cdn.test/durable.png';

  @override
  Future<Uint8List> downloadImageBytes(String url) async =>
      Uint8List.fromList(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, //
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeNotifs implements NotificationsRepository {
  _FakeNotifs(this.items);
  final List<AppNotification> items;

  @override
  Future<List<AppNotification>> getNotifications({
    int limit = NotificationsRepository.pageSize,
    DateTime? before,
    String? beforeId,
  }) async => before == null ? items : const [];
  @override
  Future<int> unreadCount() async => items.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async => [
    NewsItem(
      id: 'a1',
      title: 'One black dress, three evening moods',
      source: 'Atelier Desk',
      createdAt: DateTime(2026, 8, 1),
    ),
  ];
  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// The stylist look screen asks for a suggestion the moment it opens. These
/// tests are about the page STACK, so the request is answered locally rather
/// than left to reach for a Supabase session that a widget test does not have.
class _FakeStylist implements StylistRepository {
  @override
  Future<StylistSuggestion> suggest({
    double? latitude,
    double? longitude,
    String? occasion,
    String? note,
  }) async => const StylistSuggestion(
    title: 'Soft tailoring',
    rationale: 'Warm, dry, and nothing formal on the calendar.',
    items: [_garment],
  );

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

const _proMax = Credits(
  balance: 40,
  dailyFreeUsed: 0,
  dailyFreeLimit: 0,
  dailyFreeRemaining: 0,
  totalAvailable: 40,
  tier: 'pro_max',
  hdAllowed: true,
  stdCost: 1,
  hdCost: 4,
);

const _garment = WardrobeItem(
  id: 'g1',
  title: 'Noir silk blouse',
  category: 'tops',
  imageUrl: 'https://cdn.test/g1.png',
);

/// Session state a test can flip, so sign-in and sign-out are transitions
/// rather than two separate boots.
final _signedIn = NotifierProvider<_Session, bool>(_Session.new);

class _Session extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<(GoRouter, ProviderContainer)> boot(
    WidgetTester tester, {
    String at = AppRoute.wtmHome,
    TryOnController Function()? controller,
    List<AppNotification> notifs = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWith((ref) => ref.watch(_signedIn)),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [_garment]),
        ),
        tryonPhotosProvider.overrideWith(
          (ref) async => const [
            TryonPhoto(
              id: 'p1',
              storagePath: 'bodies/p1.png',
              signedUrl: 'https://cdn.test/body.png',
              isSelected: true,
            ),
          ],
        ),
        avatarSignedUrlProvider.overrideWith(
          (ref) async => 'https://cdn.test/body.png',
        ),
        creditsProvider.overrideWith((ref) async => _proMax),
        isPremiumProvider.overrideWithValue(true),
        aiConsentRepositoryProvider.overrideWithValue(FakeAiConsentRepo()),
        postImageServiceProvider.overrideWithValue(_FakePostImageService()),
        notificationsRepositoryProvider.overrideWithValue(_FakeNotifs(notifs)),
        stylistRepositoryProvider.overrideWithValue(_FakeStylist()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        if (controller != null)
          tryOnControllerProvider.overrideWith(controller),
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
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return (container.read(goRouterProvider), container);
  }

  /// Every page location on the stack, bottom to top.
  List<String> stack(GoRouter router) => routeStackOf(router);

  // -------------------------------------------------------------------------
  // The shell
  // -------------------------------------------------------------------------

  group('the shell is four destinations, not a growing stack', () {
    testWidgets('cycling every tab leaves exactly one page on the stack', (
      tester,
    ) async {
      final (router, _) = await boot(tester);

      for (var lap = 0; lap < 3; lap++) {
        for (final tab in const [
          AppRoute.wtmHome,
          AppRoute.wtmDiscover,
          AppRoute.wtmInbox,
          AppRoute.wtmProfile,
        ]) {
          router.go(tab);
          await settle(tester);
          expect(
            stack(router),
            [tab],
            reason: 'a tab is a destination, not something you stack onto',
          );
        }
      }
    });

    testWidgets('tapping the tab you are already on adds no page', (
      tester,
    ) async {
      final (router, _) = await boot(tester, at: AppRoute.wtmProfile);
      for (var i = 0; i < 4; i++) {
        router.go(AppRoute.wtmProfile);
        await settle(tester);
      }
      expect(stack(router), [AppRoute.wtmProfile]);
      expect(find.byType(WtmProfileScreen), findsOneWidget);
    });

    testWidgets('a branch keeps its own stack while another tab is used', (
      tester,
    ) async {
      // Tab state preservation, through the control the user actually uses.
      // The bottom bar calls `goBranch`, which parks the branch's stack and
      // brings it back; `go` to a branch ROOT is a different intention — an
      // explicit "take me to Home" — and resets it, which is why the nav bar
      // does not use it.
      final (router, _) = await boot(tester);
      router.push(AppRoute.wtmCloset);
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome, AppRoute.wtmCloset]);

      await tester.tap(find.text('INBOX'));
      await settle(tester);
      expect(find.byType(WtmInboxScreen), findsOneWidget);

      await tester.tap(find.text('HOME'));
      await settle(tester);
      expect(
        stack(router),
        [AppRoute.wtmHome, AppRoute.wtmCloset],
        reason: 'the Home branch kept its page, and only one copy of it',
      );
    });

    testWidgets('re-tapping the active tab resets it to its root', (
      tester,
    ) async {
      // Standard tab behaviour, and the thing that must NOT happen instead is
      // a second copy of the destination being pushed.
      final (router, _) = await boot(tester);
      router.push(AppRoute.wtmCloset);
      await settle(tester);

      await tester.tap(find.text('HOME'));
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome]);

      await tester.tap(find.text('HOME'));
      await tester.tap(find.text('HOME'));
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome]);
    });

    testWidgets("Today's Look opens its detail and Back returns to Home", (
      tester,
    ) async {
      final (router, _) = await boot(tester);
      router.push(AppRoute.wtmStylistLook);
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome, AppRoute.wtmStylistLook]);

      router.pop();
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome]);
      expect(find.byType(WtmHomeScreen), findsOneWidget);
    });

    testWidgets('Discover → a profile → Back keeps Discover underneath', (
      tester,
    ) async {
      final (router, _) = await boot(tester, at: AppRoute.wtmDiscover);
      router.push('${AppRoute.wtmUser}?u=u2');
      await settle(tester);
      expect(stack(router), [AppRoute.wtmDiscover, '${AppRoute.wtmUser}?u=u2']);

      router.pop();
      await settle(tester);
      expect(stack(router), [AppRoute.wtmDiscover]);
      expect(find.byType(WtmDiscoverScreen), findsOneWidget);
    });

    testWidgets('Home shortcuts open over Home without stacking a shell', (
      tester,
    ) async {
      final (router, _) = await boot(tester);
      router.push(AppRoute.wtmNewsroom);
      await settle(tester);

      expect(stack(router), [AppRoute.wtmHome, AppRoute.wtmNewsroom]);
      expect(find.byType(WtmNewsroomScreen), findsOneWidget);

      router.pop();
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome]);
      expect(find.byType(WtmHomeScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // The reported defect
  // -------------------------------------------------------------------------

  group('a finished try-on leaves its wizard behind', () {
    /// Walks the Garments flow to the point where the render is in flight,
    /// entered from [from] exactly as a Try On affordance would.
    Future<(GoRouter, _ManualTryOnController, ProviderContainer)> generate(
      WidgetTester tester, {
      String from = AppRoute.wtmDiscover,
      _ManualTryOnController? using,
    }) async {
      final controller = using ?? _ManualTryOnController();
      final (router, container) = await boot(
        tester,
        at: from,
        controller: () => controller,
      );

      router.push(AppRoute.wtmMirrorGarments);
      await settle(tester);
      expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);

      // Choose the garment the closet fixture provides, then advance.
      container.read(wtmMirrorFlowProvider.notifier).toggleItem(_garment);
      await settle(tester);
      router.push(AppRoute.wtmMirrorMode);
      await settle(tester);
      expect(find.byType(WtmMirrorStep3Screen), findsOneWidget);

      router.push(AppRoute.wtmMirrorGenerating);
      await settle(tester);
      expect(find.byType(WtmMirrorGeneratingScreen), findsOneWidget);
      controller.start(personImageUrl: 'x', garments: const [TryOnGarmentRef(imageUrl: 'y', category: 'Tops')]);
      await settle(tester);

      expect(
        stack(router),
        [
          from,
          AppRoute.wtmMirrorGarments,
          AppRoute.wtmMirrorMode,
          AppRoute.wtmMirrorGenerating,
        ],
        reason: 'the wizard really is on the stack while it is being used',
      );
      return (router, controller, container);
    }

    testWidgets('the completed steps come off when the render lands', (
      tester,
    ) async {
      final (router, controller, _) = await generate(tester);

      controller.finish();
      await settle(tester);

      expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
      expect(
        stack(router),
        [AppRoute.wtmDiscover, AppRoute.wtmMirrorResult],
        reason: 'the render sits on the surface the try-on started from',
      );
    });

    testWidgets('Back from the render lands on the origin, not on Garments', (
      tester,
    ) async {
      // The reported defect, exactly: complete a look, press Back, and the app
      // put the user back into the Garments step.
      final (router, controller, _) = await generate(tester);
      controller.finish();
      await settle(tester);

      router.pop(); // the system Back button / iOS edge swipe do this too
      await settle(tester);

      expect(stack(router), [AppRoute.wtmDiscover]);
      expect(find.byType(WtmMirrorStep2Screen), findsNothing);
      expect(find.byType(WtmMirrorStep3Screen), findsNothing);
    });

    testWidgets('the same holds when the flow started from Home', (
      tester,
    ) async {
      final (router, controller, _) = await generate(
        tester,
        from: AppRoute.wtmHome,
      );
      controller.finish();
      await settle(tester);

      expect(stack(router), [AppRoute.wtmHome, AppRoute.wtmMirrorResult]);
      router.pop();
      await settle(tester);
      expect(stack(router), [AppRoute.wtmHome]);
      expect(find.byType(WtmHomeScreen), findsOneWidget);
    });

    testWidgets('saving does not change where Back goes', (tester) async {
      final controller = _ManualTryOnController();
      final (router, _, container) = await generate(tester, using: controller);
      controller.finish();
      await settle(tester);

      await tester.tap(find.text('Save Look'));
      await settle(tester);
      expect(
        container.read(savedLookRecordsProvider.notifier).contains('job1'),
        isTrue,
        reason: 'the look really was filed before Back is exercised',
      );

      router.pop();
      await settle(tester);
      expect(stack(router), [AppRoute.wtmDiscover]);
    });

    testWidgets('a FAILED run keeps its steps — the user is going back', (
      tester,
    ) async {
      final (router, controller, _) = await generate(tester);

      controller.fail();
      await settle(tester);

      expect(
        stack(router),
        [
          AppRoute.wtmDiscover,
          AppRoute.wtmMirrorGarments,
          AppRoute.wtmMirrorMode,
          AppRoute.wtmMirrorGenerating,
        ],
        reason: 'a failure is not a completed flow; retry needs its steps',
      );
    });

    testWidgets('cancelling mid-render returns to the mode step', (
      tester,
    ) async {
      final (router, _, _) = await generate(tester);

      router.pop();
      await settle(tester);

      expect(find.byType(WtmMirrorStep3Screen), findsOneWidget);
      expect(stack(router), [
        AppRoute.wtmDiscover,
        AppRoute.wtmMirrorGarments,
        AppRoute.wtmMirrorMode,
      ]);
    });

    testWidgets('Retry reopens the mode step and drops the spent render', (
      tester,
    ) async {
      final (router, controller, _) = await generate(tester);
      controller.finish();
      await settle(tester);

      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(find.byType(WtmMirrorStep3Screen), findsOneWidget);
      expect(
        stack(router),
        [AppRoute.wtmDiscover, AppRoute.wtmMirrorMode],
        reason: 'retry re-enters the flow; it does not stack onto the render',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Re-entrancy
  // -------------------------------------------------------------------------

  group('a repeated tap is one intention', () {
    testWidgets('pushing the garment step twice leaves one copy', (
      tester,
    ) async {
      final (router, _) = await boot(tester, at: AppRoute.wtmDiscover);

      // The guard the TRY ON entry point uses, exercised directly. It used to
      // compare against `currentConfiguration.uri`, which an imperative push
      // deliberately leaves alone — so it answered "not open" forever and a
      // double tap that landed stacked a second Garments step.
      expect(
        isTopRoute(
          tester.element(find.byType(WtmDiscoverScreen)),
          AppRoute.wtmMirrorGarments,
        ),
        isFalse,
        reason: 'nothing is open yet',
      );

      router.push(AppRoute.wtmMirrorGarments);
      await settle(tester);
      expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);

      expect(
        isTopRoute(
          tester.element(find.byType(WtmMirrorStep2Screen)),
          AppRoute.wtmMirrorGarments,
        ),
        isTrue,
        reason: 'the guard has to SEE the page the first tap installed',
      );
      expect(stack(router), [AppRoute.wtmDiscover, AppRoute.wtmMirrorGarments]);
    });

    testWidgets('the guard matches on path, ignoring query strings', (
      tester,
    ) async {
      final (router, _) = await boot(tester, at: AppRoute.wtmNewsroom);
      router.push('${AppRoute.wtmArticle}?id=a1');
      await settle(tester);

      final context = tester.element(find.byType(WtmArticleScreen));
      expect(isTopRoute(context, AppRoute.wtmArticle), isTrue);
      expect(isTopRoute(context, AppRoute.wtmMirrorGarments), isFalse);
      expect(topRoute(context), '${AppRoute.wtmArticle}?id=a1');
    });
  });

  // -------------------------------------------------------------------------
  // Deep links and auth
  // -------------------------------------------------------------------------

  group('deep links and auth transitions', () {
    testWidgets('a deep link opens one page, on the branch that owns it', (
      tester,
    ) async {
      final (router, _) = await boot(
        tester,
        at: '${AppRoute.wtmArticle}?id=a1',
      );
      expect(stack(router), hasLength(2));
      expect(stack(router).first, AppRoute.wtmNewsroom);
      expect(stack(router).last, startsWith(AppRoute.wtmArticle));
    });

    testWidgets('back from a deep link lands inside the app, not on nothing', (
      tester,
    ) async {
      final (router, _) = await boot(
        tester,
        at: '${AppRoute.wtmArticle}?id=a1',
      );
      expect(router.canPop(), isTrue);
      router.pop();
      await settle(tester);
      expect(find.byType(WtmNewsroomScreen), findsOneWidget);
    });

    testWidgets('signing out leaves every authenticated route behind', (
      tester,
    ) async {
      final (router, container) = await boot(tester, at: AppRoute.wtmProfile);
      router.push(AppRoute.wtmSettings);
      await settle(tester);
      expect(stack(router), [AppRoute.wtmProfile, AppRoute.wtmSettings]);

      container.read(_signedIn.notifier).set(false);
      await settle(tester);

      expect(
        stack(router),
        [AppRoute.wtmAuth],
        reason: 'no authenticated page may survive a sign-out, at any depth',
      );
      expect(router.canPop(), isFalse, reason: 'back cannot re-enter the app');
    });

    testWidgets('signing back in opens the shell, not a stale nested route', (
      tester,
    ) async {
      final (router, container) = await boot(tester, at: AppRoute.wtmCloset);
      container.read(_signedIn.notifier).set(false);
      await settle(tester);
      expect(stack(router), [AppRoute.wtmAuth]);

      container.read(_signedIn.notifier).set(true);
      await settle(tester);

      expect(
        stack(router),
        [AppRoute.wtmHome],
        reason: 'a new session starts at Home, never inside the old one',
      );
      expect(find.byType(WtmHomeScreen), findsOneWidget);
    });

    testWidgets('a render reached cold has somewhere to go back to', (
      tester,
    ) async {
      // No wizard underneath, because there was no wizard. Back must not pop
      // the app away.
      final (router, _) = await boot(
        tester,
        at: AppRoute.wtmMirrorResult,
        controller: _DoneTryOnController.new,
      );
      expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
      expect(stack(router), [AppRoute.wtmMirrorResult]);

      // Nothing underneath, so leaving falls back to the looks gallery rather
      // than popping the app away.
      final context = tester.element(find.byType(WtmMirrorResultScreen));
      leaveCompletedFlow(
        context,
        isStep: isMirrorFlowStep,
        fallback: AppRoute.wtmLooks,
      );
      await settle(tester);
      expect(stack(router), [AppRoute.wtmLooks]);
    });
  });
}
