import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/shared/widgets/premium_loaders.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Default to reduce-motion so the loaders don't leave a repeating controller /
  // pending timer at teardown — and so we also exercise the reduce-motion path.
  Widget host(Widget child, {bool reduceMotion = true}) => MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('PremiumLogoLoader renders with its label', (tester) async {
    await tester.pumpWidget(
      host(const PremiumLogoLoader(label: 'Loading your closet…')),
    );
    await tester.pump();
    expect(find.byType(PremiumLogoLoader), findsOneWidget);
    expect(find.text('Loading your closet…'), findsOneWidget);
  });

  testWidgets('PremiumAILoader renders with its label', (tester) async {
    await tester.pumpWidget(
      host(const PremiumAILoader(label: 'Enhancing with AI…')),
    );
    await tester.pump();
    expect(find.byType(PremiumAILoader), findsOneWidget);
    expect(find.text('Enhancing with AI…'), findsOneWidget);
  });

  testWidgets('PremiumProgressOverlay shows the message and sub-message', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PremiumProgressOverlay(
        message: 'Creating your look…',
        subMessage: 'Fitting your outfit on the selected body.',
      )),
    );
    await tester.pump();
    expect(find.text('Creating your look…'), findsOneWidget);
    expect(
      find.text('Fitting your outfit on the selected body.'),
      findsOneWidget,
    );
  });

  testWidgets('PremiumInlineLoader renders', (tester) async {
    await tester.pumpWidget(host(const PremiumInlineLoader()));
    await tester.pump();
    expect(find.byType(PremiumInlineLoader), findsOneWidget);
  });

  testWidgets('loaders animate without crashing when motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PremiumAILoader(label: 'x'), reduceMotion: false),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(PremiumAILoader), findsOneWidget);
    // Unmount so the repeating controller is disposed (no pending timer).
    await tester.pumpWidget(const SizedBox());
  });
}
