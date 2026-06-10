import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/legal/legal_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/repositories/account_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Account + privacy hub (CLAUDE.md §10). Sign-in/out, plus the MANDATORY data
/// export and account-deletion flows. Export copies all of the user's data as
/// JSON to the clipboard; deletion wipes the account server-side then signs out.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLink(String url) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref.read(linkLauncherProvider).open(url);
    if (!ok) _snack(l10n.profileLinkError);
  }

  Future<void> _export() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await ref.read(accountRepositoryProvider).exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: pretty));
      _snack(l10n.profileExportDone);
    } on ApiException {
      _snack(l10n.profileExportError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
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
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(accountRepositoryProvider).deleteAccount();
      // Clear the local session, then return to a clean signed-out state.
      await ref.read(authRepositoryProvider).signOut();
      _snack(l10n.profileDeleteDone);
      if (mounted) context.go(AppRoute.home);
    } on ApiException {
      _snack(l10n.profileDeleteError);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email = ref.watch(signedInEmailProvider);
    final signedIn = email != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
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
                if (signedIn)
                  _Tile(
                    icon: Icons.face_outlined,
                    label: l10n.profileAvatar,
                    onTap: () => context.push(AppRoute.avatar),
                  ),
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
                  onTap: _export,
                ),
                _Tile(
                  icon: Icons.delete_outline_rounded,
                  label: l10n.profileDeleteAccount,
                  danger: true,
                  onTap: _confirmDelete,
                ),
                const SizedBox(height: AppSpace.lg),
                _SectionTitle(l10n.profileSectionLegal),
                _Tile(
                  icon: Icons.privacy_tip_outlined,
                  label: l10n.profilePrivacy,
                  onTap: () => _openLink(LegalLinks.privacy),
                ),
                _Tile(
                  icon: Icons.description_outlined,
                  label: l10n.profileTerms,
                  onTap: () => _openLink(LegalLinks.terms),
                ),
                _Tile(
                  icon: Icons.gavel_outlined,
                  label: l10n.profileAcceptableUse,
                  onTap: () => _openLink(LegalLinks.acceptableUse),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
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
