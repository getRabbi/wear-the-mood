import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_preselect.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

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
      // The garment picker is the user's wardrobe.
      wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(closet)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  // The "Generate your look" CTA in the sticky bottom bar.
  PrimaryButton cta(WidgetTester tester) => tester.widget<PrimaryButton>(
    find.ancestor(
      of: find.text('Build 2D outfit'),
      matching: find.byType(PrimaryButton),
    ),
  );

  testWidgets('picks a garment from the wardrobe; CTA enables on select', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Build 2D outfit'), findsOneWidget);
    // The two closet pieces show in the clothing picker.
    expect(find.byType(SmartImageCard), findsNWidgets(2));
    expect(cta(tester).onPressed, isNull);

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });

  testWidgets('empty wardrobe shows an add-clothes prompt, CTA disabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(closet: const []));
    await tester.pump();

    expect(find.text('Add clothes'), findsOneWidget);
    expect(cta(tester).onPressed, isNull);
  });

  // ── progress indicator (Task 2) ───────────────────────────────────────────

  Widget wrapState(TryOnState state) => ProviderScope(
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
      wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(_closet)),
      tryOnControllerProvider.overrideWith(() => _StubController(state)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  TryOnJob job(TryOnStatus status) => TryOnJob(jobId: 'j1', status: status);

  testWidgets('queued job shows "Preparing" stage + a determinate bar', (
    tester,
  ) async {
    await tester.pumpWidget(wrapState(TryOnState.polling(job(TryOnStatus.queued))));
    await tester.pump();

    expect(find.text('Preparing your photo…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose the periodic ticker
  });

  testWidgets('processing job shows "Generating" stage', (tester) async {
    await tester.pumpWidget(
      wrapState(TryOnState.polling(job(TryOnStatus.processing))),
    );
    await tester.pump();

    expect(find.text('Generating your look…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reassures the user after a long (>30s) wait', (tester) async {
    await tester.pumpWidget(
      wrapState(TryOnState.polling(job(TryOnStatus.processing))),
    );
    await tester.pump();
    expect(find.textContaining('high-quality looks'), findsNothing);

    await tester.pump(const Duration(seconds: 31)); // 31 ticks elapse
    expect(find.textContaining('high-quality looks'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // ── "Try on" from the closet clears a stale result/failure (Issue 5) ───────

  testWidgets('a preselect clears a stale failure and returns to the picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Land on a leftover failure from a previous run.
    await tester.pumpWidget(
      wrapState(const TryOnState.failure(message: 'Something went wrong.')),
    );
    await tester.pump();
    expect(find.text('Something went wrong.'), findsOneWidget);

    // Simulate tapping "Try on" on a closet piece (seeds the preselect).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TryOnScreen)),
    );
    container.read(tryOnPreselectProvider.notifier).setItem(_closet.first);
    await tester.pump(); // run the listener (reset + seed)
    await tester.pump(const Duration(milliseconds: 400)); // finish the switch

    // Stale failure is gone; we're back on the picker with the piece staged.
    expect(find.text('Something went wrong.'), findsNothing);
    expect(find.text('Build 2D outfit'), findsOneWidget);
  });
}

/// Pins the controller to a fixed state so the progress UI can be rendered
/// without driving a real (network) try-on.
class _StubController extends TryOnController {
  _StubController(this._state);

  final TryOnState _state;

  @override
  TryOnState build() => _state;
}

const _closet = [
  WardrobeItem(
    id: 'w1',
    title: 'White tee',
    imageUrl: 'https://x/1',
    cutoutStatus: 'done',
  ),
  WardrobeItem(
    id: 'w2',
    title: 'Black jeans',
    imageUrl: 'https://x/2',
    cutoutStatus: 'done',
  ),
];
