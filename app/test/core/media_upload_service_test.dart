import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/media/media_upload_service.dart';

/// Returns a canned HTTP response for the /v1/media/upload-url call so the test
/// never hits the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MediaUploadService _service(
  _FakeAdapter adapter, {
  required List<String> putUrls,
}) {
  final api = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
  Future<void> fakePut(String url, Uint8List bytes, String contentType) async {
    putUrls.add(url);
  }

  return MediaUploadService(api, put: fakePut);
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  test('gate on: uploads to R2 and returns the object_key + public_url', () async {
    final putUrls = <String>[];
    final service = _service(
      _FakeAdapter(
        200,
        '{"upload_url":"https://r2/put","object_key":"u/post/x.jpg",'
        '"public_url":"https://cdn/x.jpg","visibility":"public",'
        '"content_type":"image/jpeg"}',
      ),
      putUrls: putUrls,
    );

    var legacyCalled = false;
    final ref = await service.upload(
      bytes: bytes,
      sector: 'post',
      legacy: () async {
        legacyCalled = true;
        return 'https://supabase/legacy.jpg';
      },
    );

    expect(ref.objectKey, 'u/post/x.jpg');
    expect(ref.publicUrl, 'https://cdn/x.jpg');
    expect(ref.publicDisplayUrl, 'https://cdn/x.jpg');
    expect(putUrls, ['https://r2/put']); // bytes PUT to the presigned URL
    expect(legacyCalled, isFalse); // legacy NOT used when R2 is on
  });

  test('gate off (503): falls back to the legacy upload, no PUT', () async {
    final putUrls = <String>[];
    final service = _service(
      _FakeAdapter(503, '{"error":{"code":"PROVIDER_ERROR","message":"off"}}'),
      putUrls: putUrls,
    );

    var legacyCalled = false;
    final ref = await service.upload(
      bytes: bytes,
      sector: 'post',
      legacy: () async {
        legacyCalled = true;
        return 'https://supabase/legacy.jpg';
      },
    );

    expect(legacyCalled, isTrue);
    expect(ref.legacyUrl, 'https://supabase/legacy.jpg');
    expect(ref.publicDisplayUrl, 'https://supabase/legacy.jpg');
    expect(putUrls, isEmpty); // never PUT to R2 when the gate is closed
  });
}
