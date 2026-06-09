import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/models/tryon_job.dart';

void main() {
  group('TryOnJob', () {
    test('parses a queued job', () {
      final job = TryOnJob.fromJson({'job_id': 'j1', 'status': 'queued'});
      expect(job.jobId, 'j1');
      expect(job.status, TryOnStatus.queued);
      expect(job.status.isTerminal, isFalse);
      expect(job.resultImageUrl, isNull);
    });

    test('parses a done job with a result', () {
      final job = TryOnJob.fromJson({
        'job_id': 'j2',
        'status': 'done',
        'result_image_url': 'https://cdn/x.jpg',
      });
      expect(job.status.isDone, isTrue);
      expect(job.status.isTerminal, isTrue);
      expect(job.resultImageUrl, 'https://cdn/x.jpg');
    });

    test('parses a failed job with an error', () {
      final job = TryOnJob.fromJson({
        'job_id': 'j3',
        'status': 'failed',
        'error': 'provider_error',
      });
      expect(job.status.isFailed, isTrue);
      expect(job.error, 'provider_error');
    });
  });

  group('Credits', () {
    test('parses and computes canSpend', () {
      final c = Credits.fromJson({
        'balance': 0,
        'daily_free_used': 2,
        'daily_free_limit': 5,
        'daily_free_remaining': 3,
      });
      expect(c.dailyFreeRemaining, 3);
      expect(c.canSpend, isTrue);
    });

    test('canSpend is false when nothing is left', () {
      final c = Credits.fromJson({
        'balance': 0,
        'daily_free_used': 5,
        'daily_free_limit': 5,
        'daily_free_remaining': 0,
      });
      expect(c.canSpend, isFalse);
    });
  });
}
