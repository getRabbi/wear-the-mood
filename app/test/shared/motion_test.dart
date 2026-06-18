import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/widgets/count_up_text.dart';
import 'package:app/shared/widgets/pressable_scale.dart';
import 'package:app/shared/widgets/staggered_entrance.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );

void main() {
  group('PressableScale', () {
    testWidgets('does not steal the child taps (InkWell still fires)', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressableScale(
                child: Material(
                  child: InkWell(
                    onTap: () => taps++,
                    child: const SizedBox(width: 120, height: 48),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });

  group('CountUpText', () {
    testWidgets('reduce-motion shows the final number immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const CountUpText(value: 42), reduceMotion: true));
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('value 0 renders 0 with no animation', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(value: 0)));
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('counts up to the final value over its duration', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(value: 5)));
      await tester.pump(); // starts at 0
      await tester.pump(const Duration(milliseconds: 900)); // full duration
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('StaggeredItem', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        _wrap(const StaggeredItem(index: 0, child: Text('hi'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('reduce-motion renders the child directly', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StaggeredItem(index: 3, child: Text('now')),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(find.text('now'), findsOneWidget);
    });
  });
}
