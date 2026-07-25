import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/media/image_pick_permission.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/profile/profile_picture_service.dart';
import '../../features/social/public_profile_providers.dart';
import '../../features/social/social_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../widgets/widgets.dart';
import 'wtm_photo_crop.dart';

/// Small circular display-picture avatar (Edit Profile row): the photo when
/// set, else a muted user glyph on the aurora fill.
class WtmProfilePhotoAvatar extends StatelessWidget {
  const WtmProfilePhotoAvatar({super.key, required this.url, this.size = 52});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: WtmGradients.assistFill,
        border: Border.all(color: WtmColors.pillBorder),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (url == null || url!.isEmpty)
          ? WtmIcon(WtmGlyph.user, size: size * 0.42, color: WtmColors.gold)
          : CachedNetworkImage(
              imageUrl: url!,
              cacheKey: stableImageCacheKey(url!),
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Avatars are tiny — never decode a full-size photo for them.
              memCacheWidth: (size * 3).round(),
              errorWidget: (_, _, _) => WtmIcon(
                WtmGlyph.user,
                size: size * 0.42,
                color: WtmColors.gold,
              ),
            ),
    );
  }
}

/// Change / remove the display picture from the WTM profile surfaces — the
/// shipped [ProfilePictureService] flow (pick → **square crop** →
/// compress/EXIF-strip → upload R2/legacy → PATCH profile) behind a WTM sheet.
/// [viewUrl] adds a "View photo" row opening the full-screen preview.
/// Refreshes [profileProvider] so every avatar in the shell updates.
/// Evict the OLD avatar from the image cache and refresh every surface that
/// shows it (own profile/header via [profileProvider], plus the Community feed
/// and public-profile avatars) so a changed photo lands immediately, everywhere,
/// without an app restart — and no stale copy of the old image lingers.
Future<void> _refreshAvatarSurfaces(WidgetRef ref, {String? evictUrl}) async {
  if (evictUrl != null && evictUrl.isNotEmpty) {
    await CachedNetworkImage.evictFromCache(
      evictUrl,
      cacheKey: stableImageCacheKey(evictUrl),
    );
  }
  ref.invalidate(profileProvider);
  ref.invalidate(profilePictureSignedUrlProvider);
  // Own posts + any open public profile also render the avatar — refresh them
  // so Community reflects the new photo too.
  ref.invalidate(feedProvider);
  ref.invalidate(publicProfileProvider);
}

Future<void> showWtmProfilePhotoSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool hasPicture,
  String? viewUrl,
}) async {
  final l10n = AppLocalizations.of(context);
  String? action;
  await showWtmSheet(
    context,
    title: l10n.wtmProfilePhotoTitle,
    subtitle: l10n.profilePictureHint,
    children: [
      if (hasPicture && viewUrl != null) ...[
        WtmRow(
          glyph: WtmGlyph.user,
          title: l10n.wtmProfilePhotoView,
          onTap: () {
            action = 'view';
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(height: 9),
      ],
      WtmRow(
        glyph: WtmGlyph.camera,
        title: l10n.addItemCamera,
        onTap: () {
          action = 'camera';
          Navigator.of(context).pop();
        },
      ),
      const SizedBox(height: 9),
      WtmRow(
        glyph: WtmGlyph.image,
        title: l10n.addItemGallery,
        onTap: () {
          action = 'gallery';
          Navigator.of(context).pop();
        },
      ),
      if (hasPicture) ...[
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.erase,
          title: l10n.profilePictureRemove,
          titleColor: WtmColors.danger,
          iconColor: WtmColors.danger,
          onTap: () {
            action = 'remove';
            Navigator.of(context).pop();
          },
        ),
      ],
    ],
  );
  if (action == null || !context.mounted) return;

  // The currently-shown photo — evicted from cache after a successful change so
  // no stale copy of it lingers on any surface.
  final oldUrl = ref.read(profileProvider).asData?.value.profilePictureDisplayUrl;

  try {
    if (action == 'view') {
      await showWtmProfilePhotoViewer(
        context,
        ref,
        url: viewUrl!,
        canEdit: true,
      );
      return;
    }
    if (action == 'remove') {
      // Empty string clears the picture server-side (shipped contract).
      await runWithWtmProgress(context, l10n.wtmPhotoSaving, () async {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(profilePictureUrl: '');
      });
      await _refreshAvatarSurfaces(ref, evictUrl: oldUrl);
      if (context.mounted) wtmSnack(context, l10n.profilePictureRemoved);
      return;
    }

    final service = ref.read(profilePictureServiceProvider);
    final picked = await service.pickAndCompress(
      action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null || !context.mounted) return; // user cancelled the picker

    // Square crop before saving (mobile QA #4); dismissing the crop cancels.
    final cropped = await showWtmPhotoCrop(context, picked);
    if (cropped == null || !context.mounted) return;
    // Compress + upload + PATCH behind a visible progress dialog — this leg
    // takes seconds on device and must never look stuck (mobile QA #1).
    await runWithWtmProgress(context, l10n.wtmPhotoSaving, () async {
      final bytes = await FlutterImageCompress.compressWithList(
        cropped,
        minWidth: 1024,
        minHeight: 1024,
        quality: 82,
        format: CompressFormat.webp,
        keepExif: false,
      );
      final media = await service.upload(bytes);
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            profilePictureUrl: media.legacyUrl,
            profilePictureObjectKey: media.objectKey,
          );
    });
    await _refreshAvatarSurfaces(ref, evictUrl: oldUrl);
    if (context.mounted) wtmSnack(context, l10n.profilePictureSaved);
  } on ApiException {
    if (context.mounted) wtmSnack(context, l10n.profilePictureError);
  } catch (e) {
    if (!context.mounted) return;
    if (isImagePermissionDenied(e)) {
      await showImagePermissionHelp(context, camera: action == 'camera');
    } else {
      wtmSnack(context, l10n.profilePictureError);
    }
  }
}

/// Full-screen photo preview (own profile → Change/Remove via the sheet;
/// public profiles → view only). Zoomable, dismisses with the back chip.
Future<void> showWtmProfilePhotoViewer(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  bool canEdit = false,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xF2050308),
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            maxScale: 4,
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: stableImageCacheKey(url),
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                child: WtmIcon(WtmGlyph.user, size: 40, color: WtmColors.faint),
              ),
              errorWidget: (_, _, _) => const Center(
                child: WtmIcon(WtmGlyph.user, size: 40, color: WtmColors.faint),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WtmSpace.screenH),
              child: Align(
                alignment: Alignment.topLeft,
                child: WtmIconButton(
                  WtmGlyph.back,
                  semanticLabel: MaterialLocalizations.of(
                    dialogContext,
                  ).backButtonTooltip,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
          if (canEdit)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(WtmSpace.screenH),
                  child: GoldPill(
                    label: l10n.wtmProfilePhotoChange,
                    icon: const WtmIcon(
                      WtmGlyph.camera,
                      size: 12,
                      color: WtmColors.gold,
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      showWtmProfilePhotoSheet(context, ref, hasPicture: true);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
