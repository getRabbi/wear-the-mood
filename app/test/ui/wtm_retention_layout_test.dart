import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/monetization.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/planner.dart';
import 'package:app/data/models/style_memory.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/monetization_repository.dart';
import 'package:app/data/repositories/planner_repository.dart';
import 'package:app/data/repositories/style_memory_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/home/wtm_home_personalized.dart';
import 'package:app/ui/mirror/wtm_result_feedback.dart';
import 'package:app/ui/paywall/wtm_render_gate.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Device-QA conditions, run where they can actually be asserted.
///
/// The three surfaces flagged for hands-on inspection — the rejection-reason
/// sheet, the event date picker and the personalized Home block — all fail in
/// the same three situations, and all three are reproducible here: **the
/// smallest supported phone (320dp), 2.0× text, and a backend that is slow,
/// broken or absent.**
///
/// A widget test cannot replace a human looking at a screen, but it catches the
/// class of defect that a human on ONE phone in ONE font size reliably misses,
/// and it keeps catching it forever.
const _small = Size(320 * 3, 640 * 3); // 320×640dp — the narrowest we support
const _pixelRatio = 3.0;

const _closet = [
  WardrobeItem(id: 'w1', title: 'Silk shirt', cutoutUrl: 'https://x/1.png'),
];

class _SlowPlanner implements PlannerRepository {
  _SlowPlanner({this.delay = const Duration(seconds: 5), this.fail = false});

  final Duration delay;
  final bool fail;

  Future<T> _slow<T>(T value) async {
    await Future<void>.delayed(delay);
    if (fail) throw Exception('network');
    return value;
  }

  @override
  Future<MoodPlan?> createMoodPlan({
    required PlannerMood mood,
    PlannerOccasion? occasion,
  }) => _slow(null);

  @override
  Future<MoodPlan?> latestMoodPlan() => _slow(null);

  @override
  Future<StyleEventList> listEvents({bool includePast = false}) =>
      _slow(const StyleEventList());

  @override
  Future<StyleEvent?> createEvent({
    required String name,
    required DateTime eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool reminderOptIn = false,
  }) => _slow(null);

  @override
  Future<StyleEvent?> updateEvent({
    required String id,
    String? name,
    DateTime? eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool? reminderOptIn,
  }) => _slow(null);

  @override
  Future<void> deleteEvent(String id) => _slow(null);
}

class _FailingStyleMemory implements StyleMemoryRepository {
  @override
  Future<StyleMemoryProfile> getProfile() async => throw Exception('offline');

  @override
  Future<StyleMemorySignalResult?> recordSignal({
    required String signalType,
    String? entityType,
    String? entityId,
    String? value,
    String? mood,
    String? occasion,
    RejectionReason? reason,
    String? dedupeKey,
  }) async => throw Exception('offline');

  @override
  Future<StyleMemoryProfile> correct({
    required String facet,
    required String value,
    bool remove = false,
  }) async => throw Exception('offline');

  @override
  Future<StyleMemoryProfile> setPersonalization({
    required bool enabled,
  }) async => throw Exception('offline');

  @override
  Future<int> reset() async => throw Exception('offline');

  @override
  Future<TryOnFeedbackResult?> submitFeedback({
    required String resultId,
    required bool kept,
    RejectionReason? reason,
    String? note,
  }) async => throw Exception('offline');
}

class _FakeMonetization implements MonetizationRepository {
  _FakeMonetization(this.config);

  final MonetizationConfig config;

  @override
  Future<MonetizationConfig> getConfig() async => config;

