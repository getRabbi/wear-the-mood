import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/paywall/billing_providers.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_mode.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/features/tryon/two_d/fit_memory.dart';
import 'package:app/features/tryon/two_d/two_d_editor_screen.dart';
import 'package:app/features/tryon/two_d/two_d_models.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

/// Records whether the AI endpoint (`createTryOn`) was ever called.
class _RecordingTryOnRepository extends TryOnRepository {
  _RecordingTryOnRepository() : super(Dio());

  int createCalls = 0;

  @override
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    List<String>? garmentImageUrls,
    String? wardrobeItemId,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    String? idempotencyKey,
  }) async {
    createCalls++;
    // Return a terminal job so the controller doesn't poll.
    return const TryOnJob(
      jobId: 'j',
      status: TryOnStatus.done,
      resultImageUrl: 'r.jpg',
    );
  }

  @override
  Future<TryOnJob> getJob(String jobId) async => const TryOnJob(
    jobId: 'j',
    status: TryOnStatus.done,
    resultImageUrl: 'r.jpg',
  );

  @override
  Future<List<TryonResult>> listResults() async => const [];
}

/// In-memory fit-memory store for tests (no secure-storage channel).
class _MemFitStore implements FitMemoryStore {
  String? _v;
  @override
  Future<String?> read() async => _v;
  @override
  Future<void> write(String value) async => _v = value;
}

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

  // Inferred List<Override> (avoid naming the Override type directly).
  os({
    required bool canSpend,
    required bool premium,
    required TryOnRepository repo,
  }) => [
    creditsProvider.overrideWith(
      (ref) async => Credits(
        balance: 0,
        dailyFreeUsed: canSpend ? 0 : 5,
        dailyFreeLimit: 5,
        dailyFreeRemaining: canSpend ? 5 : 0,
        totalAvailable: canSpend ? 5 : 0,
      ),
    ),
    avatarSignedUrlProvider.overrideWith((ref) async => null),
    wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(_closet)),
    isPremiumProvider.overrideWithValue(premium),
    tryOnRepositoryProvider.overrideWithValue(repo),
    tryOnPollIntervalProvider.overrideWithValue(Duration.zero),
    // Fit memory (Phase 4): in-memory store + fixed user so the 2D editor never
    // touches the platform secure-storage / Supabase channels under test.
    authUserIdProvider.overrideWithValue('u_test'),
    fitMemoryServiceProvider.overrideWithValue(FitMemoryService(_MemFitStore())),
  ];

  // Plain harness (for flows that don't navigate).
  Widget plain({
    required bool canSpend,
    required bool premium,
    required TryOnRepository repo,
  }) => ProviderScope(
    overrides: os(canSpend: canSpend, premium: premium, repo: repo),
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  // Plain harness with an explicit Credits state (for the HD gating cases).
  Widget plainWith(Credits credits, {required TryOnRepository repo}) =>
      ProviderScope(
        overrides: [
          creditsProvider.overrideWith((ref) async => credits),
          avatarSignedUrlProvider.overrideWith((ref) async => null),
          wardrobeItemsProvider.overrideWith(
            () => FakeWardrobeItemsNotifier(_closet),
          ),
          isPremiumProvider.overrideWithValue(credits.isSubscriber),
          tryOnRepositoryProvider.overrideWithValue(repo),
          tryOnPollIntervalProvider.overrideWithValue(Duration.zero),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TryOnScreen(),
        ),
      );

  // Router harness (the 2D Generate pushes the editor route).
  Widget routed({
    required bool canSpend,
    required bool premium,
    required TryOnRepository repo,
  }) {
    final router = GoRouter(
      initialLocation: AppRoute.tryon,
      routes: [
        GoRoute(
          path: AppRoute.tryon,
          builder: (_, _) => const TryOnScreen(),
        ),
        GoRoute(
          path: AppRoute.tryon2dEditor,
          builder: (_, state) {
            final e = state.extra;
            return e is TwoDEditorArgs
                ? TwoDEditorScreen(args: e)
                : const TryOnScreen();
          },
        ),
        GoRoute(
          path: AppRoute.paywall,
          builder: (_, _) => const Scaffold(body: Text('paywall')),
        ),
      ],
    );
    return ProviderScope(
      overrides: os(canSpend: canSpend, premium: premium, repo: repo),
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  // ───────────────────────────────────────────────── unit ──────────────────

  test('TwoDResult stores mode "2d"', () {
    final r = TwoDResult(bytes: Uint8List.fromList([1, 2, 3]));
    expect(r.mode, '2d');
  });

  test('TryOnMode ids and labels are distinct', () {
    expect(TryOnMode.twoD.id, '2d');
    expect(TryOnMode.aiRealistic.id, 'ai_realistic');
    expect(TryOnMode.twoD.isTwoD, isTrue);
    expect(TryOnMode.aiRealistic.isAi, isTrue);
  });

  test('garmentPlacement maps categories to sensible positions', () {
    expect(garmentPlacement('shoes').verticalCenter, greaterThan(0.8));
    expect(garmentPlacement('sunglasses').verticalCenter, lessThan(0.3));
    final pants = garmentPlacement('pants').verticalCenter;
    final top = garmentPlacement('top').verticalCenter;
    expect(pants, greaterThan(top)); // pants sit lower than tops
  });

  test('garmentPlacement places accessories near the right body area', () {
    // Hijab/scarf + hats sit high (head); a watch sits low (wrist); a necklace
    // sits on the upper chest — none default to the torso "top" placement.
    final top = garmentPlacement('top').verticalCenter;
    expect(garmentPlacement('hijab').verticalCenter, lessThan(0.25));
    expect(garmentPlacement('hat').verticalCenter, lessThan(0.2));
    expect(garmentPlacement('watch').verticalCenter, greaterThan(0.5));
    expect(garmentPlacement('necklace').verticalCenter, lessThan(top));
    // A small accessory is narrower than a top.
    expect(
      garmentPlacement('watch').widthFactor,
      lessThan(garmentPlacement('top').widthFactor),
    );
    // Capri pants must NOT be mistaken for a hat (no 'cap' keyword collision).
    expect(garmentPlacement('capri').verticalCenter, greaterThan(0.5));
  });

  test('garmentZRank stacks an outfit back→front sensibly (Capability 3)', () {
    // bottoms behind the top; outerwear over the top; accessories in front.
    expect(garmentZRank('jeans'), lessThan(garmentZRank('white top')));
    expect(garmentZRank('white top'), lessThan(garmentZRank('denim jacket')));
    expect(garmentZRank('denim jacket'), lessThan(garmentZRank('necklace')));
    expect(garmentZRank('necklace'), 5); // accessories are front-most
  });

  // ─────────────────────────────────────────────── widget ──────────────────

  testWidgets('switching mode changes the Generate button text', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      plain(canSpend: true, premium: true, repo: _RecordingTryOnRepository()),
    );
    await tester.pump();

    // Default is free 2D.
    expect(find.text('Build 2D outfit'), findsOneWidget);
    expect(find.text('Generate AI look'), findsNothing);

    await tester.tap(find.text('AI Realistic Try-On')); // the AI mode card
    await tester.pump();
    expect(find.text('Generate AI look'), findsOneWidget);
    expect(find.text('Build 2D outfit'), findsNothing);

    await tester.tap(find.text('2D Try-On')); // back to 2D
    await tester.pump();
    expect(find.text('Build 2D outfit'), findsOneWidget);
  });

  testWidgets('2D generate does NOT call the AI endpoint and opens the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      routed(canSpend: false, premium: false, repo: repo),
    );
    await tester.pump();

    // Pick a garment (default mode is 2D).
    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();

    await tester.tap(find.text('Build 2D outfit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The AI endpoint was never hit (so no AI/premium credit is spent), and the
    // local 2D editor opened instead.
    expect(repo.createCalls, 0);
    expect(find.text('Adjust your look'), findsOneWidget);
  });

  testWidgets(
    '2D editor is full-screen (no app bottom nav) and offers Reset all',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingTryOnRepository();
      await tester.pumpWidget(routed(canSpend: false, premium: false, repo: repo));
      await tester.pump();

      await tester.tap(find.byType(SmartImageCard).first);
      await tester.pump();
      await tester.tap(find.text('Build 2D outfit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The editor is a full-screen route: the app's floating bottom nav is NOT
      // part of its tree, so it can never sit over the canvas or the export.
      expect(find.text('Adjust your look'), findsOneWidget);
      expect(find.byType(FloatingBottomNav), findsNothing);
      // Phase 7: a "Reset all" action is available.
      expect(find.byTooltip('Reset all'), findsOneWidget);
    },
  );

  testWidgets('free user with no credits in AI mode is blocked from generating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plain(canSpend: false, premium: false, repo: repo),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();

    // Out of credits: Generate is replaced by an upgrade CTA, so there is no way
    // to spend — the AI endpoint can never be reached.
    expect(find.text('Generate AI look'), findsNothing);
    expect(find.text('See Premium'), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('free user toggling HD sees the Pro/Pro Max upsell, not a charge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plainWith(
        const Credits(
          balance: 0,
          dailyFreeUsed: 0,
          dailyFreeLimit: 3,
          dailyFreeRemaining: 3,
          totalAvailable: 3, // could afford standard, but not HD-eligible
          tier: 'free',
        ),
        repo: repo,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();
    await tester.tap(find.byType(Switch)); // turn HD on
    await tester.pump();

    // HD is Pro Max only: a free user is told to upgrade, never charged.
    expect(find.text('Upgrade to Pro Max for HD.'), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('Pro user (HD not allowed) toggling HD sees the Pro Max upsell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plainWith(
        const Credits(
          balance: 10,
          dailyFreeUsed: 5,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 0,
          totalAvailable: 10, // plenty of credits, but Pro can't do HD
          tier: 'pro',
          hdAllowed: false, // Pro Max only (server-enforced)
        ),
        repo: repo,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();
    await tester.tap(find.byType(Switch)); // turn HD on
    await tester.pump();

    // Pro is not HD-eligible → shown the Pro Max upsell copy.
    expect(find.text('Upgrade to Pro Max for HD.'), findsOneWidget);

    // Attempting to generate routes to the HD-locked upsell sheet and NEVER calls
    // the AI endpoint (a Pro user can't run HD, so nothing is charged).
    await tester.tap(find.text('Generate AI look'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HD is a Pro Max feature'), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('subscriber with too few credits for HD sees Top Up, no AI call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plainWith(
        const Credits(
          balance: 1,
          dailyFreeUsed: 5,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 0,
          totalAvailable: 1, // a Pro Max user with only 1 credit
          tier: 'pro_max',
          hdAllowed: true,
        ),
        repo: repo,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();
    await tester.tap(find.byType(Switch)); // turn HD on (4 credits)
    await tester.pump();

    // Eligible for HD but short on credits: clear message + Top Up, no generate.
    expect(find.text('You need 4 credits for HD.'), findsOneWidget);
    expect(find.text('Top Up'), findsOneWidget);
    expect(find.text('Generate AI look'), findsNothing);
    expect(repo.createCalls, 0);
  });

  testWidgets('subscriber with enough credits can run HD', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plainWith(
        const Credits(
          balance: 4,
          dailyFreeUsed: 5,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 0,
          totalAvailable: 4,
          tier: 'pro_max',
          hdAllowed: true,
        ),
        repo: repo,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();
    await tester.tap(find.byType(Switch)); // turn HD on (4 credits, affordable)
    await tester.pump();

    // Affordable HD: the Generate button is available (no upsell/top-up).
    expect(find.text('Generate AI look'), findsOneWidget);
    expect(find.text('Top Up'), findsNothing);
  });

  testWidgets('premium user in AI mode calls the AI endpoint', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _RecordingTryOnRepository();
    await tester.pumpWidget(
      plain(canSpend: true, premium: true, repo: repo),
    );
    await tester.pump();

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();
    await tester.tap(find.text('AI Realistic Try-On'));
    await tester.pump();
    await tester.tap(find.text('Generate AI look'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(repo.createCalls, 1);
  });
}
