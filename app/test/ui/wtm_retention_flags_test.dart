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
import 'package:app/l10n/app_localizations.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/home/wtm_home_personalized.dart';
import 'package:app/ui/mirror/wtm_result_feedback.dart';
import 'package:app/ui/paywall/wtm_render_gate.dart';

import '../helpers/fake_wardrobe_items.dart';

/// **The contract every retention flag has to keep.**
///
/// With `feature_personalized_home_v2`, `feature_style_memory` and
/// `feature_style_memory_feedback` OFF — which is how migrations 0074–0076 seed
/// them, and therefore how production will run the day this ships — none of the
/// new surfaces may draw anything at all. Home is Home. The result screen is the
/// result screen. That is what makes a bad rollout survivable by flipping a row
/// in a table rather than shipping a binary (RETENTION spec §13.3, §51).
///
/// These tests assert absence as carefully as presence, because "the flag is
/// off" is exactly the case nobody notices being broken until it is in front of
/// every user.
const _closet = [
  WardrobeItem(id: 'w1', title: 'Silk shirt', cutoutUrl: 'https://x/1.png'),
];

class _FakePlanner implements PlannerRepository {
  _FakePlanner({this.plan, this.events = const StyleEventList()});

  final MoodPlan? plan;
  final StyleEventList events;
  int planCalls = 0;

  @override
  Future<MoodPlan?> createMoodPlan({
    required PlannerMood mood,
    PlannerOccasion? occasion,
  }) async {
    planCalls++;
    return plan;
  }

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

class _FakeStyleMemory implements StyleMemoryRepository {
  _FakeStyleMemory([this.profile = const StyleMemoryProfile()]);

  StyleMemoryProfile profile;
  final List<String> feedbackCalls = [];

  @override
  Future<StyleMemoryProfile> getProfile() async => profile;

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
  }) async => null;

  @override
  Future<StyleMemoryProfile> correct({
    required String facet,
    required String value,
    bool remove = false,
  }) async => profile;

  @override
  Future<StyleMemoryProfile> setPersonalization({
    required bool enabled,
  }) async => profile;

  @override
  Future<int> reset() async => 0;

  @override
  Future<TryOnFeedbackResult?> submitFeedback({
    required String resultId,
    required bool kept,
    RejectionReason? reason,
    String? note,
  }) async {
    feedbackCalls.add(kept ? 'kept' : 'rejected');
    return TryOnFeedbackResult(
      resultId: resultId,
      outcome: kept ? 'kept' : 'rejected',
      recorded: true,
    );
  }
}

class _FakeMonetization implements MonetizationRepository {
  _FakeMonetization(this.config);

  final MonetizationConfig config;
  final List<String> events = [];

  @override
  Future<MonetizationConfig> getConfig() async => config;

  @override
  Future<void> recordEvent({
    required MonetizationSurface surface,
    required MonetizationAction action,
    bool interruptive = false,
    Map<String, String>? context,
  }) async {
    events.add('${surface.wire}:${action.wire}:$interruptive');
  }
}

