import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/social/post_image_service.dart';
import 'package:app/features/tryon/models/studio_models.dart';
import 'package:app/features/tryon/sample_garments.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/mirror/wtm_body_source.dart';
import 'package:app/ui/mirror/wtm_mirror_adjust.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_generating.dart';
import 'package:app/ui/mirror/wtm_mirror_result.dart';
import 'package:app/ui/mirror/wtm_mirror_step1.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/ui/mirror/wtm_mirror_step3.dart';
import 'package:app/ui/paywall/wtm_paywall_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P4 gate coverage: the MoodMirror flow on the REAL try-on stack — the outfit
/// draft, credit gating, generate → generating → result, and the local adjust
/// editor. Backend boundaries (photo gallery, credits, the try-on controller,
/// durable upload) are mocked so the flow is deterministic and offline.

// ---- fakes -----------------------------------------------------------------

/// A real, decodable 1×1 transparent PNG (durable-save round trip needs bytes).
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _resultJob = TryOnJob(
  jobId: 'job1',
  status: TryOnStatus.done,
  resultImageUrl: 'https://cdn.test/look.png',
);

/// Controller seeded straight into success — for the Result screen in isolation.
class _DoneTryOnController extends TryOnController {
  @override
  TryOnState build() => const TryOnState.success(_resultJob);
}

/// Controller whose submit just enters the in-flight state (no network, no
/// timer) — for verifying Generate lands on the Generating screen.
class _SubmitTryOnController extends TryOnController {
  @override
  Future<void> start({
    required String personImageUrl,
    required List<String> garmentImageUrls,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
  }) async {
    state = const TryOnState.submitting();
  }
}

class _FakePostImageService implements PostImageService {
  @override
  Future<String> upload(Uint8List bytes) async => 'https://cdn.test/durable.png';

