import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/ui/widgets/widgets.dart';

/// A transient error must not follow the user off the screen that raised it.
///
/// Reproduced on a physical iPhone: "That link isn't safe to open." appeared in
/// the article reader and was still there on Discover, on All Picks and over a
/// product — where it reads as a complaint about whatever is now on screen.
/// `ScaffoldMessenger` is one app-level widget, so a snack outlives the route
/// that showed it unless something ties the two together.
///
/// The tie is opt-in, and that is the whole design. "Saved", "Deleted" and
/// "This giveaway was deleted by the owner" are all raised immediately BEFORE
/// popping, as the explanation for the leaving — scoping those by default would
/// have silently deleted every confirmation in the app.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpTwoScreens(
    WidgetTester tester, {
    required bool dismissOnPop,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (home) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(home).push(
                  MaterialPageRoute<void>(
                    builder: (pushed) => Scaffold(
                      body: Center(
                        child: ElevatedButton(
                          onPressed: () => wtmSnack(
                            pushed,
                            'That link isn\'t safe to open.',
                            dismissOnPop: dismissOnPop,
                          ),
                          child: const Text('raise'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('raise'));
    await tester.pumpAndSettle();
  }

  testWidgets('a scoped message leaves with the screen that raised it', (
    tester,
  ) async {
    await pumpTwoScreens(tester, dismissOnPop: true);
    expect(find.text("That link isn't safe to open."), findsOneWidget);

    // Back out — exactly what the user does after a story refuses to open.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(
      find.text("That link isn't safe to open."),
      findsNothing,
      reason: 'the refusal belonged to the article, not to what comes next',
    );
  });

  testWidgets('an unscoped confirmation still survives the pop', (
    tester,
  ) async {
    // The pattern this must not break: tell the user why, THEN leave.
    await pumpTwoScreens(tester, dismissOnPop: false);
    expect(find.text("That link isn't safe to open."), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text("That link isn't safe to open."), findsOneWidget);
    // And it still goes on its own timer rather than sticking forever.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("That link isn't safe to open."), findsNothing);
  });

  testWidgets('a scoped message still expires normally if nobody leaves', (
    tester,
  ) async {
    await pumpTwoScreens(tester, dismissOnPop: true);
    expect(find.text("That link isn't safe to open."), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("That link isn't safe to open."), findsNothing);
  });

  testWidgets('a later snack is not stolen by an earlier scoped one', (
    tester,
  ) async {
    // The failure mode of a naive implementation: the first snack's route pops,
    // its cleanup runs, and it closes whatever happens to be current — which by
    // then is somebody else's message.
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (home) {
            rootContext = home;
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(home).push(
                    MaterialPageRoute<void>(
                      builder: (pushed) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed: () =>
                                wtmSnack(pushed, 'first', dismissOnPop: true),
                            child: const Text('raise'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('raise'));
    await tester.pumpAndSettle();

    // The first message is dismissed on its own before the route goes.
    ScaffoldMessenger.of(rootContext).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    wtmSnack(rootContext, 'second');
    await tester.pumpAndSettle();
    expect(
      find.text('second'),
      findsOneWidget,
      reason: 'a closed message must not reach forward and cancel a later one',
    );
  });
}
