import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../l10n/app_localizations.dart';
import '../auth/welcome_screen.dart';
import '../shell/main_shell.dart';
import 'onboarding_providers.dart';
import 'onboarding_screen.dart';

/// First-frame decision at `/` (CLAUDE.md §11/§17):
/// - signed in            → the app shell ([MainShell]);
/// - signed out, first run → the value carousel ([OnboardingScreen]);
/// - signed out, returning → the welcome/sign-in gate ([WelcomeScreen]).
///
/// Auth is read synchronously (the session is restored in `bootstrap()` before
/// the first frame), so a logged-in cold start goes straight to the app with no
/// content flash, and a logged-out one never reaches gated content. Fails
/// *closed* to the gate — an unreadable onboarding flag never opens the app.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isAuthenticatedProvider)) return const MainShell();

    return ref
        .watch(onboardingSeenProvider)
        .when(
          loading: () => const _Splash(),
          error: (_, _) => const WelcomeScreen(),
          data: (seen) =>
              seen ? const WelcomeScreen() : const OnboardingScreen(),
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle, style: text.displaySmall),
            const SizedBox(height: 8),
            Text(
              l10n.appTagline,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