  @override
  Future<Uint8List> downloadImageBytes(String url) async => _png;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Credits _credits({
  required String tier,
  required bool hd,
  required int available,
  int std = 1,
  int hdCost = 4,
}) =>
    Credits(
      balance: available,
      dailyFreeUsed: 0,
      dailyFreeLimit: 0,
      dailyFreeRemaining: 0,
      totalAvailable: available,
      tier: tier,
      hdAllowed: hd,
      stdCost: std,
      hdCost: hdCost,
    );

final _freeNoCredits = _credits(tier: 'free', hd: false, available: 0);
final _proMax = _credits(tier: 'pro_max', hd: true, available: 10);

const _bodyPhoto = TryonPhoto(
  id: 'p1',
  storagePath: 'avatars/u1/p1.jpg',
  signedUrl: 'https://cdn.test/body.png',
  isSelected: true,
);

const _garment = WardrobeItem(
  id: 'w1',
  title: 'Noir silk blouse',
  category: 'tops',
  imageUrl: 'https://cdn.test/w1.png',
);

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

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    List<TryonPhoto> photos = const [],
    List<WardrobeItem> items = const [],
    Credits? credits,
    TryOnController Function()? controller,
    PostImageService? postImage,
    String at = AppRoute.wtmMirror,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      // Riverpod 3 auto-retries failed providers on a backoff timer, which
      // trips the pending-timer check at teardown — disable in tests.
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        tryonPhotosProvider.overrideWith((ref) => photos),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(items),
        ),
        creditsProvider.overrideWith((ref) => credits ?? _freeNoCredits),
        // The top-up sheet (opened from the credits row) reads premium status —
        // pin it so it never reaches for the real entitlement network.
        isPremiumProvider.overrideWithValue(false),
        avatarSignedUrlProvider.overrideWith(
          (ref) async => 'https://cdn.test/body.png',
        ),
        if (controller != null)
          tryOnControllerProvider.overrideWith(controller),
        if (postImage != null)
          postImageServiceProvider.overrideWithValue(postImage),
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
    return container;
  }

  GradientCta ctaByLabel(WidgetTester tester, String label) =>
      tester.widget<GradientCta>(find.byWidgetPredicate(
        (w) => w is GradientCta && w.label == label,
      ));

  // ---- flow notifier (pure) ------------------------------------------------

  group('WtmMirrorFlow', () {
    test('toggleItem adds then removes; imageless item is ignored', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final flow = container.read(wtmMirrorFlowProvider.notifier);

      expect(flow.toggleItem(_garment), isTrue);
      expect(container.read(wtmMirrorFlowProvider).layers.length, 1);
      expect(flow.toggleItem(_garment), isTrue); // toggle off
      expect(container.read(wtmMirrorFlowProvider).layers, isEmpty);

      expect(flow.toggleItem(const WardrobeItem(id: 'bare')), isFalse);
      expect(container.read(wtmMirrorFlowProvider).layers, isEmpty);
    });

    test('the outfit stack caps at maxGarments and refuses further adds', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final flow = container.read(wtmMirrorFlowProvider.notifier);

      // One past the ceiling: the first maxGarments land, the extra is refused.
      final results = [
        for (var i = 0; i <= WtmMirrorFlow.maxGarments; i++)
          flow.toggleItem(WardrobeItem(id: 'g$i', imageUrl: 'https://x/g$i')),
      ];
      expect(results.take(WtmMirrorFlow.maxGarments), everyElement(isTrue));
      expect(results.last, isFalse);
      expect(
        container.read(wtmMirrorFlowProvider).layers.length,
        WtmMirrorFlow.maxGarments,
      );

      // A brand-new piece can't sneak past the ceiling either.
      expect(
        flow.toggleItem(const WardrobeItem(id: 'x', imageUrl: 'https://x/x')),
        isFalse,
      );
      expect(
        container.read(wtmMirrorFlowProvider).layers.length,
        WtmMirrorFlow.maxGarments,
      );
    });

    test('setLayers seeds the stack and clamps to the ceiling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final flow = container.read(wtmMirrorFlowProvider.notifier);

      flow.setLayers([
        for (var i = 0; i < 9; i++)
          TryOnLayer.fromSource(imageUrl: 'https://x/$i', zIndex: i),
      ]);
      expect(
        container.read(wtmMirrorFlowProvider).layers.length,
        WtmMirrorFlow.maxGarments,
      );
    });

    test('mode cost + plan gating read the server credit model', () {
      expect(WtmMirrorMode.twoD.cost(_freeNoCredits), 0);
      expect(WtmMirrorMode.aiCouture.cost(_freeNoCredits), 1);
      expect(WtmMirrorMode.fullLook.cost(_freeNoCredits), 4);

      // Full Look (HD) is Pro-Max only, regardless of balance.
      expect(WtmMirrorMode.fullLook.allowed(_freeNoCredits), isFalse);
      expect(WtmMirrorMode.fullLook.allowed(_proMax), isTrue);
      expect(WtmMirrorMode.aiCouture.allowed(_freeNoCredits), isTrue);
    });
  });

  // ---- adjustments (pure) --------------------------------------------------

  group('WtmAdjustments', () {
    test('neutral by default; any change breaks neutrality', () {
      const neutral = WtmAdjustments();
      expect(neutral.isNeutral, isTrue);
      expect(neutral.copyWith(brightness: 0.7).isNeutral, isFalse);
      expect(neutral.copyWith(shadows: 0.2).isNeutral, isFalse);
    });

    test('builds a color filter for both neutral and edited states', () {
      expect(const WtmAdjustments().toColorFilter(), isA<ColorFilter>());
      expect(
        const WtmAdjustments(contrast: 0.9, saturation: 0.1).toColorFilter(),
        isA<ColorFilter>(),
      );
    });
  });

  // ---- screens -------------------------------------------------------------

  testWidgets('Step 1 with a body photo continues to garments', (tester) async {
    await boot(tester, photos: const [_bodyPhoto]);
    expect(find.byType(WtmMirrorStep1Screen), findsOneWidget);
    expect(find.text('Continue · Add Garments'), findsOneWidget);

    await tapAndSettle(tester, find.text('Continue · Add Garments'));
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
  });

  testWidgets('Step 1 without a photo invites a body photo', (tester) async {
    await boot(tester, photos: const []);
    expect(find.byType(WtmMirrorStep1Screen), findsOneWidget);
    expect(find.byType(WtmFigure), findsWidgets);
    expect(find.text('Upload Photo'), findsOneWidget);
    expect(find.text('Select from Gallery'), findsOneWidget);
  });

  testWidgets('Step 1 with a chosen mannequin body continues to garments (Fix 5)',
      (tester) async {
    // No personal photo, but picking the mannequin gives MoodMirror a body.
    final container = await boot(tester, photos: const []);
    expect(find.text('Upload Photo'), findsOneWidget);

    container.read(wtmBodyChoiceProvider.notifier).useMannequin();
    await settle(tester);
    expect(find.text('Continue · Add Garments'), findsOneWidget);

    await tapAndSettle(tester, find.text('Continue · Add Garments'));
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
  });

  testWidgets('Step 2 selecting a garment enables Choose Mode', (tester) async {
    await boot(tester, items: const [_garment], at: AppRoute.wtmMirrorGarments);
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
    // Nothing picked yet → the CTA is disabled.
    expect(ctaByLabel(tester, 'Next · Choose Mode').onPressed, isNull);

    await tapAndSettle(tester, find.byType(FabricTile).first);
    // Picked → the CTA now carries the count and advances to mode selection.
    await tapAndSettle(tester, find.textContaining('Next · Choose Mode'));
    expect(find.byType(WtmMirrorStep3Screen), findsOneWidget);
  });

  testWidgets('Step 3 Full Look on a non-Pro-Max plan opens the paywall', (
    tester,
  ) async {
    await boot(tester, credits: _freeNoCredits, at: AppRoute.wtmMirrorMode);
    expect(find.byType(WtmMirrorStep3Screen), findsOneWidget);

    await tapAndSettle(tester, find.text('Full Look'));
    expect(find.byType(WtmPaywallScreen), findsOneWidget);
  });

  testWidgets('Step 3 insufficient credits disables Generate and offers top-up',
      (tester) async {
    final container = await boot(
      tester,
      credits: _freeNoCredits,
      at: AppRoute.wtmMirrorMode,
    );
    container.read(wtmMirrorFlowProvider.notifier).toggleSample(
          sampleGarments.first,
        );
    await settle(tester);

    await tapAndSettle(tester, find.text('AI Couture Try-On'));
    // Zero credits → inline warning + the Generate CTA is disabled.
    expect(find.text('Not enough credits for this mode.'), findsOneWidget);
    expect(ctaByLabel(tester, 'Generate Look').onPressed, isNull);

    // The credits row routes to the top-up sheet.
    await tapAndSettle(tester, find.text('YOUR CREDITS'));
    expect(find.text('CURRENT BALANCE'), findsOneWidget);
  });

  testWidgets('Step 3 Generate (AI) lands on the Generating screen', (
    tester,
  ) async {
    final container = await boot(
      tester,
      credits: _proMax,
      controller: _SubmitTryOnController.new,
      at: AppRoute.wtmMirrorMode,
    );
    container.read(wtmMirrorFlowProvider.notifier).toggleSample(
          sampleGarments.first,
        );
    await settle(tester);

    await tapAndSettle(tester, find.text('AI Couture Try-On'));
    expect(ctaByLabel(tester, 'Generate Look').onPressed, isNotNull);

    await tapAndSettle(tester, find.text('Generate Look'));
    expect(find.byType(WtmMirrorGeneratingScreen), findsOneWidget);
    expect(find.byType(TheOrb), findsWidgets);
    // The controller received a submit (no failure branch shown).
    expect(container.read(tryOnControllerProvider), isA<TryOnSubmitting>());
  });

  testWidgets('Result renders the action bar and Save records the look', (
    tester,
  ) async {
    final container = await boot(
      tester,
      credits: _proMax,
      controller: _DoneTryOnController.new,
      postImage: _FakePostImageService(),
      at: AppRoute.wtmMirrorResult,
    );
    expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
    expect(find.text('Save Look'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    await tapAndSettle(tester, find.text('Save Look'));
    // Durable save recorded the look so it survives to the Looks gallery.
    expect(
      container.read(savedLookRecordsProvider.notifier).contains('job1'),
      isTrue,
    );
  });

  testWidgets('Result → Adjust opens the editor and Done returns', (
    tester,
  ) async {
    await boot(
      tester,
      credits: _proMax,
      controller: _DoneTryOnController.new,
      at: AppRoute.wtmMirrorResult,
    );

    await tapAndSettle(tester, find.text('Adjust'));
    expect(find.byType(WtmMirrorAdjustScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Done'));
    expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
  });
}
