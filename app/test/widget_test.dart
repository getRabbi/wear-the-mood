import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';

void main() {
  // Avoid network font fetches during tests; fall back to the default font.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('App renders the localized Phase 0 placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FashionOsApp()));
    await tester.pumpAndSettle();

    expect(find.text('Fashion OS'), findsOneWidget);
    expect(find.text('Phase 0 — Foundations'), findsOneWidget);
  });
}
