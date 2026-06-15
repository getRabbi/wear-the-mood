import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'primary_button.dart';

/// Empty-state placeholder: icon + title + optional message + optional CTA.
/// One of the four required screen states (CLAUDE.md §4.3).
///
/// Strings are passed in by the caller so they can come from `l10n/` (Step 5).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Scroll + center so the state never overflows a short area (e.g. a tab body
    // on a small screen) — fixes "BOTTOM OVERFLOWED" on empty states (spec).
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: c.maxHeight.isFinite ? c.maxHeight : 0,
          ),
          child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: AppSpace.md),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                message!,
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }
}
