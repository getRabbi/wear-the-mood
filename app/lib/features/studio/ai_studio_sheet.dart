import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/credits_repository.dart';
import '../../l10n/app_localizations.dart';

/// Entry point for the AI Studio shortcut (Home card / Closet wand). Pro/Pro Max
/// opens the shortcut sheet; free users go to the paywall (BUILD_PROMPT_PRO_
/// PROMAX.md Phase 5).
Future<void> openAiStudio(BuildContext context, WidgetRef ref) async {
  ref.read(analyticsProvider).track(AnalyticsEvents.aiStudioOpened);
  final isSubscriber =
      ref.read(creditsProvider).asData?.value.isSubscriber ?? false;
  if (!isSubscriber) {
    context.push(AppRoute.paywall);
    return;
  }
  await showAiStudioSheet(context);
}

Future<void> showAiStudioSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _AiStudioSheet(),
  );
}

class _AiStudioSheet extends StatelessWidget {
  const _AiStudioSheet();

  void _go(BuildContext context, String path, {bool push = false}) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (push) {
      router.push(path);
    } else {
      router.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.accent),
                const SizedBox(width: AppSpace.sm),
                Text(l10n.aiStudioTitle, style: text.headlineSmall),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(l10n.aiStudioSubtitle, style: text.bodySmall),
            const SizedBox(height: AppSpace.lg),
            _StudioRow(
              icon: Icons.auto_fix_high_rounded,
              title: l10n.aiStudioEnhance,
              subtitle: l10n.aiStudioEnhanceSub,
              onTap: () => _go(context, AppRoute.wardrobe),
            ),
            _StudioRow(
              icon: Icons.checkroom_rounded,
              title: l10n.aiStudioCatalog,
              subtitle: l10n.aiStudioCatalogSub,
              onTap: () => _go(context, AppRoute.wardrobe),
            ),
            _StudioRow(
              icon: Icons.accessibility_new_rounded,
              title: l10n.aiStudioTryStudio,
              subtitle: l10n.aiStudioTryStudioSub,
              onTap: () => _go(context, AppRoute.tryon),
            ),
            _StudioRow(
              icon: Icons.photo_library_outlined,
              title: l10n.aiStudioViewLooks,
              subtitle: l10n.aiStudioViewLooksSub,
              onTap: () => _go(context, AppRoute.aiLooks, push: true),
            ),
            const Divider(height: AppSpace.lg),
            // My Style Model is FUTURE-READY only — shown as a safe, honest
            // "coming soon" (no promise of an exact clone / face / body / fit).
            _StudioRow(
              icon: Icons.face_retouching_natural_outlined,
              title: l10n.aiStudioMyModel,
              subtitle: l10n.aiStudioMyModelSub,
              comingSoon: l10n.aiStudioComingSoon,
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioRow extends StatelessWidget {
  const _StudioRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? comingSoon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: text.titleMedium),
                          if (comingSoon != null) ...[
                            const SizedBox(width: AppSpace.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.glassFill,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Text(
                                comingSoon!,
                                style: text.bodySmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.graphite,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(color: AppColors.graphite),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.graphite),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
