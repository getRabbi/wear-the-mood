import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/generated_image.dart';
import 'package:app/data/repositories/ai_studio_repository.dart';
import 'package:app/features/studio/ai_looks_screen.dart';
import 'package:app/features/studio/ai_studio_sheet.dart';
import 'package:app/l10n/app_localizations.dart';

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('AI Studio sheet lists the shortcuts + My Style Model coming soon',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAiStudioSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Enhance an item'), findsOneWidget);
    expect(find.text('Create model shot'), findsOneWidget);
    expect(find.text('Try on studio model'), findsOneWidget);
    expect(find.text('View AI Looks'), findsOneWidget);
    // Future-ready My Style Model is shown only as a safe "coming soon".
    expect(find.text('My Style Model'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('AI Looks shows the empty state when there are none', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          generatedImagesProvider.overrideWith((ref) async => <GeneratedImage>[]),
        ],
        child: _app(const AiLooksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Your AI-generated looks will appear here.'), findsOneWidget);
  });

  testWidgets('AI Looks renders a tile per generated image', (tester) async {
    final looks = [
      GeneratedImage(
        id: 'g1', type: 'catalog_model', outputUrl: 'https://x/1.png',
        createdAt: DateTime(2026, 6, 30),
      ),
      GeneratedImage(
        id: 'g2', type: 'enhanced_item', outputUrl: 'https://x/2.png',
        createdAt: DateTime(2026, 6, 30),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          generatedImagesProvider.overrideWith((ref) async => looks),
        ],
        child: _app(const AiLooksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Two generated images → two tappable tiles in the grid.
    expect(find.byType(GestureDetector), findsNWidgets(2));
  });
}
