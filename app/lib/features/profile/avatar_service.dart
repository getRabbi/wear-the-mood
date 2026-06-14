import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/repositories/profile_repository.dart';

/// Captures + stores the user's **try-on body photo** (CLAUDE.md §1, §10). This is
/// the validated full-body image we deliver try-on from. It goes to the PRIVATE
/// `avatars` bucket under the user's own folder at a fixed path (overwritten on
/// re-capture); reads use short-lived signed URLs. EXIF is stripped on compress
/// (§8). Picking and compressing are separate steps so the caller can run the
/// on-device pose check on the ORIGINAL file before we shrink it.
class AvatarService {
  AvatarService(this._client, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  static const _bucket = 'avatars';

  String _path(String userId) => '$userId/avatar.jpg';

  /// Picks a photo. Defaults to the rear camera — a full-body shot needs distance,
  /// not a selfie. Returns the raw [XFile] (with a path for pose detection) or null
  /// if the user cancels.
  Future<XFile?> pick(ImageSource source, {bool preferFront = false}) {
    return _picker.pickImage(
      source: source,
      preferredCameraDevice:
          preferFront ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
  }

  /// Compresses a picked file to a JPEG with EXIF stripped (§8), ready to upload.
  Future<Uint8List> compress(XFile file) async {
    final bytes = await file.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1280,
      minHeight: 1280,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  /// Uploads the body photo (overwriting any previous one) and returns its storage
  /// path (stored on the profile; never a public URL).
  Future<String> upload(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in.');
    return _put(_path(userId), bytes);
  }

  /// Uploads a NEW gallery try-on photo to a unique path under the user's folder
  /// and returns it. Each photo is its own object so the user can keep several.
  Future<String> uploadTryonPhoto(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in.');
    final path = '$userId/tryon/${DateTime.now().microsecondsSinceEpoch}.jpg';
    return _put(path, bytes);
  }

  Future<String> _put(String path, Uint8List bytes) async {
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  /// Mints a short-lived signed URL for a stored path (for display or to hand to
  /// try-on, §10 — the bucket is private).
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) {
    return _client.storage
        .from(_bucket)
        .createSignedUrl(path, expiresInSeconds);
  }
}

final avatarServiceProvider = Provider<AvatarService>((ref) {
  return AvatarService(ref.watch(supabaseClientProvider));
});

/// A signed URL for the current user's try-on body photo (null if none). Memoized
/// until the profile is invalidated; reused by the avatar screen and try-on.
final avatarSignedUrlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (!profile.hasAvatar) return null;
  return ref.watch(avatarServiceProvider).signedUrl(profile.avatarUrl!);
});

/// A signed URL for an arbitrary `avatars`-bucket path — used for the gallery
/// thumbnails. Memoized per path.
final tryonPhotoSignedUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) {
      return ref.watch(avatarServiceProvider).signedUrl(path);
    });
