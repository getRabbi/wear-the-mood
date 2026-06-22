import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/media/media_upload_service.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/utils/image_format.dart';

/// Stores the user's **display** picture — any photo they like (CLAUDE.md §1).
/// PRIVATE: when the write-gate is on it goes to R2 (presigned PUT → object_key),
/// else the legacy `profile-pictures` Supabase bucket (signed reads, §11). EXIF
/// stripped on compress (§8). No pose validation; purely decorative.
class ProfilePictureService {
  ProfilePictureService(this._client, {ImagePicker? picker, MediaUploadService? mediaUpload})
    : _picker = picker ?? ImagePicker(),
      // ignore: prefer_initializing_formals — a private field can't be a named formal.
      _mediaUpload = mediaUpload;

  final SupabaseClient _client;
  final ImagePicker _picker;
  final MediaUploadService? _mediaUpload;

  static const _bucket = 'profile-pictures';

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
      format: CompressFormat.webp,
      keepExif: false,
    );
  }

  /// Uploads the picture. Returns a [MediaRef]: an R2 `objectKey` when the
  /// write-gate is on, else the legacy Supabase `legacyUrl` (a path).
  Future<MediaRef> upload(Uint8List bytes) async {
    final contentType = imageContentType(bytes);
    final media = _mediaUpload;
    if (media == null) {
      return MediaRef(legacyUrl: await _legacyUpload(bytes, contentType));
    }
    return media.upload(
      bytes: bytes,
      sector: 'profile_pic',
      contentType: contentType,
      legacy: () => _legacyUpload(bytes, contentType),
    );
  }

  /// Legacy: upload to the `profile-pictures` Supabase bucket; returns its path.
  Future<String> _legacyUpload(Uint8List bytes, String contentType) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in.');
    final path = '$userId/profile${extForImageContentType(contentType)}';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }
}

final profilePictureServiceProvider = Provider<ProfilePictureService>((ref) {
  return ProfilePictureService(
    ref.watch(supabaseClientProvider),
    mediaUpload: ref.watch(mediaUploadServiceProvider),
  );
});

/// A signed URL for the current user's display picture (null if none) — resolved
/// by the backend (R2 or legacy Supabase); the app no longer self-signs (§11).
final profilePictureSignedUrlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  return profile.profilePictureDisplayUrl;
});
