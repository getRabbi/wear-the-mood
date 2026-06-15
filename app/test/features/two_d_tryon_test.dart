import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
import 'package:app/features/tryon/two_d/two_d_editor_screen.dart';
import 'package:app/features/tryon/two_d/two_d_models.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

/// Records whether the AI endpoint (`createTryOn`) was ever called.
class _RecordingTryOnRepository extends TryOnRepository {
  _RecordingTryOnRepository() : super(Dio());

  int createCalls = 0;

  @override
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    String? wardrobeItemId,
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
      ),
    ),
    avatarSignedUrlProvider.overrideWith((ref) async => null),
    wardrobeItemsProvider.overrideWith((ref) async => _closet),
    isPremiumProvider.overrideWithValue(premium),
    tryOnRepositoryProvider.overrideWithValue(repo),
    tryOnPollIntervalProvider.overrideWithValue(Duration.zero),
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
    expect(find.text('Generate 2D preview'), findsOneWidget);
    expect(find.text('Generate AI look'), findsNothing);

    await tester.tap(find.text('AI Realistic Try-On')); // the AI mode card
    await tester.pump();
    expect(find.text('Generate AI look'), findsOneWidget);
    expect(find.text('Generate 2D preview'), findsNothing);

    await tester.tap(find.text('2D Try-On')); // back to 2D
    await tester.pump();
    expect(find.text('Generate 2D preview'), findsOneWidget);
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

    await tester.tap(find.text('Generate 2D preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The AI endpoint was never hit (so no AI/premium credit is spent), and the
    // local 2D editor opened instead.
    expect(repo.createCalls, 0);
    expect(find.text('Adjust your look'), findsOneWidget);
  });

  testWidgets('free user in AI mode sees the upgrade sheet, no AI call', (
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
    await tester.tap(find.text('Generate AI look'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet animates in

    expect(repo.createCalls, 0);
    expect(find.text('Unlock AI Realistic Try-On'), findsOneWidget);
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
