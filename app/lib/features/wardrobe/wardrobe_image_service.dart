import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../shared/utils/uuid.dart';

/// Picks, compresses and uploads wardrobe photos (CLAUDE.md §8). Images go
/// straight to the public `wardrobe` Supabase Storage bucket under the user's
/// own `{user_id}/` folder (RLS-enforced, §11) — never proxied through the API.
class WardrobeImageService {
  WardrobeImageService(this._client, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

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

  /// Uploads JPEG [bytes] to the signed-in user's wardrobe folder and returns
  /// the public CDN URL.
  Future<String> upload(Uint8List bytes) async {
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
  return WardrobeImageService(ref.watch(supabaseClientProvider));
});
