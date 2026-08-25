import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/analytics/analytics.dart';
import 'package:app/core/analytics/analytics_events.dart';
import 'package:app/core/analytics/analytics_provider.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/auth/pending_auth_intent.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/ui/auth/guest_gate.dart';
import 'package:app/ui/auth/wtm_guest_conversion_sheet.dart';

/// THE UI LAYER — the sheet a guest actually sees.
///
/// What is proved here: the copy is action-specific, "Not Now" leaves the user
/// exactly where they were with nothing started, and the funnel events carry an
/// action name and no personal data.
class _RecordingAnalytics implements Analytics {
  final events = <({String name, Map<String, Object>? props})>[];

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) async {
    events.add((name: event, props: properties));
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}

  List<String> get names => [for (final e in events) e.name];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _RecordingAnalytics analytics;
  late ProviderContainer container;

  /// A public screen with one button that asks for a protected action — the
  /// shape of every real call site.
  Future<GuestConversionOutcome?> pumpPublicScreen(
    WidgetTester tester,
    ProtectedAction action, {
    String? resourceId,
    AppSessionState session = AppSessionState.guest,
  }) async {
    analytics = _RecordingAnalytics();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(platform: TargetPlatform.iOS),
        ),
        appSessionProvider.overrideWithValue(session),
        analyticsProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);

    GuestConversionOutcome? outcome;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('PUBLIC CONTENT'),
                    TextButton(
                      onPressed: () async {
                        outcome = await showGuestConversionSheet(
                          context,
                          ref,
                          action: action,
                          resourceId: resourceId,
                        );
                      },
                      child: const Text('DO IT'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('DO IT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return outcome;
  }

  group('the copy is specific to what was tapped', () {
    testWidgets('try-on', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.tryOn);

      expect(find.text('See this look on you'), findsOneWidget);
      expect(
        find.text(
          'Create your private wardrobe to securely store your photos, '
          'credits and try-on results.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('closet', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.closet);

      expect(find.text('Your digital wardrobe'), findsOneWidget);
      expect(find.textContaining('private digital wardrobe'), findsOneWidget);
    });

    testWidgets('save a product', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.saveProduct);

      expect(find.text('Keep this piece'), findsOneWidget);
      expect(
        find.text(
          'Create a free account to save products, use them in outfits '
          'and keep them synced.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('community', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.community);

      expect(find.text('Join the style conversation'), findsOneWidget);
      expect(
        find.text(
          'Create an account to react, comment and follow styles that '
          'inspire you.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('giveaway entry', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.giveawayEntry);

      expect(find.text('Sign in to enter'), findsOneWidget);
      expect(
        find.text(
          'An account is required to verify your entry and notify you '
          'if you win.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('every action has copy — none falls through blank', (
      tester,
    ) async {
      for (final action in ProtectedAction.values) {
        await pumpPublicScreen(tester, action);
        // The sheet's dismiss action is always present, which proves the sheet
        // built at all for this action.
        expect(
          find.text('Not Now'),
          findsOneWidget,
          reason: '${action.name} produced no sheet',
        );
        await tester.tap(find.text('Not Now'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
    });
  });

  group('the sheet always offers a way out', () {
    testWidgets('Not Now leaves the user on the same public screen', (
      tester,
    ) async {
      final outcome = await pumpPublicScreen(tester, ProtectedAction.tryOn);
      expect(outcome, isNull); // still open

      await tester.tap(find.text('Not Now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The sheet is gone and the public content is untouched underneath.
      expect(find.text('See this look on you'), findsNothing);
      expect(find.text('PUBLIC CONTENT'), findsOneWidget);
    });

    testWidgets('dismissing clears the pending intent', (tester) async {
      await pumpPublicScreen(
        tester,
        ProtectedAction.saveProduct,
        resourceId: 'p1',
      );
      // Recorded up front, so a backgrounded OAuth round trip survives.
      expect(container.read(pendingAuthIntentProvider)?.resourceId, 'p1');

      await tester.tap(find.text('Not Now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // …and dropped on an explicit "no", so it cannot fire days later after an
      // unrelated sign-in.
      expect(container.read(pendingAuthIntentProvider), isNull);
    });

    testWidgets('all three actions are present on iOS', (tester) async {
      await pumpPublicScreen(tester, ProtectedAction.tryOn);

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Other Sign-In Options'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);
    });
  });

  group('the guest funnel events are non-PII', () {
    testWidgets('viewing the sheet records the action and nothing else', (
      tester,
    ) async {
      await pumpPublicScreen(
        tester,
        ProtectedAction.tryOn,
        resourceId: 'public-product-1',
      );

      final viewed = analytics.events.singleWhere(
        (e) => e.name == AnalyticsEvents.iosGuestAuthPromptViewed,
      );
      expect(viewed.props, {'action': 'tryOn'});
      // The public product id is NOT sent — it is a resource the user looked
      // at, and analytics has no business with it.
      expect(viewed.props.toString(), isNot(contains('public-product-1')));
    });

    testWidgets('dismissing records a dismissal, not a completion', (
      tester,
    ) async {
      await pumpPublicScreen(tester, ProtectedAction.closet);
      await tester.tap(find.text('Not Now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(analytics.names, contains(AnalyticsEvents.iosGuestAuthDismissed));
      expect(
        analytics.names,
        isNot(contains(AnalyticsEvents.iosGuestAuthCompleted)),
      );
      expect(
        analytics.names,
        isNot(contains(AnalyticsEvents.iosGuestIntentResumed)),
      );
    });

    testWidgets('no event carries an email, a token or a photo path', (
      tester,
    ) async {
      await pumpPublicScreen(tester, ProtectedAction.bodyPhoto);
      for (final event in analytics.events) {
        final dump = '${event.name}${event.props}';
        expect(dump, isNot(contains('@')));
        expect(dump.toLowerCase(), isNot(contains('token')));
        expect(dump.toLowerCase(), isNot(contains('.jpg')));
      }
    });
  });

  group('ensureAccount', () {
    testWidgets('returns true for a member and shows no sheet', (tester) async {
      analytics = _RecordingAnalytics();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appSessionProvider.overrideWithValue(AppSessionState.authenticated),
          analyticsProvider.overrideWithValue(analytics),
        ],
      );
      addTearDown(container.dispose);

      bool? allowed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    allowed = await ensureAccount(
                      context,
                      ref,
                      ProtectedAction.tryOn,
                    );
                  },
                  child: const Text('GO'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('GO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(allowed, isTrue);
      expect(find.text('Not Now'), findsNothing);
      // A member never enters the guest funnel at all.
      expect(analytics.events, isEmpty);
    });

    testWidgets('returns false for a guest and shows the sheet', (
      tester,
    ) async {
      analytics = _RecordingAnalytics();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(platform: TargetPlatform.iOS),
          ),
          appSessionProvider.overrideWithValue(AppSessionState.guest),
          analyticsProvider.overrideWithValue(analytics),
        ],
      );
      addTearDown(container.dispose);

      bool? allowed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    allowed = await ensureAccount(
                      context,
                      ref,
                      ProtectedAction.closet,
                    );
                  },
                  child: const Text('GO'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('GO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Your digital wardrobe'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // False even though the sheet ran: the caller must NOT continue inline.
      // A successful sign-in re-enters through the intent resume instead.
      expect(allowed, isFalse);
    });
  });
}
