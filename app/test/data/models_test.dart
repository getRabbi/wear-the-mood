import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/models/wardrobe_item.dart';

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
        'total_available': 3,
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

  group('WardrobeItem', () {
    test('parses snake_case keys and prefers the thumbnail', () {
      final item = WardrobeItem.fromJson({
        'id': 'w1',
        'title': 'White tee',
        'category': 'Tops',
        'image_url': 'https://cdn/full.jpg',
        'thumbnail_url': 'https://cdn/thumb.jpg',
      });
      expect(item.id, 'w1');
      expect(item.title, 'White tee');
      expect(item.displayImageUrl, 'https://cdn/thumb.jpg');
    });

    test('falls back to the full image when no thumbnail', () {
      const item = WardrobeItem(id: 'w2', imageUrl: 'https://cdn/full.jpg');
      expect(item.displayImageUrl, 'https://cdn/full.jpg');
    });

    test('parses color, tags and wear metadata', () {
      final item = WardrobeItem.fromJson({
        'id': 'w3',
        'color': 'navy',
        'tags': ['casual', 'denim'],
        'wear_count': 5,
        'last_worn_at': '2026-06-10T10:00:00Z',
      });
      expect(item.color, 'navy');
      expect(item.tags, ['casual', 'denim']);
      expect(item.wearCount, 5);
      expect(item.lastWornAt, isNotNull);
    });

    test('defaults wear metadata when absent (backward-compatible)', () {
      final item = WardrobeItem.fromJson({'id': 'w4'});
      expect(item.wearCount, 0);
      expect(item.tags, isEmpty);
      expect(item.lastWornAt, isNull);
      expect(item.color, isNull);
    });
  });

  group('Profile', () {
    test('parses public fields (bio / style_tags / is_public)', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'display_name': 'Mim',
        'bio': 'minimal modest style',
        'style_tags': ['modest', 'minimal'],
        'is_public': false,
      });
      expect(p.bio, 'minimal modest style');
      expect(p.styleTags, ['modest', 'minimal']);
      expect(p.isPublic, isFalse);
    });

    test('defaults public fields when absent', () {
      final p = Profile.fromJson({'id': 'u1'});
      expect(p.bio, isNull);
      expect(p.styleTags, isEmpty);
      expect(p.isPublic, isTrue); // public by default
    });
  });
}
