import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/stylist_suggestion.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/stylist/stylist_controller.dart';
import 'package:app/features/stylist/stylist_state.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/home/wtm_mood.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/ui/stylist/wtm_stylist_look_screen.dart';
import 'package:app/ui/stylist/wtm_stylist_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P5 gate coverage: the AI Stylist on the real stylist backend, and the
/// Suggest → "Try This On" handoff that pre-fills MoodMirror Step 2.

class _FakeMoodRepo implements WtmMoodRepository {
  @override
  Future<double?> read() async => null;
  @override
  Future<void> write(double v) async {}
}

/// Stylist controller seeded to a fixed state; styleMe is a no-op so the screen
/// is deterministic (no network, no auto-query surprises).
class _SeededStylist extends StylistController {
  _SeededStylist(this._seed);
  final StylistState _seed;
  @override
  StylistState build() => _seed;
  @override
  Future<void> styleMe({String? occasion, String? note}) async {}
}

const _pieces = [
  WardrobeItem(
      id: 'w1', title: 'Noir blouse', category: 'tops',
      imageUrl: 'https://cdn.test/w1.png'),
  WardrobeItem(
      id: 'w2', title: 'Wide trousers', category: 'bottoms',
      imageUrl: 'https://cdn.test/w2.png'),
];

StylistState _success(List<WardrobeItem> items) => StylistState.success(
      StylistSuggestion(
        title: 'Moonlit Confidence',
        rationale: 'Silk against structure — soft romance, modern edge.',
        items: items,
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

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
    required StylistState seed,
    List<WardrobeItem> items = _pieces,
    String at = AppRoute.wtmStylist,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        wtmMoodRepositoryProvider.overrideWithValue(_FakeMoodRepo()),
        stylistControllerProvider.overrideWith(() => _SeededStylist(seed)),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(items),
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
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return container;
  }

  testWidgets('Stylist renders a LookCard with Try This On + Shuffle', (
    tester,
  ) async {
    await boot(tester, seed: _success(_pieces));
    expect(find.byType(WtmStylistScreen), findsOneWidget);
    expect(find.text('Try This On'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.textContaining('Moonlit'), findsWidgets);
  });

  testWidgets('GATE: Stylist Try This On lands in Step 2 pre-filled', (
    tester,
  ) async {
    final container = await boot(tester, seed: _success(_pieces));

    await tapAndSettle(tester, find.text('Try This On'));

    // The handoff opened Step 2 and pre-filled the outfit draft with the
    // suggestion's real pieces.
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
    expect(container.read(wtmMirrorFlowProvider).layers.length, 2);
  });

  testWidgets('GATE: look detail Try This On pre-fills Step 2', (tester) async {
    final container =
        await boot(tester, seed: _success(_pieces), at: AppRoute.wtmStylistLook);
    expect(find.byType(WtmStylistLookScreen), findsOneWidget);
    expect(find.textContaining('AI insight'), findsOneWidget);

    await tapAndSettle(tester, find.text('Try This On'));
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
    expect(container.read(wtmMirrorFlowProvider).layers.length, 2);
  });

  testWidgets('Stylist with an empty closet invites Add Garment', (
    tester,
  ) async {
    await boot(tester, seed: _success(const []), items: const []);
    expect(find.byType(WtmEmptyState), findsOneWidget);
    expect(find.text('Add a garment'), findsOneWidget);
  });

  testWidgets('Stylist failure offers retry', (tester) async {
    await boot(
      tester,
      seed: const StylistState.failure(message: 'The stylist is offline.'),
    );
    expect(find.byType(WtmErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
