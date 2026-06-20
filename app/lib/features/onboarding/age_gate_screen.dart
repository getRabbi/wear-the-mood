import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'onboarding_providers.dart';

/// Mandatory, neutral 16+ age gate shown by [RootGate] before any app access
/// (CLAUDE.md §10 — sensitive face/body capture). Collects no date of birth — only
/// a confirmation. Confirming persists the flag and lets the gate re-resolve;
/// declaring under-16 shows a polite block (reversible, since nothing is stored).
class AgeGateScreen extends ConsumerStatefulWidget {
  const AgeGateScreen({super.key});

  @override
  ConsumerState<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends ConsumerState<AgeGateScreen> {
  bool _blocked = false;
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(ageGateRepositoryProvider).markAccepted();
    // Re-resolve RootGate, which then continues to onboarding / the app.
    ref.invalidate(ageGateAcceptedProvider);
    // No navigation: RootGate rebuilds and replaces this screen.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _blocked
                      ? Icons.lock_outline_rounded
                      : Icons.verified_user_outlined,
                  size: 40,
                  color: AppColors.accent,
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  _blocked ? l10n.ageGateBlockedTitle : l10n.ageGateTitle,
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  _blocked ? l10n.ageGateBlockedBody : l10n.ageGateBody,
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.xl),
                if (_blocked) ...[
                  TextButton(
                    onPressed: () => setState(() => _blocked = false),
                    child: Text(l10n.ageGateBack),
                  ),
                ] else ...[
                  PrimaryButton(
                    label: l10n.ageGateConfirm,
                    onPressed: _busy ? null : _confirm,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _blocked = true),
                    child: Text(
                      l10n.ageGateUnder,
                      style: text.labelLarge?.copyWith(color: AppColors.graphite),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
