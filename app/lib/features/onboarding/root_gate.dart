import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shell/main_shell.dart';
import 'age_gate_screen.dart';
import 'onboarding_providers.dart';
import 'onboarding_screen.dart';

/// First-frame decision (CLAUDE.md §10, §17): a mandatory 16+ age gate comes
/// first, then onboarding on first run, otherwise the app. The age gate fails
/// CLOSED (shows the gate if its flag can't be read) since it's mandatory;
/// onboarding fails open to the app.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(ageGateAcceptedProvider)
        .when(
          loading: () => const _Splash(),
          error: (_, _) => const AgeGateScreen(),
          data: (accepted) => accepted ? const _PostAgeGate() : const AgeGateScreen(),
        );
  }
}

/// After the age gate: onboarding on first run, otherwise the app.
class _PostAgeGate extends ConsumerWidget {
  const _PostAgeGate();

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