  @override
  Future<void> recordEvent({
    required MonetizationSurface surface,
    required MonetizationAction action,
    bool interruptive = false,
    Map<String, String>? context,
  }) async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  /// Pump one widget under a given viewport and text scale.
  ///
  /// The text scale goes through the platform dispatcher, not a `MediaQuery`
  /// wrapper: `MediaQueryData(textScaler: …)` REPLACES the data and would zero
  /// the viewport, which silently sends every responsive branch down its narrow
  /// path and makes a breakpoint test pass without testing the breakpoint.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = _small,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
    // Deliberately not `List<Override>`: `Override` is sealed and not exported
    // for naming, so the repo's idiom is to let the list type be inferred at
    // the call site (see test/features/two_d_tryon_test.dart).
    List<dynamic> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: overrides.cast(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: brightness),
          // A ListView, because that is what WtmPage puts its children in.
          // Pumping into a bare Scaffold body would impose a hard height bound
          // production never applies, and would report an overflow that no
          // user can ever see.
          home: Scaffold(body: ListView(children: [child])),
        ),
      ),
    );
    await settle(tester);
  }

  /// Every tappable in the tree meets the 48dp floor (§41).
  void expectTapTargets(WidgetTester tester, Finder finder) {
    for (final element in finder.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(
        size.height,
        greaterThanOrEqualTo(44.0),
        reason: 'tap target too short: ${element.widget.runtimeType} $size',
      );
    }
  }

  // ── A. the rejection-reason sheet ──────────────────────────────────────────

  group('A. reason sheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      double textScale = 1.0,
      Size size = _small,
    }) async {
      await pump(
        tester,
        const WtmResultFeedback(resultId: 'r1'),
        size: size,
        textScale: textScale,
        overrides: [
          enabledFeatureFlagsProvider.overrideWith(
            (ref) => {FeatureFlags.styleMemoryFeedback},
          ),
          styleMemoryRepositoryProvider.overrideWithValue(
            _FailingStyleMemory(),
          ),
        ],
      );
      await tester.tap(find.text('Not me'));
      await settle(tester);
    }

    testWidgets('opens without overflow on the narrowest phone', (
      tester,
    ) async {
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Not my style'), findsOneWidget);
    });

    testWidgets('survives 2.0x text without overflowing', (tester) async {
      await openSheet(tester, textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every reason stays reachable at 2.0x text', (tester) async {
      // The failure this guards: seven rows in a min-sized Column on a 640dp
      // screen at double text. If the sheet cannot scroll, the last reasons are
      // simply unreachable and the user can never say "wrong colour".
      await openSheet(tester, textScale: 2.0);
      for (final label in [
        'Doesn’t look like me',
        'The clothing looks wrong',
        'Proportions look off',
        'Not my style',
        'Wrong colour for me',
        'Wrong for the occasion',
        'Something else',
      ]) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: 'missing reason: $label');
        await tester.ensureVisible(finder);
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('reason rows meet the 48dp tap floor', (tester) async {
      await openSheet(tester);
      expectTapTargets(tester, find.byType(InkWell));
    });

    testWidgets('a failed submit never leaves the row stuck busy', (
      tester,
    ) async {
      // The repository throws. The user must get their buttons back, not a
      // permanently disabled row on top of their render.
      await pump(
        tester,
        const WtmResultFeedback(resultId: 'r1'),
        overrides: [
          enabledFeatureFlagsProvider.overrideWith(
            (ref) => {FeatureFlags.styleMemoryFeedback},
          ),
          styleMemoryRepositoryProvider.overrideWithValue(
            _FailingStyleMemory(),
          ),
        ],
      );
      await tester.tap(find.text('Keep it'));
      await settle(tester);
      // Still "Keep it", never "Kept": a verdict that failed to reach the
      // server must not be shown as recorded, and the user must be able to
      // try again rather than be left with a dead button on their render.
      expect(find.text('Keep it'), findsOneWidget);
      expect(find.text('Kept'), findsNothing);
      // Tapping again is still possible — proof the row did not latch busy.
      await tester.tap(find.text('Keep it'));
      await settle(tester);
      expect(find.text('Keep it'), findsOneWidget);
    });
  });

  // ── C. personalized Home first paint ──────────────────────────────────────

  group('C. personalized Home', () {
    Future<ProviderContainer> bootHome(
      WidgetTester tester, {
      required Set<String> flags,
      PlannerRepository? planner,
      StyleMemoryRepository? memory,
      Size size = _small,
      double textScale = 1.0,
      int settleMs = 900,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = _pixelRatio;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          authUserIdProvider.overrideWithValue('u1'),
          enabledFeatureFlagsProvider.overrideWith((ref) => flags),
          plannerRepositoryProvider.overrideWithValue(
            planner ?? _SlowPlanner(),
          ),
          styleMemoryRepositoryProvider.overrideWithValue(
            memory ?? _FailingStyleMemory(),
          ),
          wardrobeItemsProvider.overrideWith(
            () => FakeWardrobeItemsNotifier(_closet),
          ),
          outfitsProvider.overrideWith((ref) async => const <Outfit>[]),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await settle(tester, settleMs);
      container.read(goRouterProvider).go(AppRoute.wtmHome);
      await settle(tester, settleMs);
      // Drain anything the fake still owes, so a deliberately slow repository
      // cannot fail the test on a pending timer it was asked to create.
      addTearDown(() async => tester.pump(const Duration(seconds: 1)));
      return container;
    }

    /// Home is a lazy ListView and the personalized block sits below Today's
    /// Look, so on a 640dp screen it is not built until scrolled to. An
    /// assertion made without scrolling passes (or fails) for the wrong
    /// reason — the module was never built rather than never rendered.
    Future<void> scrollToBlock(WidgetTester tester) async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await settle(tester);
    }

    testWidgets('a slow backend leaves NO blank block on first paint', (
      tester,
    ) async {
      // The regression this guards: a module that renders an empty card while
      // its provider is loading, so Home paints a grey hole and then jumps.
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _SlowPlanner(delay: const Duration(milliseconds: 400)),
        settleMs: 0, // assert on the FIRST paint, before the plan arrives
      );
      await scrollToBlock(tester);
      final block = tester.getSize(find.byType(WtmHomePersonalized));
      // Nothing known yet except the always-available mood prompt, so the block
      // is exactly one module tall — never an empty placeholder.
      expect(find.text('TODAY’S MOOD'), findsOneWidget);
      expect(find.text('COMING UP'), findsNothing);
      expect(block.height, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an offline backend degrades to the free next action', (
      tester,
    ) async {
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _SlowPlanner(delay: Duration.zero, fail: true),
      );
      await scrollToBlock(tester);
      // Every module whose data failed is absent; Home still works.
      expect(find.text('TODAY’S MOOD'), findsOneWidget);
      expect(find.text('COMING UP'), findsNothing);
      expect(find.text('BASED ON YOUR STYLE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the flag-off Home paints nothing extra, even while loading', (
      tester,
    ) async {
      // The flash this guards: legacy Home rendering, then a new block
      // appearing a frame later once the flags request lands.
      await bootHome(
        tester,
        flags: const {},
        planner: _SlowPlanner(delay: Duration.zero),
      );
      // HEIGHT is the assertion that matters. `SizedBox.shrink()` inside a
      // stretch Column still reports the parent's width, so a zero-Size check
      // would fail for a widget that is correctly painting nothing.
      expect(tester.getSize(find.byType(WtmHomePersonalized)).height, 0.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320dp with 2.0x text', (tester) async {
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _SlowPlanner(delay: Duration.zero),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long event name does not overflow its card', (
      tester,
    ) async {
      final event = StyleEvent(
        id: 'e1',
        name: 'A' * 300,
        eventAt: DateTime.now().add(const Duration(days: 3)),
      );
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FixedPlanner(
          events: StyleEventList(events: [event], nextEvent: event),
        ),
        textScale: 2.0,
      );
      await scrollToBlock(tester);
      expect(find.text('COMING UP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── the render gate ───────────────────────────────────────────────────────

  group('render gate', () {
    testWidgets('all three actions fit at 320dp with 2.0x text', (
      tester,
    ) async {
      await pump(
        tester,
        const WtmRenderGate(),
        textScale: 2.0,
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(
            _FakeMonetization(
              MonetizationConfig.fromJson(const {
                'tier': 'free',
                'free_render_remaining': 0,
              }),
            ),
          ),
        ],
      );
      expect(find.text('Unlock renders'), findsOneWidget);
      expect(find.text('Buy credits'), findsOneWidget);
      expect(find.text('Keep planning for free'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// A planner that answers immediately with fixed data — for layout tests that
/// need a populated module rather than a loading one.
class _FixedPlanner implements PlannerRepository {
  _FixedPlanner({this.events = const StyleEventList()});

  final MoodPlan? plan = null;
  final StyleEventList events;

  @override
  Future<MoodPlan?> createMoodPlan({
    required PlannerMood mood,
    PlannerOccasion? occasion,
  }) async => plan;

  @override
  Future<MoodPlan?> latestMoodPlan() async => plan;

  @override
  Future<StyleEventList> listEvents({bool includePast = false}) async => events;

  @override
  Future<StyleEvent?> createEvent({
    required String name,
    required DateTime eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool reminderOptIn = false,
  }) async => null;

  @override
  Future<StyleEvent?> updateEvent({
    required String id,
    String? name,
    DateTime? eventAt,
    String? occasion,
    String? lookRef,
    String? lookImageUrl,
    String? note,
    bool? reminderOptIn,
  }) async => null;

  @override
  Future<void> deleteEvent(String id) async {}
}
