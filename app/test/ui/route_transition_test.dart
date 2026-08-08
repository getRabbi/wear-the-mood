import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/ui/widgets/widgets.dart';

/// Push/pop transition regression tests.
///
/// The bug these lock down: a routed page that painted no background of its
/// own. While a transition runs, `TransitionRoute` clears its overlay entry's
/// `opaque` flag, so Flutter keeps painting the route *underneath* the incoming
/// one — and a transparent incoming page let the outgoing page's text, cards
/// and nav show straight through it for the whole animation. It was worst on
/// iOS, where `CupertinoPageTransition` paints no fill of its own and slides
/// the outgoing page across at full opacity.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // `ThemeData.platform` is exactly what MaterialRouteTransitionMixin reads to
  // pick the page transition, so it is the knob for exercising both platforms.
  Widget host(
    Widget home,
    GlobalKey<NavigatorState> navigator, {
    required TargetPlatform platform,
  }) => MaterialApp(
    navigatorKey: navigator,
    theme: AppTheme.dark().copyWith(platform: platform),
    home: home,
  );

  Finder backdropOf(String marker) =>
      find.ancestor(of: find.text(marker), matching: find.byType(WtmBackdrop));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'on $platform a pushed page owns an opaque full-screen backdrop from the '
      'first transition frame',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          host(
            const WtmPage(title: 'From', children: [Text('outgoing')]),
            navigator,
            platform: platform,
          ),
        );

        unawaitedPush(navigator);
        // One frame in: mid-animation, both routes are in the tree and the
        // outgoing one is still being painted below.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.text('outgoing'), findsOneWidget);
        expect(find.text('incoming'), findsOneWidget);

        final backdrop = backdropOf('incoming');
        expect(
          backdrop,
          findsOneWidget,
          reason:
              'the incoming page must paint its own background, never '
              'borrow the shell\'s',
        );
        // Covers the viewport, so nothing beneath it can show through...
        expect(tester.getSize(backdrop), tester.getSize(find.byType(Overlay)));
        // ...and it is fully opaque.
        final fill = tester.widget<ColoredBox>(
          find
              .descendant(of: backdrop, matching: find.byType(ColoredBox))
              .first,
        );
        expect(fill.color.a, 1.0);

        // Still true once the transition has finished, and after popping back.
        await tester.pumpAndSettle();
        expect(backdropOf('incoming'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(backdropOf('outgoing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('repeated push/pop leaves no stacked or leaked backdrops', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      host(
        const WtmPage(title: 'From', children: [Text('outgoing')]),
        navigator,
        platform: TargetPlatform.iOS,
      ),
    );

    for (var i = 0; i < 3; i++) {
      unawaitedPush(navigator);
      await tester.pumpAndSettle();
      // The pushed page is opaque, so the route below stops painting entirely.
      expect(find.byType(WtmBackdrop), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(WtmBackdrop), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullBleed pages do not double up the backdrop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WtmPage(title: 'Full bleed', fullBleed: true)),
    );
    expect(find.byType(WtmBackdrop), findsOneWidget);
  });

  test('one transition system, retimed, with the platform gestures intact', () {
    final builders = AppTheme.dark().pageTransitionsTheme.builders;

    // Subclasses of the native builders — not a hand-rolled slide — so iOS
    // keeps its interactive edge-swipe back and Android its predictive back.
    expect(
      builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
    expect(
      builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
    for (final builder in builders.values) {
      expect(
        builder.transitionDuration.inMilliseconds,
        inInclusiveRange(220, 300),
      );
      expect(builder.reverseTransitionDuration, builder.transitionDuration);
    }
  });
}

/// Pushes the destination page with the app's standard (platform) route.
void unawaitedPush(GlobalKey<NavigatorState> navigator) {
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const WtmPage(title: 'To', children: [Text('incoming')]),
    ),
  );
}
