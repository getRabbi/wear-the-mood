import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'routes.dart';

/// App router, exposed via Riverpod so it can later react to auth state
/// (redirects in Step 9) and stays testable. Deep links work out of the box
/// from this declarative route table.
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.home,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: AppRoute.home,
        name: AppRoute.homeName,
        builder: (context, state) => const _Phase0Screen(),
      ),
    ],
  );
});

/// Temporary landing so navigation runs end-to-end before real screens exist.
/// Replaced by onboarding/home in Phase 1.
class _Phase0Screen extends StatelessWidget {
  const _Phase0Screen();

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
