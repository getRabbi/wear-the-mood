import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/widgets/wtm_tier_badge.dart';

/// A GUEST HOME MUST BE QUIET.
///
/// Not hiding a widget for tidiness — hiding it because rendering it means
/// ASKING. `WtmMembershipPill` and `WtmTierBadge` both read
/// `accountStatusProvider`, which reads `creditsProvider`, which is a protected
/// call the guest gate refuses. Painted on every Home frame for someone who has
/// no balance, that is a refused request per paint and a pill showing a number
/// that is not true of anybody.
///
/// The reported symptom was "everything loads slowly after signing in from
/// guest". Requests that never needed making are the cheapest part of that to
/// delete.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late int creditsReads;

  Future<void> pump(
    WidgetTester tester, {
    required AppSessionState session,
  }) async {
    creditsReads = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appSessionProvider.overrideWithValue(session),
        // Counts every time the account surface is actually consulted.
        creditsProvider.overrideWith((ref) async {
          creditsReads++;
          return const Credits(
            balance: 7,
            tier: 'pro',
            dailyFreeUsed: 0,
            dailyFreeLimit: 3,
            dailyFreeRemaining: 3,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Row(children: [WtmMembershipPill(), WtmTierBadge()]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a guest is shown no membership pill and no tier badge', (
    tester,
  ) async {
    await pump(tester, session: AppSessionState.guest);

    // Both render nothing at all — not a shimmer, not a zero.
    expect(find.byType(SizedBox), findsNWidgets(2));
    expect(find.textContaining('FREE'), findsNothing);
    expect(find.textContaining('PRO'), findsNothing);
  });

  testWidgets('a guest never causes a credits request', (tester) async {
    await pump(tester, session: AppSessionState.guest);

    expect(
      creditsReads,
      0,
      reason:
          'a guest has no balance to fetch; asking is pure waste and is '
          'refused anyway',
    );
  });

  testWidgets('a member still gets the pill and the badge', (tester) async {
    // The other half of the guarantee: this must not have quietly removed the
    // membership indicator for everyone.
    await pump(tester, session: AppSessionState.authenticated);

    expect(creditsReads, greaterThan(0));
    expect(find.textContaining('PRO'), findsWidgets);
  });

  testWidgets('a still-resolving session shows a shimmer, never a tier', (
    tester,
  ) async {
    // Deliberately NOT hidden while the session resolves. The pill's existing
    // contract is "shimmer rather than flash a wrong Free", and a member on a
    // cold start should see a skeleton settle into their real tier — not an
    // empty gap that pops. The guest guard is a guard on KNOWING you are a
    // guest, which is a different question from not knowing yet.
    creditsReads = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appSessionProvider.overrideWithValue(AppSessionState.unknown),
        // Never completes — the session is still being resolved.
        creditsProvider.overrideWith((ref) {
          creditsReads++;
          return Completer<Credits>().future;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Row(children: [WtmTierBadge()])),
        ),
      ),
    );
    await tester.pump();

    // No tier is claimed while we do not know who this is.
    expect(find.textContaining('PRO'), findsNothing);
    expect(find.textContaining('FREE'), findsNothing);
  });
}
