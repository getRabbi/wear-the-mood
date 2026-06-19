import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/widgets/staged_progress_bar.dart';

void main() {
  LinearProgressIndicator bar(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

  testWidgets('shows the label and a determinate bar that eases up over time', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: StagedProgressBar(
                label: 'Removing background',
                estimateSeconds: 5,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Removing background'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final start = bar(tester).value ?? 0;

    // Let the 1s ticker advance a few times, then settle the value tween.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    final later = bar(tester).value ?? 0;
    expect(later, greaterThan(start)); // progresses with elapsed time
    expect(later, lessThan(1.0)); // never completes on its own ("snap to done")

    await tester.pumpWidget(const SizedBox()); // dispose the ticker
  });
}
