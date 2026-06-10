import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/repositories/profile_repository.dart';

/// Captures + stores the user's avatar selfie (CLAUDE.md §1, §10). Goes to the
/// PRIVATE `avatars` bucket under the user's own folder at a fixed path
/// (overwritten on re-capture); reads use short-lived signed URLs. EXIF is
/// stripped on compress (§8).
class AvatarService {
  AvatarService(this._client, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  static const _bucket = 'avatars';

  String _path(String userId) => '$userId/avatar.jpg';

  /// Picks a selfie (front camera by default) and returns compressed JPEG bytes
  /// with EXIF stripped. Null if the user cancels.
  Future<Uint8List?> pickAndCompress(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 90,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1280,
      minHeight: 1280,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  /// Uploads the avatar (overwriting any previous one) and returns its storage
  /// path (stored on the profile; never a public URL).
  Future<String> upload(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in.');
    final path = _path(userId);
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

  /// Mints a short-lived signed URL for a stored avatar path (for display or to
  /// hand to try-on, §10 — the bucket is private).
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) {
    return _client.storage
        .from(_bucket)
        .createSignedUrl(path, expiresInSeconds);
  }
}

final avatarServiceProvider = Provider<AvatarService>((ref) {
  return AvatarService(ref.watch(supabaseClientProvider));
});

/// A signed URL for the current user's avatar (null if none). Memoized until the
/// profile is invalidated; reused by the avatar screen and try-on.
final avatarSignedUrlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (!profile.hasAvatar) return null;
  return ref.watch(avatarServiceProvider).signedUrl(profile.avatarUrl!);
});
