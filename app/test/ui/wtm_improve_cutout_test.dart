import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/ui/closet/wtm_cutout_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_dio.dart';

/// "Improve edges" — the free automatic BiRefNet re-run (local BG §6.4, §9.4, §9.5).
///
/// Two things are easy to get wrong and are pinned here:
///
///  * **Improve edges and Fix cutout are different features.** One re-runs the
///    server cutout; the other opens the manual editor. They have separate gates on
///    both sides of the wire, and enabling one must never surface the other.
///  * **A previous valid cutout survives everything.** It stays displayed while an
///    improvement is queued or processing, and it is still displayed if the
///    improvement fails — a user must not lose a good cutout by asking for better.
void main() {
  WardrobeItem item({
    String? cutoutUrl = 'https://cdn/c.png',
    String? status = 'done',
    String? thumbnailUrl,
    String? imageUrl = 'https://cdn/o.jpg',
  }) => WardrobeItem(
    id: 'w1',
    cutoutUrl: cutoutUrl,
    cutoutStatus: status,
    thumbnailUrl: thumbnailUrl,
    imageUrl: imageUrl,
  );

  group('canImproveCutout is a distinct rule from canFixCutout', () {
    test('needs the gate on and a cutout to improve', () {
      expect(canImproveCutout(item(), enabled: true), isTrue);
      expect(canImproveCutout(item(), enabled: false), isFalse);
      expect(canImproveCutout(item(cutoutUrl: null), enabled: true), isFalse);
      expect(canImproveCutout(null, enabled: true), isFalse);
    });

    test('is hidden while an attempt is already in flight', () {
      // Offering it mid-attempt would invite the duplicate tap the server rejects.
      for (final status in ['queued', 'processing']) {
        expect(
          canImproveCutout(item(status: status), enabled: true),
          isFalse,
          reason: status,
        );
      }
    });

    test('is offered again for a FAILED item — the likeliest reason to tap it', () {
      expect(canImproveCutout(item(status: 'failed'), enabled: true), isTrue);
    });

    test('the two gates are independent', () {
      final piece = item();
      // Editor on, local off: Fix cutout only.
      expect(canFixCutout(piece, enabled: true), isTrue);
      expect(canImproveCutout(piece, enabled: false), isFalse);
      // Local on, editor off: Improve edges only.
      expect(canFixCutout(piece, enabled: false), isFalse);
      expect(canImproveCutout(piece, enabled: true), isTrue);
    });

    test('neither is offered for a piece with no cutout at all', () {
      final raw = item(cutoutUrl: null, status: 'queued');
      expect(canFixCutout(raw, enabled: true), isFalse);
      expect(canImproveCutout(raw, enabled: true), isFalse);
    });
  });

  group('the display keeps the old cutout through an improvement (§9.5)', () {
    test('a queued improvement still renders the existing cutout', () {
      final improving = item(status: 'queued');
      expect(improving.displayImageUrl, 'https://cdn/c.png');
      expect(improving.isProcessingCutout, isTrue);
    });

    test('a processing improvement still renders the existing cutout', () {
      expect(item(status: 'processing').displayImageUrl, 'https://cdn/c.png');
    });

    test('a FAILED improvement does not fall back to the original', () {
      // The server never clears cutout_url on failure, and displayImageUrl does not
      // consult cutoutStatus — so the good cutout stays on screen.
      final failed = item(status: 'failed');
      expect(failed.displayImageUrl, 'https://cdn/c.png');
      expect(failed.displayImageUrl, isNot('https://cdn/o.jpg'));
    });

    test('a thumbnail is preferred once the replacement lands', () {
      // Signed-URL refresh after an atomic asset replacement arrives as a new
      // thumbnail/cutout pair; the display picks the thumbnail first.
      final replaced = item(thumbnailUrl: 'https://cdn/t2.webp');
      expect(replaced.displayImageUrl, 'https://cdn/t2.webp');
    });

    test('a fresh cloud item with no cutout yet still shows its processing state', () {
      final fresh = item(cutoutUrl: null, status: 'queued', thumbnailUrl: null);
      expect(fresh.isProcessingCutout, isTrue);
      expect(fresh.displayImageUrl, 'https://cdn/o.jpg');
    });
  });

  group('requestBiRefNetImprovement', () {
    test('POSTs to the improvement route and returns the item', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'id': 'w1',
          'cutout_status': 'queued',
          // The server hands back the CURRENT cutout, not a cleared field.
          'cutout_url': 'https://cdn/c.png',
        }, status: 202),
      );

      final updated = await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/v1/wardrobe/w1/improve-cutout');
      expect(updated.cutoutStatus, 'queued');
      expect(
        updated.cutoutUrl,
        'https://cdn/c.png',
        reason: 'the existing cutout must survive the request',
      );
    });

    test('sends no body — it costs nothing and configures nothing', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({'id': 'w1', 'cutout_status': 'queued'}, status: 202),
      );

      await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(adapter.lastRequest!.data, isNull);
    });

    test('a duplicate tap returns the unchanged in-flight item', () async {
      // The server no-ops a second request for a row already queued/processing.
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'id': 'w1',
          'cutout_status': 'processing',
          'cutout_url': 'https://cdn/c.png',
        }, status: 202),
      );

      final updated = await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(updated.cutoutStatus, 'processing');
      expect(updated.cutoutUrl, 'https://cdn/c.png');
    });

    test('a gated-off endpoint surfaces as ApiException, not a raw DioException', () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {'code': 'NOT_FOUND', 'message': 'Not found.'},
        }, status: 404),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a rate limit surfaces its message', () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {'code': 'RATE_LIMITED', 'message': 'Too many requests.'},
        }, status: 429),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Too many'),
          ),
        ),
      );
    });

    test('it is NOT the editor route', () async {
      // Guards against the two free cutout tools ever being wired to each other.
      final paths = <String>[];
      final (dio, _) = fakeDio((options) {
        paths.add(options.path);
        return jsonResponse({'id': 'w1', 'cutout_status': 'queued'}, status: 202);
      });

      await WardrobeRepository(dio).requestBiRefNetImprovement('w1');

      expect(paths.single, isNot(contains('cutout-mask')));
      expect(paths.single, contains('improve-cutout'));
    });

    test('a network failure is a typed ApiException', () async {
      final (dio, _) = fakeDio(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      );

      await expectLater(
        WardrobeRepository(dio).requestBiRefNetImprovement('w1'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
