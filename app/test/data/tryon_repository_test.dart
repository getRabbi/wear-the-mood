import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/repositories/tryon_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test(
    'createTryOn posts the garment + an Idempotency-Key and parses the job',
    () async {
      final (dio, adapter) = fakeDio(
        (_) =>
            jsonResponse({'job_id': 'job-1', 'status': 'queued'}, status: 202),
      );
      final repo = TryOnRepository(dio);

      final job = await repo.createTryOn(
        personImageUrl: 'p.jpg',
        garmentImageUrl: 'g.jpg',
      );

      expect(job.jobId, 'job-1');
      expect(job.status, TryOnStatus.queued);

      final req = adapter.lastRequest!;
      expect(req.path, '/v1/tryon');
      expect(req.headers['Idempotency-Key'], isNotNull);
      final body = _body(req.data);
      expect(body['person_image_url'], 'p.jpg');
      expect(body['garment_image_url'], 'g.jpg');
      expect(body.containsKey('wardrobe_item_id'), isFalse);
    },
  );

  test('createTryOn honors a supplied Idempotency-Key', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({'job_id': 'job-2', 'status': 'queued'}, status: 202),
    );
    await TryOnRepository(dio).createTryOn(
      personImageUrl: 'p.jpg',
      wardrobeItemId: 'w-1',
      idempotencyKey: 'fixed-key',
    );
    expect(adapter.lastRequest!.headers['Idempotency-Key'], 'fixed-key');
    expect(_body(adapter.lastRequest!.data)['wardrobe_item_id'], 'w-1');
  });

  test(
    'createTryOn maps an INSUFFICIENT_CREDITS envelope to ApiException',
    () async {
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {
            'code': 'INSUFFICIENT_CREDITS',
            'message': 'Not enough credits.',
          },
        }, status: 402),
      );

      expect(
        () => TryOnRepository(
          dio,
        ).createTryOn(personImageUrl: 'p', garmentImageUrl: 'g'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.insufficientCredits)
              .having(
                (e) => e.isInsufficientCredits,
                'isInsufficientCredits',
                isTrue,
              )
              .having((e) => e.statusCode, 'statusCode', 402),
        ),
      );
    },
  );

  test('getJob fetches and parses a done result', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'job_id': 'job-1',
        'status': 'done',
        'result_image_url': 'r.jpg',
      }),
    );

    final job = await TryOnRepository(dio).getJob('job-1');
    expect(adapter.lastRequest!.path, '/v1/tryon/job-1');
    expect(job.status.isDone, isTrue);
    expect(job.resultImageUrl, 'r.jpg');
  });
}
