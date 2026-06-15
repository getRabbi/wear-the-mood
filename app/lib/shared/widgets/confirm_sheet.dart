import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'primary_button.dart';

/// A friendly confirmation bottom sheet (CLAUDE.md §"Polish" — beautiful confirm
/// sheets instead of basic alerts). Returns `true` if the user confirms.
/// Destructive confirmations show the action in danger red.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      final text = Theme.of(ctx).textTheme;
      final accent = destructive ? AppColors.danger : AppColors.accent;
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
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(height: AppSpace.md),
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.sm),
              Text(
                message,
                style: text.bodyMedium?.copyWith(color: AppColors.graphite),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.lg),
              if (destructive)
                _DangerButton(
                  label: confirmLabel,
                  onTap: () => Navigator.of(ctx).pop(true),
                )
              else
                PrimaryButton(
                  label: confirmLabel,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(cancelLabel),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: AppColors.danger,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
