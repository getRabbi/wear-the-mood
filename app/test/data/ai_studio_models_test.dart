import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/ai_job.dart';
import 'package:app/data/models/generated_image.dart';
import 'package:app/data/models/studio_model_preset.dart';

void main() {
  group('StudioModelPreset', () {
    test('maps the backend snake_case payload', () {
      final m = StudioModelPreset.fromJson(const {
        'id': 'p1',
        'name': 'Female Studio',
        'image_url': 'https://cdn/m.jpg',
        'style': 'female_studio',
        'body_type': 'average',
        'skin_tone': 'medium',
        'pose_type': 'front_full',
        'is_pro_only': true,
      });
      expect(m.id, 'p1');
      expect(m.name, 'Female Studio');
      expect(m.imageUrl, 'https://cdn/m.jpg');
      expect(m.bodyType, 'average');
      expect(m.isProOnly, isTrue);
    });
  });

  group('AiJob', () {
    test('parses status + output_url and tracks terminal states', () {
      final job = AiJob.fromJson(const {
        'job_id': 'j1',
        'job_type': 'enhance_item',
        'status': 'completed',
        'output_url': 'https://cdn/out.png',
      });
      expect(job.jobId, 'j1');
      expect(job.jobType, 'enhance_item');
      expect(job.status, AiJobStatus.completed);
      expect(job.status.isTerminal, isTrue);
      expect(job.status.isDone, isTrue);
      expect(job.outputUrl, 'https://cdn/out.png');
    });

    test('queued + processing are non-terminal; failed is terminal', () {
      expect(AiJobStatus.queued.isTerminal, isFalse);
      expect(AiJobStatus.processing.isTerminal, isFalse);
      expect(AiJobStatus.failed.isTerminal, isTrue);
      expect(AiJobStatus.failed.isFailed, isTrue);
    });
  });

  group('GeneratedImage', () {
    test('maps type, output_url, source_item_id, created_at', () {
      final g = GeneratedImage.fromJson(const {
        'id': 'g1',
        'type': 'catalog_model',
        'output_url': 'https://cdn/cat.png',
        'source_item_id': 'w1',
        'is_ai_generated': true,
        'created_at': '2026-06-30T10:00:00Z',
      });
      expect(g.id, 'g1');
      expect(g.type, 'catalog_model');
      expect(g.outputUrl, 'https://cdn/cat.png');
      expect(g.sourceItemId, 'w1');
      expect(g.isAiGenerated, isTrue);
      expect(g.createdAt.toUtc().year, 2026);
    });
  });
}
