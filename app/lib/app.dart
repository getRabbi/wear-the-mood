import 'package:flutter/material.dart';

/// Root application widget.
///
/// Kept intentionally thin for Phase 0. Wiring lands in later steps:
/// - Step 4: design system theme ([AppTheme]) replaces the default theme.
/// - Step 5: localized strings via `l10n/`.
/// - Step 6: `go_router` replaces `home:` with `MaterialApp.router`.
class FashionOsApp extends StatelessWidget {
  const FashionOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fashion OS',
      debugShowCheckedModeBanner: false,
      home: const _Phase0Placeholder(),
    );
  }
}

/// Temporary placeholder so the skeleton runs end-to-end before the real
/// onboarding/home screens exist. Replaced in Phase 1.
class _Phase0Placeholder extends StatelessWidget {
  const _Phase0Placeholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Fashion OS', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Phase 0 — Foundations', style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
