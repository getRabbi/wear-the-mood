import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/media/media_upload_service.dart';
import '../../data/repositories/profile_repository.dart';

/// Captures + stores the user's **try-on body photo** (CLAUDE.md §1, §10). PRIVATE
/// (biometric): when the write-gate is on it goes to R2 (presigned PUT → returns
/// an object_key); otherwise the legacy `avatars` Supabase bucket under the user's
/// own folder (signed reads, §11). EXIF is stripped on compress (§8). Picking and
/// compressing are separate so the caller can run the on-device pose check on the
/// ORIGINAL file before we shrink it.
class AvatarService {
  AvatarService(this._client, {ImagePicker? picker, MediaUploadService? mediaUpload})
    : _picker = picker ?? ImagePicker(),
      // ignore: prefer_initializing_formals — a private field can't be a named formal.
      _mediaUpload = mediaUpload;

  final SupabaseClient _client;
  final ImagePicker _picker;
  final MediaUploadService? _mediaUpload;

  static const _bucket = 'avatars';

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
  /// This also normalizes the format — a HEIC/HEIF (iPhone) or WebP source comes
  /// out as a plain JPEG.
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

  /// Writes JPEG [bytes] to a temp file and returns its path. The on-device pose
  /// check (ML Kit) then reads a guaranteed JPEG, so an unusual source format
  /// (e.g. HEIC) can't make validation choke. The caller deletes it when done.
  Future<String> writeTempJpeg(Uint8List bytes) async {
    final path =
        '${Directory.systemTemp.path}/tryon_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Uploads a NEW gallery try-on photo. Returns a [MediaRef]: an R2 `objectKey`
  /// when the write-gate is on, else the legacy Supabase `legacyUrl` (a path).
  Future<MediaRef> uploadTryonPhoto(Uint8List bytes) async {
    final media = _mediaUpload;
    if (media == null) {
      return MediaRef(legacyUrl: await _legacyUploadTryon(bytes));
    }
    return media.upload(
      bytes: bytes,
      sector: 'tryon_photo',
      legacy: () => _legacyUploadTryon(bytes),
    );
  }

  /// Legacy: each gallery photo is its own object so the user can keep several.
  Future<String> _legacyUploadTryon(Uint8List bytes) async {
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
  return AvatarService(
    ref.watch(supabaseClientProvider),
    mediaUpload: ref.watch(mediaUploadServiceProvider),
  );
});

/// A signed URL for the current user's try-on body photo (null if none) — now
/// resolved by the backend (R2 or legacy Supabase) so the app never self-signs
/// (§11). Reused by the avatar screen and as the try-on person image.
final avatarSignedUrlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  return profile.avatarDisplayUrl;
});
