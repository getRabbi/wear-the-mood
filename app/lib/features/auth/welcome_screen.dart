import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// The logged-out gate (CLAUDE.md §11/§17). A calm, on-brand welcome offering
/// sign-in / create-account — never gated content. Non-aggressive: a single
/// screen, no popups. Shown by [RootGate] once onboarding has been seen and no
/// session exists; both buttons open the auth screen (pre-selecting its mode).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  gradient: AppGradients.brand,
                  shape: BoxShape.circle,
                  boxShadow: AppShadow.accentGlow,
                ),
                child: const Icon(
                  Icons.checkroom_rounded,
                  size: 52,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                l10n.appTitle,
                style: text.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                l10n.welcomeSubtitle,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 4),
              PrimaryButton(
                label: l10n.authSignIn,
                onPressed: () =>
                    context.pushNamed(AppRoute.authName, extra: false),
              ),
              const SizedBox(height: AppSpace.md),
              GhostButton(
                label: l10n.authSignUpCta,
                onPressed: () =>
                    context.pushNamed(AppRoute.authName, extra: true),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
