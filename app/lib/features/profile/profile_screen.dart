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
import '../../data/repositories/tryon_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../outfits/outfit_providers.dart';
import '../social/public_profile_providers.dart';
import '../social/social_providers.dart';
import '../wardrobe/closet_item_card.dart';
import '../wardrobe/drawers/drawer_store.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'profile_picture_service.dart';

/// Social profile + account hub (CLAUDE.md §1, §10). A real profile — header,
/// stats and Looks / Saved / Closet tabs — with the MANDATORY data export and
/// account-deletion flows preserved under Settings. Full email is shown only in
/// the private Settings/account area, never in the public header.
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

  /// Clears the display picture.
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
    final confirmed = await showConfirmSheet(
      context,
      icon: Icons.delete_forever_outlined,
      title: l10n.profileDeleteConfirmTitle,
      message: l10n.profileDeleteConfirmBody,
      confirmLabel: l10n.profileDeleteAccount,
      cancelLabel: l10n.profileCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

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
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: l10n.notificationsTitle,
            onPressed: () => context.push(AppRoute.notifications),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            signedIn ? _signedIn(email) : _guest(),
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

  Widget _signedIn(String email) {
    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Column(
                children: [
                  _ProfileHeaderCard(
                    email: email,
                    localBytes: _newProfilePic,
                    onEditPicture: _changeProfilePicture,
                    onEdit: () => context.push(AppRoute.accountDetails),
                  ),
                  const SizedBox(height: AppSpace.md),
                  const _StatsRow(),
                  const SizedBox(height: AppSpace.md),
                  _PremiumBanner(onTap: () => context.push(AppRoute.paywall)),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.accent,
                indicatorColor: AppColors.accent,
                tabs: [
                  Tab(text: AppLocalizations.of(context).profileTabLooks),
                  Tab(text: AppLocalizations.of(context).profileTabSaved),
                  Tab(text: AppLocalizations.of(context).profileTabCloset),
                  Tab(text: AppLocalizations.of(context).profileTabSettings),
                ],
              ),
              Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ],
        body: TabBarView(
          children: [
            const _LooksTab(),
            const _SavedTab(),
            const _ClosetTab(),
            _SettingsTab(
              email: email,
              onExport: _export,
              onDelete: _confirmDelete,
              onSignOut: () => ref.read(authRepositoryProvider).signOut(),
              onOpenLink: _openLink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _guest() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.profileGuestTitle,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.xs),
              Text(l10n.profileGuestSubtitle,
                  style: Theme.of(context).textTheme.bodySmall),
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
        _PremiumBanner(onTap: () => context.push(AppRoute.paywall)),
        const SizedBox(height: AppSpace.lg),
        _Tile(
          icon: Icons.download_outlined,
          label: l10n.profileExportData,
          onTap: _export,
        ),
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
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── Header ──────────────

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard({
    required this.email,
    required this.localBytes,
    required this.onEditPicture,
    required this.onEdit,
  });

  final String email;
  final Uint8List? localBytes;
  final VoidCallback onEditPicture;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider).asData?.value;
    final name = profile?.displayName;
    final bio = profile?.bio?.trim();
    final tags = profile?.styleTags ?? const <String>[];
    final isPublic = profile?.isPublic ?? true;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A47), Color(0xFF1A102A)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ProfilePictureAvatar(localBytes: localBytes, onTap: onEditPicture),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (name != null && name.trim().isNotEmpty)
                          ? name.trim()
                          : email.split('@').first,
                      style: text.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _maskEmail(email),
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                ),
                child: Text(l10n.profileEditProfile),
              ),
            ],
          ),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bio,
                style: text.bodySmall?.copyWith(color: Colors.white70),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _VisibilityChip(isPublic: isPublic),
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      t,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill showing whether the user's profile is public or private.
class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({required this.isPublic});

  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = isPublic ? AppColors.success : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isPublic
                ? l10n.profileVisibilityPublic
                : l10n.profileVisibilityPrivate,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final myId = ref.watch(currentUserProvider)?.id;
    final closet = ref.watch(wardrobeItemsProvider).asData?.value.length ?? 0;
    final outfits = ref.watch(outfitsProvider).asData?.value.length ?? 0;
    final tryOns = ref.watch(tryOnResultsProvider).asData?.value.length ?? 0;
    final saved = ref.watch(savedLooksProvider).length;
    final drawers = ref.watch(closetDrawersProvider).length;

    // Own follower/following counts come from the same public-profile endpoint
    // (self is always visible, §10) so the numbers match the public profile.
    final social = myId == null
        ? null
        : ref.watch(publicProfileProvider(myId)).asData?.value;
    final followers = social?.followerCount ?? 0;
    final following = social?.followingCount ?? 0;

    String followersPath() => '${AppRoute.userProfilePath(myId!)}/followers';
    String followingPath() => '${AppRoute.userProfilePath(myId!)}/following';

    // Responsive grid (LayoutBuilder + Wrap): fits as many equal-width stat
    // cards per row as the screen allows and wraps the rest — never clipped or
    // cut off on small Android devices (spec). Followers/Following are tappable.
    final stats = <({int value, String label, VoidCallback? onTap})>[
      (
        value: followers,
        label: l10n.profileStatFollowers,
        onTap: myId == null ? null : () => context.push(followersPath()),
      ),
      (
        value: following,
        label: l10n.profileStatFollowing,
        onTap: myId == null ? null : () => context.push(followingPath()),
      ),
      (value: closet, label: l10n.profileStatCloset, onTap: null),
      (value: drawers, label: l10n.profileStatDrawers, onTap: null),
      (value: outfits, label: l10n.profileStatOutfits, onTap: null),
      (value: tryOns, label: l10n.profileStatTryOns, onTap: null),
      (value: saved, label: l10n.profileStatSaved, onTap: null),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = AppSpace.sm;
        // Aim for ~84px cards; never fewer than 3 per row, never more than 5.
        final perRow = ((c.maxWidth + gap) / (84 + gap)).floor().clamp(3, 5);
        final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in stats)
              SizedBox(
                width: width,
                child: _StatCard(
                  value: s.value,
                  label: s.label,
                  onTap: s.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpace.sm,
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadow.soft,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$value',
                  style: text.titleLarge?.copyWith(color: AppColors.accent)),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return PremiumDarkCard(
      onTap: onTap,
      gradientBorder: true,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profilePremiumBannerTitle,
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.profilePremiumBannerSubtitle,
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          const Icon(Icons.chevron_right_rounded, color: Colors.white70),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── Tabs ───────────────

class _LooksTab extends ConsumerWidget {
  const _LooksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final myId = ref.watch(currentUserProvider)?.id;
    final feed = ref.watch(feedProvider);

    return feed.maybeWhen(
      data: (posts) {
        final mine = posts
            .where((p) =>
                p.userId == myId && (p.imageUrl ?? '').isNotEmpty)
            .toList();
        if (mine.isEmpty) {
          return EmptyState(
            icon: Icons.grid_on_outlined,
            title: l10n.profileLooksEmptyTitle,
            message: l10n.profileLooksEmptyMessage,
          );
        }
        return _ImageGrid(urls: [for (final p in mine) p.imageUrl!]);
      },
      orElse: () => SkeletonLoader.grid(aspectRatio: 0.8),
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final savedIds = ref.watch(savedLooksProvider);
    final feed = ref.watch(feedProvider);

    return feed.maybeWhen(
      data: (posts) {
        final saved = posts
            .where((p) =>
                savedIds.contains(p.id) && (p.imageUrl ?? '').isNotEmpty)
            .toList();
        if (saved.isEmpty) {
          return EmptyState(
            icon: Icons.bookmark_border_rounded,
            title: l10n.profileSavedEmptyTitle,
            message: l10n.profileSavedEmptyMessage,
          );
        }
        return _ImageGrid(urls: [for (final p in saved) p.imageUrl!]);
      },
      orElse: () => SkeletonLoader.grid(aspectRatio: 0.8),
    );
  }
}

class _ClosetTab extends ConsumerWidget {
  const _ClosetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(wardrobeItemsProvider);
    final favorites = ref.watch(closetFavoritesProvider);

    return items.when(
      loading: () => SkeletonLoader.grid(aspectRatio: 0.7),
      error: (_, _) => EmptyState(
        icon: Icons.checkroom_outlined,
        title: l10n.wardrobeEmptyTitle,
        message: l10n.profileClosetEmptyMessage,
      ),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.checkroom_outlined,
              title: l10n.wardrobeEmptyTitle,
              message: l10n.wardrobeEmptyMessage,
              actionLabel: l10n.wardrobeAdd,
              onAction: () => context.push(AppRoute.wardrobeAdd),
            )
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(
                AppSpace.screenH,
                AppSpace.md,
                AppSpace.screenH,
                bottomNavClearance(context),
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpace.md,
                crossAxisSpacing: AppSpace.md,
                childAspectRatio: 0.62,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final item = list[i];
                return ClosetItemCard(
                  item: item,
                  compact: true,
                  isFavorite: favorites.contains(item.id),
                  onTap: () =>
                      context.push(AppRoute.wardrobeItem, extra: item),
                  onToggleFavorite: () => ref
                      .read(closetFavoritesProvider.notifier)
                      .toggle(item.id),
                );
              },
            ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        bottomNavClearance(context),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpace.sm,
        crossAxisSpacing: AppSpace.sm,
        childAspectRatio: 0.8,
      ),
      itemCount: urls.length,
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: CachedNetworkImage(
          imageUrl: urls[i],
          fit: BoxFit.cover,
          placeholder: (_, _) => const LoadingShimmer(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
          errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.email,
    required this.onExport,
    required this.onDelete,
    required this.onSignOut,
    required this.onOpenLink,
  });

  final String email;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onSignOut;
  final void Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        bottomNavClearance(context),
      ),
      children: [
        _SettingsGroup(
          title: l10n.profileSectionAccount,
          children: [
            _Tile(
              icon: Icons.badge_outlined,
              label: l10n.profilePersonalDetails,
              onTap: () => context.push(AppRoute.accountDetails),
            ),
            _Tile(
              icon: Icons.face_outlined,
              label: l10n.profileBodyPhoto,
              onTap: () => context.push(AppRoute.avatar),
            ),
            _Tile(
              icon: Icons.card_giftcard_outlined,
              label: l10n.profileInvite,
              onTap: () => context.push(AppRoute.referrals),
            ),
            _Tile(
              icon: Icons.download_outlined,
              label: l10n.profileExportData,
              onTap: onExport,
            ),
            _Tile(
              icon: Icons.logout_rounded,
              label: l10n.profileSignOut,
              onTap: onSignOut,
            ),
          ],
        ),
        _SettingsGroup(
          title: l10n.profileSectionPremium,
          children: [
            _Tile(
              icon: Icons.workspace_premium_outlined,
              label: l10n.profilePremium,
              onTap: () => context.push(AppRoute.paywall),
            ),
          ],
        ),
        _SettingsGroup(
          title: l10n.profileSectionLegal,
          children: [
            _Tile(
              icon: Icons.privacy_tip_outlined,
              label: l10n.profilePrivacy,
              onTap: () => onOpenLink(LegalLinks.privacy),
            ),
            _Tile(
              icon: Icons.description_outlined,
              label: l10n.profileTerms,
              onTap: () => onOpenLink(LegalLinks.terms),
            ),
            _Tile(
              icon: Icons.gavel_outlined,
              label: l10n.profileAcceptableUse,
              onTap: () => onOpenLink(LegalLinks.acceptableUse),
            ),
          ],
        ),
        _SettingsGroup(
          title: l10n.profileSectionDanger,
          children: [
            _Tile(
              icon: Icons.delete_outline_rounded,
              label: l10n.profileDeleteAccount,
              danger: true,
              onTap: onDelete,
            ),
          ],
        ),
      ],
    );
  }
}

/// A titled card grouping related settings rows (spec — grouped settings).
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs,
            ),
            // ListTiles paint ink on the nearest Material; without this the
            // AppCard's colored box would swallow it (debug assertion).
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────── Shared bits ───────────────

/// Masks an email for the public header: keeps a couple of leading characters,
/// hides the rest (CLAUDE.md §10 — no full email in public places).
String _maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final name = email.substring(0, at);
  final domain = email.substring(at);
  final keep = name.length <= 4 ? 2 : 4;
  final visible = name.substring(0, keep.clamp(1, name.length));
  return '$visible••••$domain';
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: background, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) =>
      tabBar != oldDelegate.tabBar || background != oldDelegate.background;
}

class _ProfilePictureAvatar extends ConsumerWidget {
  const _ProfilePictureAvatar({required this.onTap, this.localBytes});

  final VoidCallback onTap;
  final Uint8List? localBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signed = ref.watch(profilePictureSignedUrlProvider);
    final url = signed.asData?.value;
    final ImageProvider? image = localBytes != null
        ? MemoryImage(localBytes!)
        : (url == null ? null : CachedNetworkImageProvider(url));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 30,
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
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 1.5),
                ),
              ),
              child: const Icon(Icons.edit, size: 12, color: Colors.white),
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
