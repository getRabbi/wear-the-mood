import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/shared/widgets/widgets.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

  testWidgets('PrimaryButton shows label and fires onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(PrimaryButton(label: 'Continue', onPressed: () => tapped = true)),
    );
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryButton hides label and is disabled while loading', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        PrimaryButton(
          label: 'Save',
          isLoading: true,
          onPressed: () => tapped = true,
        ),
      ),
    );
    expect(find.text('Save'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(tapped, isFalse);
  });

  testWidgets('EmptyState renders title, message and CTA', (tester) async {
    await tester.pumpWidget(
      host(
        EmptyState(
          title: 'No items yet',
          message: 'Add your first piece',
          actionLabel: 'Add',
          onAction: () {},
        ),
      ),
    );
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.text('Add your first piece'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('ErrorState shows default title and fires onRetry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      host(ErrorState(message: 'Network error', onRetry: () => retried = true)),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(retried, isTrue);
  });

  testWidgets('AppChip renders its label', (tester) async {
    await tester.pumpWidget(host(const AppChip(label: 'Summer', selected: true)));
    expect(find.text('Summer'), findsOneWidget);
  });

  testWidgets('LoadingShimmer builds', (tester) async {
    await tester.pumpWidget(host(const LoadingShimmer(width: 100)));
    expect(find.byType(LoadingShimmer), findsOneWidget);
  });

  testWidgets('OutfitTile shows its label', (tester) async {
    await tester.pumpWidget(
      host(
        const Center(
          child: SizedBox(
            width: 160,
            child: OutfitTile(
              imageUrl: 'https://example.com/look.jpg',
              label: 'Look 1',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(OutfitTile), findsOneWidget);
    expect(find.text('Look 1'), findsOneWidget);
  });
}