MoodPlan _plan() => MoodPlan(
  id: 'p1',
  mood: 'calm',
  headline: 'Quiet and easy',
  lines: const ['Aim for soft, unhurried, nothing shouting.'],
  createdAt: DateTime(2026, 8, 20),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> bootHome(
    WidgetTester tester, {
    required Set<String> flags,
    _FakePlanner? planner,
    _FakeStyleMemory? memory,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith((ref) => flags),
        plannerRepositoryProvider.overrideWithValue(planner ?? _FakePlanner()),
        styleMemoryRepositoryProvider.overrideWithValue(
          memory ?? _FakeStyleMemory(),
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
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmHome);
    await settle(tester);
    return container;
  }

  group('Home with the flag OFF', () {
    testWidgets('draws no personalized module at all', (tester) async {
      await bootHome(
        tester,
        flags: const {},
        planner: _FakePlanner(plan: _plan()),
      );

      // The widget is in the tree (it is a const child of the list) but must
      // render nothing — asserting on the MODULE text is what proves that,
      // since a shrink and a module both "exist" as widgets.
      expect(find.byType(WtmHomePersonalized), findsOneWidget);
      expect(find.text('CONTINUE YOUR STYLE'), findsNothing);
      expect(find.text('TODAY’S MOOD'), findsNothing);
      expect(find.text('COMING UP'), findsNothing);
      expect(find.text('WEAR AGAIN'), findsNothing);
    });

    testWidgets('the mood slider and quick actions are untouched', (
      tester,
    ) async {
      await bootHome(tester, flags: const {});
      // The modules that were there before this project must still be there.
      expect(find.text('Try-On\nStudio'), findsWidgets);
      expect(find.text('Smart\nCloset'), findsWidgets);
      expect(find.text('Confident'), findsWidgets);
    });
  });

  group('Home with the flag ON', () {
    testWidgets('a user with no history gets one clear free next action', (
      tester,
    ) async {
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FakePlanner(),
      );

      // No plan yet → the mood prompt, not an empty "Continue your style".
      expect(find.text('TODAY’S MOOD'), findsOneWidget);
      expect(find.text('CONTINUE YOUR STYLE'), findsNothing);
    });

    testWidgets('an existing plan becomes Continue your style', (tester) async {
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FakePlanner(plan: _plan()),
      );

      expect(find.text('CONTINUE YOUR STYLE'), findsOneWidget);
      expect(find.text('Quiet and easy'), findsOneWidget);
      // And the new-user prompt steps aside rather than doubling up.
      expect(find.text('TODAY’S MOOD'), findsNothing);
    });

    testWidgets('an upcoming event surfaces with its countdown', (
      tester,
    ) async {
      final event = StyleEvent(
        id: 'e1',
        name: 'Nadia wedding',
        eventAt: DateTime.now().add(const Duration(days: 3, hours: 2)),
      );
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FakePlanner(
          plan: _plan(),
          events: StyleEventList(events: [event], nextEvent: event),
        ),
      );

      expect(find.text('COMING UP'), findsOneWidget);
      expect(find.text('Nadia wedding'), findsOneWidget);
      expect(find.text('In 3 days'), findsOneWidget);
    });

    testWidgets('a low-confidence style memory is not stated on Home', (
      tester,
    ) async {
      // Below the 0.35 threshold WTM says nothing rather than hedging on the
      // first screen of the app (§12.3).
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FakePlanner(plan: _plan()),
        memory: _FakeStyleMemory(
          const StyleMemoryProfile(
            confidence: 0.1,
            signalCount: 1,
            preferenceSummary: 'Lately you seem to lean toward black tones.',
          ),
        ),
      );

      expect(find.text('BASED ON YOUR STYLE'), findsNothing);
    });

    testWidgets('a confident style memory is surfaced', (tester) async {
      await bootHome(
        tester,
        flags: const {FeatureFlags.personalizedHomeV2},
        planner: _FakePlanner(plan: _plan()),
        memory: _FakeStyleMemory(
          const StyleMemoryProfile(
            confidence: 0.8,
            signalCount: 12,
            preferenceSummary: 'Lately you seem to lean toward black tones.',
          ),
        ),
      );

      expect(find.text('BASED ON YOUR STYLE'), findsOneWidget);
    });
  });

  group('the result feedback row', () {
    Future<void> pumpFeedback(
      WidgetTester tester, {
      required Set<String> flags,
      required String? resultId,
      _FakeStyleMemory? memory,
    }) async {
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          enabledFeatureFlagsProvider.overrideWith((ref) => flags),
          styleMemoryRepositoryProvider.overrideWithValue(
            memory ?? _FakeStyleMemory(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: WtmResultFeedback(resultId: resultId)),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('is absent while the flag is off', (tester) async {
      await pumpFeedback(tester, flags: const {}, resultId: 'r1');
      expect(find.text('Keep it'), findsNothing);
      expect(find.text('Not me'), findsNothing);
    });

    testWidgets('is absent when there is no result to judge', (tester) async {
      // A job that has not produced a result row cannot record a verdict, so
      // the row hides rather than offering an action that would fail.
      await pumpFeedback(
        tester,
        flags: const {FeatureFlags.styleMemoryFeedback},
        resultId: null,
      );
      expect(find.text('Keep it'), findsNothing);
    });

    testWidgets('appears with the flag on and a real result', (tester) async {
      await pumpFeedback(
        tester,
        flags: const {FeatureFlags.styleMemoryFeedback},
        resultId: 'r1',
      );
      expect(find.text('Keep it'), findsOneWidget);
      expect(find.text('Not me'), findsOneWidget);
    });

    testWidgets('Keep it records the verdict and settles into Kept', (
      tester,
    ) async {
      final memory = _FakeStyleMemory();
      await pumpFeedback(
        tester,
        flags: const {FeatureFlags.styleMemoryFeedback},
        resultId: 'r1',
        memory: memory,
      );

      await tester.tap(find.text('Keep it'));
      await settle(tester);

      expect(memory.feedbackCalls, ['kept']);
      expect(find.text('Kept'), findsOneWidget);
    });

    testWidgets('a second tap on Kept cannot record a second verdict', (
      tester,
    ) async {
      final memory = _FakeStyleMemory();
      await pumpFeedback(
        tester,
        flags: const {FeatureFlags.styleMemoryFeedback},
        resultId: 'r1',
        memory: memory,
      );

      await tester.tap(find.text('Keep it'));
      await settle(tester);
      await tester.tap(find.text('Kept'), warnIfMissed: false);
      await settle(tester);

      expect(memory.feedbackCalls, ['kept']);
    });

    testWidgets('Not me opens the structured reason sheet', (tester) async {
      final memory = _FakeStyleMemory();
      await pumpFeedback(
        tester,
        flags: const {FeatureFlags.styleMemoryFeedback},
        resultId: 'r1',
        memory: memory,
      );

      await tester.tap(find.text('Not me'));
      await settle(tester);

      expect(find.text('Not my style'), findsOneWidget);
      // The sheet states plainly that this is not a refund request.
      expect(
        find.textContaining('doesn’t change your credits'),
        findsOneWidget,
      );
      // Nothing is recorded until a reason is actually chosen.
      expect(memory.feedbackCalls, isEmpty);

      await tester.tap(find.text('Not my style'));
      await settle(tester);
      expect(memory.feedbackCalls, ['rejected']);
    });
  });

  group('the render gate', () {
    Future<void> pumpGate(
      WidgetTester tester,
      MonetizationConfig config,
    ) async {
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(
            _FakeMonetization(config),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: WtmRenderGate()),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('says nothing to a free user who still has renders', (
      tester,
    ) async {
      await pumpGate(
        tester,
        MonetizationConfig.fromJson(const {
          'tier': 'free',
          'free_render_remaining': 2,
        }),
      );
      expect(find.textContaining('free renders are used'), findsNothing);
    });

    testWidgets('says nothing to a subscriber', (tester) async {
      await pumpGate(
        tester,
        MonetizationConfig.fromJson(const {
          'tier': 'pro',
          'free_render_remaining': 0,
        }),
      );
      expect(find.textContaining('free renders are used'), findsNothing);
    });

    testWidgets('offers the free path alongside the two paid ones', (
      tester,
    ) async {
      await pumpGate(
        tester,
        MonetizationConfig.fromJson(const {
          'tier': 'free',
          'free_render_remaining': 0,
        }),
      );
      expect(find.textContaining('free renders are used'), findsOneWidget);
      expect(find.text('Unlock renders'), findsOneWidget);
      expect(find.text('Buy credits'), findsOneWidget);
      // The one that must never disappear: a user out of renders still owns
      // everything they saved (§9).
      expect(find.text('Keep planning for free'), findsOneWidget);
    });
  });
}
