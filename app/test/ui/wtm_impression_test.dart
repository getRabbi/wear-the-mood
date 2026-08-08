import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:app/ui/discover/wtm_impression.dart';

/// The three impression rules, tested directly (DISCOVER spec §22): at least
/// half visible, for at least half a second, once per key per session.
///
/// These are the rules the rollout's rates depend on — story open rate, save
/// rate, click-through all divide by impressions — so a change that loosens
/// any of them should fail here rather than quietly inflate every metric.
void main() {
  setUpAll(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  /// Mounts [child] inside a scroll view tall enough that the card starts
  /// off-screen, so visibility is driven by real scrolling rather than by
  /// synthesising VisibilityInfo.
  Future<ScrollController> pumpScroller(
    WidgetTester tester, {
    required Widget child,
    required ProviderContainer container,
    double spacer = 900,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                SizedBox(height: spacer),
                child,
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  ProviderContainer freshContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  Widget card(String key, VoidCallback onImpression) => WtmImpression(
    impressionKey: key,
    onImpression: onImpression,
    child: const SizedBox(height: 200, width: 300),
  );

  testWidgets('a card that is never visible never counts', (tester) async {
    var count = 0;
    await pumpScroller(
      tester,
      container: freshContainer(),
      child: card('a', () => count++),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(count, 0);
  });

  testWidgets('half visible for half a second counts once', (tester) async {
    var count = 0;
    final controller = await pumpScroller(
      tester,
      container: freshContainer(),
      child: card('a', () => count++),
    );

    controller.jumpTo(900);
    await tester.pump();
    // Not yet — the dwell has not elapsed.
    await tester.pump(const Duration(milliseconds: 300));
    expect(count, 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(count, 1);
  });

  testWidgets('a scroll-through does not count', (tester) async {
    // The card passes through the viewport faster than the dwell, which is
    // exactly the case the 500ms rule exists to exclude.
    var count = 0;
    final controller = await pumpScroller(
      tester,
      container: freshContainer(),
      child: card('a', () => count++),
      spacer: 900,
    );

    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    controller.jumpTo(0); // scrolled back off before the dwell completed
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(count, 0);
  });

  testWidgets('the dwell restarts after the card leaves and returns', (
    tester,
  ) async {
    var count = 0;
    final controller = await pumpScroller(
      tester,
      container: freshContainer(),
      child: card('a', () => count++),
    );

    // Partial dwell, leave, come back: the earlier partial must not carry over
    // and complete early.
    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(count, 0);

    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(count, 0, reason: 'the interrupted dwell must not resume');

    await tester.pump(const Duration(milliseconds: 300));
    expect(count, 1);
  });

  testWidgets('scrolling away and back does not count a second time', (
    tester,
  ) async {
    var count = 0;
    final controller = await pumpScroller(
      tester,
      container: freshContainer(),
      child: card('a', () => count++),
    );

    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(count, 1);

    controller.jumpTo(0);
    await tester.pump();
    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(count, 1, reason: 'once per key per session');
  });

  testWidgets('two widgets sharing a key count once between them', (
    tester,
  ) async {
    // The same story rendered twice — a rebuild, or a card that also appears
    // elsewhere — is still one impression.
    var count = 0;
    final container = freshContainer();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 900),
                card('shared', () => count++),
                card('shared', () => count++),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(count, 1);
  });

  testWidgets('different keys count independently', (tester) async {
    final seen = <String>[];
    final container = freshContainer();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 900),
                card('a', () => seen.add('a')),
                card('b', () => seen.add('b')),
                // Trailing slack so an offset exists where BOTH cards sit
                // comfortably inside the viewport, rather than only at the
                // exact scroll edge.
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Both cards occupy 900–1300, so this puts the pair inside the viewport.
    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(seen, containsAll(['a', 'b']));
    expect(seen, hasLength(2));
  });

  testWidgets('a disposed card does not fire after the fact', (tester) async {
    // Navigating away mid-dwell must not report an impression for a card that
    // is no longer on screen.
    var count = 0;
    final container = freshContainer();
    final controller = await pumpScroller(
      tester,
      container: container,
      child: card('a', () => count++),
    );

    controller.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(count, 0);
  });
}
