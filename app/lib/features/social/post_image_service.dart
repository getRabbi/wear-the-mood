import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_providers.dart';
import '../../shared/utils/uuid.dart';

/// Picks, compresses and uploads a free-form community post photo (CLAUDE.md §1
/// pillar 4, §8) — so a user can share ANY picture, not just an outfit cutout.
/// Goes to the public `post-images` bucket under the user's own folder (RLS,
/// §11); the backend moderates the image before the post is created (§19).
class PostImageService {
  PostImageService(this._client, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  static const _bucket = 'post-images';

  /// Picks an image, returns compressed JPEG bytes (EXIF stripped, §8). Null if
  /// the user cancels.
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

  /// Uploads JPEG [bytes] to the user's post-images folder; returns the public URL.
  Future<String> upload(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in to post.');
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

  /// Downloads an image's bytes (e.g. a try-on result's signed URL) so they can
  /// be re-uploaded to the durable public post bucket before sharing — a signed
  /// URL expires, so it must never be stored directly on a post (§8). Uses a bare
  /// Dio (no API base URL / auth) since the URL is already absolute + signed.
  Future<Uint8List> downloadImageBytes(String url) async {
    final res = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
}

final postImageServiceProvider = Provider<PostImageService>((ref) {
  return PostImageService(ref.watch(supabaseClientProvider));
});
