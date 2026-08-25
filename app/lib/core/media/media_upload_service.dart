import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_required.dart';
import '../auth/protected_action.dart';
import '../network/dio_client.dart';

/// What an upload produced. For a PUBLIC sector this carries a display URL
/// ([publicUrl] for R2, or [legacyUrl] for Supabase). For a PRIVATE sector R2
/// yields only [objectKey] (the caller hands it to the create endpoint, which
/// records the asset and the read endpoint signs it on serve, §8).
class MediaRef {
  const MediaRef({this.objectKey, this.publicUrl, this.legacyUrl});

  final String? objectKey;
  final String? publicUrl;
  final String? legacyUrl;

  /// The URL to store for a PUBLIC image — the R2 CDN url, else the legacy one.
  String get publicDisplayUrl => publicUrl ?? legacyUrl!;
}

class _SignedUpload {
  const _SignedUpload(this.uploadUrl, this.objectKey, this.publicUrl);
  final String uploadUrl;
  final String objectKey;
  final String? publicUrl;
}

/// Uploads images to Cloudflare R2 via a backend-minted presigned PUT (§8: bytes
/// go STRAIGHT to R2, never proxied; §11: the app never holds R2 keys).
///
/// While the server-side write-gate is off the backend returns 503, and this
/// falls back to the caller-provided LEGACY Supabase upload — so the whole path
/// is INERT (identical to today) until the backend flips STORAGE_WRITES=r2, with
/// no app release needed for the cutover.
typedef PutBytes =
    Future<void> Function(String url, Uint8List bytes, String contentType);

class MediaUploadService {
  MediaUploadService(this._api, {PutBytes? put, this.ensureAccount})
    : _put = put ?? _defaultPut;

  final Dio _api;
  final PutBytes _put;

  /// Throws [AuthRequiredException] unless a real session exists.
  ///
  /// Every image the app sends — a garment, a body photo, a post picture —
  /// funnels through [upload], which makes this the one place that has to be
  /// right for "a guest cannot upload anything" to be true. The signing call
  /// would be refused by the network guard anyway; this refuses one step
  /// earlier, with the typed error the UI knows how to convert, and without
  /// putting a request on the wire at all.
  ///
  /// Injected so tests can supply a fake and assert zero calls to either the
  /// signing API or the legacy fallback.
  final VoidCallback? ensureAccount;

  /// ONE client for every presigned PUT in the process.
  ///
  /// This used to be constructed per upload, which meant a fresh connection and
  /// a fresh TLS handshake for every single image — paid on the add-garment
  /// path, the body-photo path and the post-image path alike. Reusing it keeps
  /// the connection alive across a batch.
  ///
  /// Safe to share across accounts precisely BECAUSE it is bare: no base URL,
  /// no interceptors, no auth header and no cookie jar, so it carries nothing
  /// from one user's upload into the next. Authorization lives entirely in the
  /// signature on the URL.
  static final Dio _uploadClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<void> _defaultPut(
    String url,
    Uint8List bytes,
    String contentType,
  ) async {
    // The presigned URL is absolute + already authorized, so this must NOT
    // carry our API base URL or auth header.
    await _uploadClient.put<void>(
      url,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          Headers.contentTypeHeader: contentType,
          Headers.contentLengthHeader: bytes.length,
        },
      ),
    );
  }

  Future<_SignedUpload?> _sign(
    String sector,
    String contentType,
    int size,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/v1/media/upload-url',
        data: {
          'sector': sector,
          'content_type': contentType,
          'byte_size': size,
        },
      );
      final d = res.data!;
      return _SignedUpload(
        d['upload_url'] as String,
        d['object_key'] as String,
        d['public_url'] as String?,
      );
    } on DioException catch (e) {
      // Gate closed (503) → caller falls back to the legacy Supabase upload.
      if (e.response?.statusCode == 503) return null;
      rethrow;
    }
  }

  /// Uploads [bytes] for [sector] via R2 when enabled, else via [legacy].
  Future<MediaRef> upload({
    required Uint8List bytes,
    required String sector,
    required Future<String> Function() legacy,
    String contentType = 'image/jpeg',
  }) async {
    // Before the signature request, and before the legacy fallback: no account,
    // no upload. Deliberately ahead of BOTH paths — guarding only the R2 branch
    // would leave the Supabase fallback open, which is the kind of half-closed
    // gate that ships.
    ensureAccount?.call();

    final signed = await _sign(sector, contentType, bytes.length);
    if (signed == null) {
      return MediaRef(legacyUrl: await legacy());
    }
    await _put(signed.uploadUrl, bytes, contentType);
    return MediaRef(objectKey: signed.objectKey, publicUrl: signed.publicUrl);
  }
}

final mediaUploadServiceProvider = Provider<MediaUploadService>(
  (ref) => MediaUploadService(
    ref.watch(dioProvider),
    ensureAccount: () =>
        requireAuthenticatedUser(ref, ProtectedAction.bodyPhoto),
  ),
);
