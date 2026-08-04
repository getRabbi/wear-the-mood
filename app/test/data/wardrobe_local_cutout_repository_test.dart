import 'dart:typed_data';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_dio.dart';

/// `addItemWithLocalCutout` — the local-cutout persistence call (local BG §9.2).
///
/// The retry rule is the point of this file. The endpoint is idempotent on the
/// original object key, so retrying a TRANSIENT failure is safe and returns the
/// already-created item. Retrying a 4xx is not: it would fail identically, and the
/// caller needs that answer promptly so it can fall back to the cloud create with
/// the same key rather than sitting on a doomed request.
void main() {
  final mask = Uint8List.fromList([1, 2, 3, 4]);

  Future<WardrobeItemResult> call(
    Dio dio, {
    String key = 'user-1/wardrobe/abc.jpg',
  }) async {
    final item = await WardrobeRepository(dio).addItemWithLocalCutout(
      originalObjectKey: key,
      maskPng: mask,
      engine: 'google_mlkit',
      platform: 'android',
      engineVersion: '16.0.0-beta1',
      localLatencyMs: 1200,
      subjectCount: 2,
      title: 'White tee',
    );
    return WardrobeItemResult(item.id, item.cutoutStatus);
  }

  test(
    'posts one multipart request with the mask and the engine metadata',
    () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({'id': 'w1', 'cutout_status': 'done'}, status: 201),
      );

      final result = await call(dio);

      expect(result.id, 'w1');
      expect(result.cutoutStatus, 'done');
      final req = adapter.lastRequest!;
      expect(req.method, 'POST');
      expect(req.path, '/v1/wardrobe/local-cutout');

      final form = req.data as FormData;
      expect(form.files, hasLength(1));
      expect(form.files.first.key, 'mask');
      final fields = Map.fromEntries(form.fields);
      expect(fields['original_object_key'], 'user-1/wardrobe/abc.jpg');
      expect(fields['engine'], 'google_mlkit');
      expect(fields['platform'], 'android');
      expect(fields['engine_version'], '16.0.0-beta1');
      expect(fields['local_latency_ms'], '1200');
      expect(fields['subject_count'], '2');
      expect(fields['title'], 'White tee');
    },
  );

  test('omits optional metadata rather than sending nulls', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({'id': 'w1', 'cutout_status': 'done'}, status: 201),
    );

    await WardrobeRepository(dio).addItemWithLocalCutout(
      originalObjectKey: 'user-1/wardrobe/abc.jpg',
      maskPng: mask,
      engine: 'apple_vision',
      platform: 'ios',
    );

    final fields = Map.fromEntries(
      (adapter.lastRequest!.data as FormData).fields,
    );
    expect(fields.containsKey('title'), isFalse);
    expect(fields.containsKey('category'), isFalse);
  });

  test('a 200 replay of an existing item is returned as-is', () async {
    // The lost-response case: the commit landed, the client never saw it, and the
    // idempotent retry hands back that same item.
    final (dio, _) = fakeDio(
      (_) => jsonResponse({'id': 'existing', 'cutout_status': 'done'}),
    );

    expect((await call(dio)).id, 'existing');
  });

  group('retries exactly once, and only for transient failures', () {
    test('a 5xx is retried and the second answer is used', () async {
      var attempts = 0;
      final (dio, _) = fakeDio((_) {
        attempts++;
        if (attempts == 1) return jsonResponse({'error': 'boom'}, status: 503);
        return jsonResponse({'id': 'w2', 'cutout_status': 'done'}, status: 201);
      });

      expect((await call(dio)).id, 'w2');
      expect(attempts, 2);
    });

    test('a connection error is retried', () async {
      var attempts = 0;
      final (dio, _) = fakeDio((options) {
        attempts++;
        if (attempts == 1) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          );
        }
        return jsonResponse({'id': 'w3', 'cutout_status': 'done'}, status: 201);
      });

      expect((await call(dio)).id, 'w3');
      expect(attempts, 2);
    });

    test('a second transient failure surfaces instead of looping', () async {
      var attempts = 0;
      final (dio, _) = fakeDio((_) {
        attempts++;
        return jsonResponse({'error': 'still down'}, status: 502);
      });

      await expectLater(call(dio), throwsA(isA<ApiException>()));
      expect(attempts, 2, reason: 'exactly one retry, never a loop');
    });

    test('a 422 validation failure is NOT retried', () async {
      // The caller must learn quickly that the mask was refused so it can use the
      // cloud create with the same object key. A retry would just fail again.
      var attempts = 0;
      final (dio, _) = fakeDio((_) {
        attempts++;
        return jsonResponse({
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Mask dimensions'},
        }, status: 422);
      });

      await expectLater(call(dio), throwsA(isA<ApiException>()));
      expect(attempts, 1);
    });

    test('a 404 gated endpoint is NOT retried', () async {
      var attempts = 0;
      final (dio, _) = fakeDio((_) {
        attempts++;
        return jsonResponse({
          'error': {'code': 'NOT_FOUND', 'message': 'Not found.'},
        }, status: 404);
      });

      await expectLater(call(dio), throwsA(isA<ApiException>()));
      expect(attempts, 1);
    });

    test('a 503 provider error IS retried, then surfaces', () async {
      // R2 disabled server-side: transient in shape, so one retry is correct, and
      // the caller then falls back to the cloud path.
      var attempts = 0;
      final (dio, _) = fakeDio((_) {
        attempts++;
        return jsonResponse({
          'error': {'code': 'PROVIDER_ERROR', 'message': 'unavailable'},
        }, status: 503);
      });

      await expectLater(call(dio), throwsA(isA<ApiException>()));
      expect(attempts, 2);
    });

    test(
      'the retry sends a fresh multipart body, not a consumed stream',
      () async {
        // A FormData stream cannot be replayed; reusing one silently sends an empty
        // body on the retry.
        final masks = <int>[];
        var attempts = 0;
        final (dio, _) = fakeDio((options) {
          attempts++;
          masks.add((options.data as FormData).files.length);
          if (attempts == 1) return jsonResponse({}, status: 500);
          return jsonResponse({
            'id': 'w4',
            'cutout_status': 'done',
          }, status: 201);
        });

        expect((await call(dio)).id, 'w4');
        expect(masks, [
          1,
          1,
        ], reason: 'both attempts carry exactly one mask file');
      },
    );
  });

  test(
    'a backend error is surfaced as ApiException, never a raw DioException',
    () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {'code': 'RATE_LIMITED', 'message': 'slow down'},
        }, status: 429),
      );

      await expectLater(call(dio), throwsA(isA<ApiException>()));
    },
  );
}

/// Tiny holder so the helper can return both fields without a records import.
class WardrobeItemResult {
  const WardrobeItemResult(this.id, this.cutoutStatus);
  final String id;
  final String? cutoutStatus;
}
