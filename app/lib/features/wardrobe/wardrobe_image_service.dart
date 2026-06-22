import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/media/media_upload_service.dart';
import '../../shared/utils/uuid.dart';

/// Picks, compresses and uploads wardrobe photos (CLAUDE.md §8). Wardrobe is
/// PRIVATE (INFRA_UPGRADE Ph.1): when the write-gate is on the image goes to R2
/// (presigned PUT → returns an object_key); otherwise it falls back to the legacy
/// `wardrobe` Supabase bucket under the user's own `{user_id}/` folder (RLS, §11).
class WardrobeImageService {
  WardrobeImageService(this._client, {ImagePicker? picker, MediaUploadService? mediaUpload})
    : _picker = picker ?? ImagePicker(),
      // ignore: prefer_initializing_formals — a private field can't be a named formal.
      _mediaUpload = mediaUpload;

  final SupabaseClient _client;
  final ImagePicker _picker;
  final MediaUploadService? _mediaUpload;

  static const _bucket = 'wardrobe';

  /// Picks an image from [source], then returns compressed JPEG bytes with EXIF
  /// stripped (privacy, §8) — ~1600px long edge. Null if the user cancels.
  Future<Uint8List?> pickAndCompress(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  /// Uploads JPEG [bytes] for the signed-in user. Returns a [MediaRef]: an R2
  /// `objectKey` when the write-gate is on, else the legacy Supabase `legacyUrl`.
  Future<MediaRef> upload(Uint8List bytes) async {
    final media = _mediaUpload;
    if (media == null) return MediaRef(legacyUrl: await _legacyUpload(bytes));
    return media.upload(
      bytes: bytes,
      sector: 'wardrobe',
      legacy: () => _legacyUpload(bytes),
    );
  }

  /// Legacy path: upload to the `wardrobe` Supabase bucket; returns its URL.
  Future<String> _legacyUpload(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to upload.');
    }
    final path = '$userId/${uuidV4()}.jpg';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return _client.storage.from(_bucket).getPublicUrl(path);
  }
}

final wardrobeImageServiceProvider = Provider<WardrobeImageService>((ref) {
  return WardrobeImageService(
    ref.watch(supabaseClientProvider),
    mediaUpload: ref.watch(mediaUploadServiceProvider),
  );
});
