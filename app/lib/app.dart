import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

/// Root application widget.
///
/// Remaining wiring:
/// - Step 6: `go_router` replaces `home:` with `MaterialApp.router`.
class FashionOsApp extends StatelessWidget {
  const FashionOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.appTitle, style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(l10n.phase0Tagline, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
