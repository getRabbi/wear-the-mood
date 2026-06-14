import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/repositories/profile_repository.dart';

/// Stores the user's **display** picture — any photo they like (CLAUDE.md §1).
/// Unlike the try-on body photo there is NO pose validation; it is purely
/// decorative. Kept in the PRIVATE `profile-pictures` bucket under the user's own
/// folder; reads use short-lived signed URLs. EXIF stripped on compress (§8).
class ProfilePictureService {
  ProfilePictureService(this._client, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  static const _bucket = 'profile-pictures';

  String _path(String userId) => '$userId/profile.jpg';

  /// Picks a display photo (front camera by default — it's a portrait), compresses
  /// to a square-ish JPEG with EXIF stripped. Null if the user cancels.
  Future<Uint8List?> pickAndCompress(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1024,
      minHeight: 1024,
      quality: 82,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  /// Uploads the picture (overwriting any previous one) and returns its storage
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

  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) {
    return _client.storage
        .from(_bucket)
        .createSignedUrl(path, expiresInSeconds);
  }
}

final profilePictureServiceProvider = Provider<ProfilePictureService>((ref) {
  return ProfilePictureService(ref.watch(supabaseClientProvider));
});

/// A signed URL for the current user's display picture (null if none). Memoized
/// until the profile is invalidated.
final profilePictureSignedUrlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (!profile.hasProfilePicture) return null;
  return ref
      .watch(profilePictureServiceProvider)
      .signedUrl(profile.profilePictureUrl!);
});
