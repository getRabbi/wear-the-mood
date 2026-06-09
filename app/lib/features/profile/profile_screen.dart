import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Account + privacy hub (CLAUDE.md §10). Sign-in/out, plus the MANDATORY data
/// export and account-deletion entry points. The export/delete backends and
/// the legal links land in later steps; their UI + confirmations live here now.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _comingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileDeleteConfirmTitle),
        content: Text(l10n.profileDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.profileCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.profileDeleteAccount),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      _comingSoon(context, l10n.profileComingSoon);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final email = ref.watch(signedInEmailProvider);
    final signedIn = email != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            AppCard(
              child: signedIn
                  ? Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: AppColors.accentSoft,
                          child: Icon(
                            Icons.person_outline,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            l10n.profileSignedInAs(email),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.profileGuestTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          l10n.profileGuestSubtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpace.md),
                        PrimaryButton(
                          label: l10n.profileSignIn,
                          icon: Icons.login_rounded,
                          onPressed: () => context.push(AppRoute.auth),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpace.lg),
            _SectionTitle(l10n.profileSectionAccount),
            _Tile(
              icon: Icons.workspace_premium_outlined,
              label: l10n.profilePremium,
              onTap: () => context.push(AppRoute.paywall),
            ),
            if (signedIn)
              _Tile(
                icon: Icons.logout_rounded,
                label: l10n.profileSignOut,
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            _Tile(
              icon: Icons.download_outlined,
              label: l10n.profileExportData,
              onTap: () => _comingSoon(context, l10n.profileComingSoon),
            ),
            _Tile(
              icon: Icons.delete_outline_rounded,
              label: l10n.profileDeleteAccount,
              danger: true,
              onTap: () => _confirmDelete(context, l10n),
            ),
            const SizedBox(height: AppSpace.lg),
            _SectionTitle(l10n.profileSectionLegal),
            _Tile(
              icon: Icons.privacy_tip_outlined,
              label: l10n.profilePrivacy,
              onTap: () => _comingSoon(context, l10n.profileComingSoon),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: l10n.profileTerms,
              onTap: () => _comingSoon(context, l10n.profileComingSoon),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.sm),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: AppColors.graphite),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}
