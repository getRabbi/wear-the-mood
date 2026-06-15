import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../paywall/billing_providers.dart';

/// Bottom sheet detailing the user's try-on credits (redesign spec — Credits):
/// free try-ons left today, purchased balance, reset info, and an upgrade CTA.
/// Reuses the existing [creditsProvider] / [isPremiumProvider] logic.
Future<void> showCreditsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _CreditsSheet(),
  );
}

class _CreditsSheet extends ConsumerWidget {
  const _CreditsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final credits = ref.watch(creditsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.accent),
                const SizedBox(width: AppSpace.sm),
                Text(l10n.creditsSheetTitle, style: text.titleLarge),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            credits.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpace.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Text(
                l10n.creditsSheetReset,
                style: text.bodyMedium,
              ),
              data: (c) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${c.dailyFreeRemaining}',
                          style: text.displaySmall?.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            l10n.creditsSheetFreeLeft(c.dailyFreeRemaining),
                            style: text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.balance > 0) ...[
                    const SizedBox(height: AppSpace.md),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: AppColors.violet,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          l10n.creditsSheetBalance(c.balance),
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Text(
                    isPremium
                        ? l10n.creditsSheetUnlimited
                        : l10n.creditsSheetReset,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            if (!isPremium)
              PrimaryButton(
                label: l10n.creditsSheetUpgrade,
                icon: Icons.workspace_premium_outlined,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(AppRoute.paywall);
                },
              ),
            const SizedBox(height: AppSpace.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        ),
      ),
    );
  }
}
