import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';

/// Compact credits badge for app bars (CLAUDE.md §12). Shows the paid balance
/// when present, otherwise the remaining free daily try-ons. Dims when nothing
/// is spendable so the user reads "empty" without relying on color alone.
class CreditsChip extends ConsumerWidget {
  const CreditsChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditsProvider);
    final l10n = AppLocalizations.of(context);

    return credits.when(
      loading: () => const _ChipShell(child: _Dots()),
      error: (_, _) => _ChipShell(
        onTap: onTap,
        child: const _Label(icon: Icons.auto_awesome, text: '—'),
      ),
      data: (c) {
        // Subscribers see their total spendable credits (plan + top-up + any free
        // trial left); free users see remaining trial try-ons. Server-authoritative.
        final label = c.isSubscriber
            ? l10n.creditsChipBalance(c.totalAvailable)
            : l10n.creditsChipFree(c.dailyFreeRemaining);
        return _ChipShell(
          onTap: onTap,
          dimmed: !c.canSpend,
          child: _Label(icon: Icons.auto_awesome, text: label),
        );
      },
    );
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.child, this.onTap, this.dimmed = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: onTap != null,
      label: 'Credits',
      child: Material(
        color: dimmed ? AppColors.mist : AppColors.accentSoft,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AppColors.accent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: AppSpace.xs),
        Text(text, style: style),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 16,
      width: 28,
      child: Center(
        child: SizedBox(
          height: 12,
          width: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
