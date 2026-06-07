import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app.dart';

void main() {
  testWidgets('App renders the Phase 0 placeholder', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FashionOsApp()),
    );

    expect(find.text('Fashion OS'), findsOneWidget);
    expect(find.text('Phase 0 — Foundations'), findsOneWidget);
  });
}
