import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/legal/legal_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'profile_picture_service.dart';

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
  // Just-picked picture bytes — shown immediately so the avatar updates without
  // waiting on the signed-URL round-trip (the signed URL persists across reopen).
  Uint8List? _newProfilePic;

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

  /// Sets the decorative display picture (separate from the try-on body photo).
  Future<void> _changeProfilePicture() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final hasPic =
        _newProfilePic != null ||
        (ref.read(profileProvider).asData?.value.hasProfilePicture ?? false);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.addItemCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.addItemGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPic)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: Text(l10n.profilePictureRemove),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'remove') {
      await _removeProfilePicture();
      return;
    }
    final source = action == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;

    setState(() => _busy = true);
    try {
      final service = ref.read(profilePictureServiceProvider);
      final bytes = await service.pickAndCompress(source);
      if (bytes == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final path = await service.upload(bytes);
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(profilePictureUrl: path);
      if (mounted) setState(() => _newProfilePic = bytes);
      ref.invalidate(profileProvider);
      ref.invalidate(profilePictureSignedUrlProvider);
      _snack(l10n.profilePictureSaved);
    } on ApiException {
      _snack(l10n.profilePictureError);
    } catch (_) {
      _snack(l10n.profilePictureError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Clears the display picture (empty string => the column reads as "no
  /// picture"; the avatar falls back to the placeholder).
  Future<void> _removeProfilePicture() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(profilePictureUrl: '');
      if (mounted) setState(() => _newProfilePic = null);
      ref.invalidate(profileProvider);
      ref.invalidate(profilePictureSignedUrlProvider);
      _snack(l10n.profilePictureRemoved);
    } on ApiException {
      _snack(l10n.profilePictureError);
    } catch (_) {
      _snack(l10n.profilePictureError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                            _ProfilePictureAvatar(
                              localBytes: _newProfilePic,
                              onTap: _changeProfilePicture,
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
                    icon: Icons.badge_outlined,
                    label: l10n.profilePersonalDetails,
                    onTap: () => context.push(AppRoute.accountDetails),
                  ),
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
                    icon: Icons.card_giftcard_outlined,
                    label: l10n.profileInvite,
                    onTap: () => context.push(AppRoute.referrals),
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

class _ProfilePictureAvatar extends ConsumerWidget {
  const _ProfilePictureAvatar({required this.onTap, this.localBytes});

  final VoidCallback onTap;
  final Uint8List? localBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signed = ref.watch(profilePictureSignedUrlProvider);
    final url = signed.asData?.value;
    // Prefer the just-picked bytes (instant); otherwise the stored signed URL.
    final ImageProvider? image = localBytes != null
        ? MemoryImage(localBytes!)
        : (url == null ? null : CachedNetworkImageProvider(url));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.accentSoft,
            backgroundImage: image,
            child: image == null
                ? const Icon(Icons.person_outline, color: AppColors.accent)
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
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
