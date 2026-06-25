import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/shell/shell_providers.dart';
import 'package:app/features/tryon/open_tryon.dart';
import 'package:app/features/tryon/tryon_preselect.dart';

void main() {
  // BUG 3: every "Try On" entry point must reveal the Try-On page, not just flip
  // the shell tab underneath a still-visible pushed route.
  testWidgets(
    'openTryOnWithItem seeds the preselect, selects the Try-On tab, and '
    'dismisses overlay routes back to the shell',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: _Host())),
      );

      // Open a full-screen route over the "shell".
      await tester.tap(find.text('open overlay'));
      await tester.pumpAndSettle();
      expect(find.text('overlay'), findsOneWidget);

      // Tap Try On in the overlay.
      await tester.tap(find.text('try on'));
      await tester.pumpAndSettle();

      // The overlay is gone — we're back on the shell with the Try-On tab active…
      expect(find.text('overlay'), findsNothing);
      expect(find.text('shell'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('shell')),
      );
      expect(container.read(shellTabProvider), ShellTabs.tryOn);
      // …and the tapped piece is staged for try-on.
      expect(container.read(tryOnPreselectProvider)?.length, 1);
    },
  );

  testWidgets('returns false and stages nothing when the piece has no image', (
    tester,
  ) async {
    late BuildContext ctx;
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (c, r, _) {
              ctx = c;
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    // A still-bare item (no cutout, no original) must NOT silently "succeed".
    final ok = openTryOnWithItem(ctx, ref, const WardrobeItem(id: 'w0'));
    expect(ok, isFalse);

    final container = ProviderScope.containerOf(tester.element(find.byType(Consumer)));
    expect(container.read(tryOnPreselectProvider), isNull);
    expect(container.read(shellTabProvider), ShellTabs.home); // unchanged
  });
}

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('shell'),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _Overlay()),
              ),
              child: const Text('open overlay'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overlay extends ConsumerWidget {
  const _Overlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('overlay'),
            ElevatedButton(
              onPressed: () => openTryOnWithItem(
                context,
                ref,
                const WardrobeItem(id: 'w1', imageUrl: 'https://x/1'),
              ),
              child: const Text('try on'),
            ),
          ],
        ),
      ),
    );
  }
}
