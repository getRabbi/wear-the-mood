import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/main_shell.dart';
import 'onboarding_providers.dart';
import 'onboarding_screen.dart';

/// First-frame decision: show onboarding on first run, otherwise the app
/// (CLAUDE.md §17). Fails open to the app if the flag can't be read.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(onboardingSeenProvider)
        .when(
          loading: () => const _Splash(),
          error: (_, _) => const MainShell(),
          data: (done) => done ? const MainShell() : const OnboardingScreen(),
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
