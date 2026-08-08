import 'package:app/core/network/api_exception.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_analytics.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_quality_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_cutout_fakes.dart';

/// Analytics payloads and the backend error taxonomy (local BG §10, §6.3).
///
/// Most of this file is about what must NOT be present. An analytics payload is
/// the easiest place to leak a path, an object key or an exact dimension by
/// accident, and the leak is invisible until it is already in a third-party
/// system — so the absence is asserted explicitly rather than assumed.
void main() {
  /// Every value that must never appear in any payload, at any nesting level.
  const forbiddenKeys = [
    'width',
    'height',
    'operationId',
    'operation_id',
    'maskFilePath',
    'mask_file_path',
    'cutoutFilePath',
    'cutout_file_path',
    'path',
    'file',
    'filename',
    'objectKey',
    'object_key',
    'url',
    'token',
    'engineVersion',
    'engine_version',
    'message',
    'error',
    'exception',
    'stackTrace',
    'metadata',
    'exif',
  ];

  void assertSafe(Map<String, Object> properties) {
    for (final key in properties.keys) {
      expect(
        forbiddenKeys.contains(key),
        isFalse,
        reason: 'forbidden key "$key" in an analytics payload',
      );
    }
    // Values must be primitives or lists of primitives — never a nested map that
    // could smuggle richer data in later.
    for (final entry in properties.entries) {
      final value = entry.value;
      expect(
        value is String || value is num || value is bool || value is List,
        isTrue,
        reason: '${entry.key} has a non-primitive value',
      );
      if (value is List) {
        for (final element in value) {
          expect(element, isA<String>(), reason: '${entry.key} list element');
        }
      }
    }
  }

  group('buckets, never exact values', () {
    test('latency maps to coarse buckets', () {
      expect(
        localCutoutLatencyBucket(const Duration(milliseconds: 200)),
        'lt500ms',
      );
      expect(
        localCutoutLatencyBucket(const Duration(milliseconds: 900)),
        '500ms-1.5s',
      );
      expect(localCutoutLatencyBucket(const Duration(seconds: 2)), '1.5s-3s');
      expect(localCutoutLatencyBucket(const Duration(seconds: 5)), '3s-6s');
      expect(localCutoutLatencyBucket(const Duration(seconds: 10)), '6s-15s');
      expect(localCutoutLatencyBucket(const Duration(seconds: 40)), 'gt15s');
      expect(
        localCutoutLatencyBucket(const Duration(milliseconds: -1)),
        'unknown',
      );
    });

    test('two nearby latencies collapse to the same bucket', () {
      // The point of bucketing: a payload must not distinguish one user's photo
      // from another's by a few milliseconds.
      expect(
        localCutoutLatencyBucket(const Duration(milliseconds: 1712)),
        localCutoutLatencyBucket(const Duration(milliseconds: 2488)),
      );
    });

    test('subject count is bucketed and clamped', () {
      expect(localCutoutSubjectBucket(0), '0');
      expect(localCutoutSubjectBucket(1), '1');
      expect(localCutoutSubjectBucket(3), '2-3');
      expect(localCutoutSubjectBucket(7), '4-8');
      expect(localCutoutSubjectBucket(5000), 'gt8');
    });
  });

  group('success payload', () {
    Map<String, Object> build({
      LocalCutoutMetrics? metrics,
      Set<LocalCutoutQualityWarning> warnings = const {},
    }) => localCutoutSuccessProperties(
      platform: 'android',
      engine: LocalCutoutEngine.googleMlKit,
      metrics:
          metrics ?? fakeMetrics(width: 1600, height: 1200, subjectCount: 2),
      latency: const Duration(milliseconds: 1200),
      warnings: warnings,
    );

    test('carries only buckets and bounded values', () {
      final properties = build();

      assertSafe(properties);
      expect(properties['platform'], 'android');
      expect(properties['engine'], 'google_mlkit');
      expect(properties['latency_bucket'], '500ms-1.5s');
      expect(properties['subject_bucket'], '2-3');
      expect(properties['size_bucket'], 'le1600');
      expect(properties['accepted'], isTrue);
    });

    test('exact dimensions are absent even though metrics carry them', () {
      final properties = build(
        metrics: fakeMetrics(width: 1601, height: 1199, subjectCount: 1),
      );

      expect(properties.containsKey('width'), isFalse);
      expect(properties.containsKey('height'), isFalse);
      expect(properties.values.contains(1601), isFalse);
      expect(properties.values.contains(1199), isFalse);
    });

    test(
      'warnings are reported as a count, and names are bounded enum names',
      () {
        final properties = build(
          warnings: {
            LocalCutoutQualityWarning.highUncertainty,
            LocalCutoutQualityWarning.lowConfidence,
          },
        );
        expect(properties['warning_count'], 2);
        assertSafe(properties);
      },
    );
  });

  group('fallback payload', () {
    test('reason is a bounded enum name and terminality is explicit', () {
      final properties = localCutoutFallbackProperties(
        platform: 'ios',
        reason: LocalCutoutFallbackReason.unsupportedOs,
        engine: LocalCutoutEngine.appleVision,
      );

      assertSafe(properties);
      expect(properties['fallback_reason'], 'unsupportedOs');
      expect(properties['terminal'], isFalse);
      expect(properties['engine'], 'apple_vision');
    });

    test('sourceMissing is the only reason marked terminal', () {
      for (final reason in LocalCutoutFallbackReason.values) {
        final properties = localCutoutFallbackProperties(
          platform: 'android',
          reason: reason,
        );
        expect(
          properties['terminal'],
          reason == LocalCutoutFallbackReason.sourceMissing,
          reason: reason.name,
        );
      }
    });

    test('every reason produces a safe payload', () {
      for (final reason in LocalCutoutFallbackReason.values) {
        assertSafe(
          localCutoutFallbackProperties(platform: 'android', reason: reason),
        );
      }
    });

    test('the engine key is omitted rather than sent as null', () {
      final properties = localCutoutFallbackProperties(
        platform: 'android',
        reason: LocalCutoutFallbackReason.timeout,
      );
      expect(properties.containsKey('engine'), isFalse);
    });
  });

  group('persist payload', () {
    test('a failure carries a bounded category, never the server message', () {
      final properties = localCutoutPersistProperties(
        platform: 'android',
        engine: LocalCutoutEngine.googleMlKit,
        success: false,
        failureCategory: 'mask_rejected',
      );

      assertSafe(properties);
      expect(properties['success'], isFalse);
      expect(properties['failure_category'], 'mask_rejected');
    });

    test('a success omits the failure category', () {
      final properties = localCutoutPersistProperties(
        platform: 'ios',
        engine: LocalCutoutEngine.appleVision,
        success: true,
      );
      expect(properties.containsKey('failure_category'), isFalse);
    });
  });

  group('failure category never leaks the server message', () {
    test('known codes map to fixed categories', () {
      const cases = {
        ApiErrorCode.sourceMissing: 'source_missing',
        ApiErrorCode.validationError: 'mask_rejected',
        ApiErrorCode.providerError: 'storage_unavailable',
        ApiErrorCode.notFound: 'gate_off',
        ApiErrorCode.rateLimited: 'rate_limited',
        ApiErrorCode.network: 'network',
      };
      cases.forEach((code, category) {
        expect(
          localCutoutFailureCategory(
            ApiException(
              code: code,
              message: 'Mask dimensions (8, 8) must match',
            ),
          ),
          category,
          reason: code,
        );
      });
    });

    test('an unknown code collapses to one bucket, not a novel string', () {
      expect(
        localCutoutFailureCategory(
          const ApiException(code: 'INVENTED_LATER', message: 'x'),
        ),
        'other',
      );
    });

    test('the category never contains any of the message text', () {
      const message =
          'Mask dimensions (8, 8) must match the image (1600, 1200).';
      final category = localCutoutFailureCategory(
        const ApiException(
          code: ApiErrorCode.validationError,
          message: message,
        ),
      );
      expect(message.contains(category), isFalse);
      expect(category, 'mask_rejected');
    });
  });

  group('backend error -> fallback taxonomy (§6.3)', () {
    test('SOURCE_MISSING is terminal and must not queue a cloud attempt', () {
      final reason = localCutoutReasonForApiError(
        const ApiException(code: ApiErrorCode.sourceMissing, message: 'gone'),
      );
      expect(reason, LocalCutoutFallbackReason.sourceMissing);
      expect(reason.canUseCloudFallback, isFalse);
    });

    test('a rejected mask IS recoverable through the cloud path', () {
      // The original is fine; BiRefNet makes its own mask.
      final reason = localCutoutReasonForApiError(
        const ApiException(
          code: ApiErrorCode.validationError,
          message: 'bad mask',
        ),
      );
      expect(reason, LocalCutoutFallbackReason.backendRejected);
      expect(reason.canUseCloudFallback, isTrue);
    });

    test('a transient storage failure IS recoverable', () {
      final reason = localCutoutReasonForApiError(
        const ApiException(
          code: ApiErrorCode.providerError,
          message: 'try later',
        ),
      );
      expect(reason, LocalCutoutFallbackReason.backendUnavailable);
      expect(reason.canUseCloudFallback, isTrue);
    });

    test('a gated-off endpoint is recoverable', () {
      final reason = localCutoutReasonForApiError(
        const ApiException(code: ApiErrorCode.notFound, message: 'Not found.'),
      );
      expect(reason, LocalCutoutFallbackReason.backendUnavailable);
      expect(reason.canUseCloudFallback, isTrue);
    });

    test('an unrecognised code defaults to recoverable, never terminal', () {
      // Defaulting to terminal would strand a recoverable add behind a
      // reselect-the-photo message.
      final reason = localCutoutReasonForApiError(
        const ApiException(code: 'SOMETHING_NEW', message: 'x'),
      );
      expect(reason.canUseCloudFallback, isTrue);
    });
  });

  group('event names', () {
    test('follow the noun_verb snake_case taxonomy', () {
      const names = [
        LocalCutoutEvents.prepareStarted,
        LocalCutoutEvents.prepareReady,
        LocalCutoutEvents.prepareFailed,
        LocalCutoutEvents.started,
        LocalCutoutEvents.succeeded,
        LocalCutoutEvents.hardRejected,
        LocalCutoutEvents.softWarning,
        LocalCutoutEvents.fallbackStarted,
        LocalCutoutEvents.persisted,
        LocalCutoutEvents.sourceMissing,
        LocalCutoutEvents.improvementRequested,
        LocalCutoutEvents.fixCutoutOpened,
      ];
      for (final name in names) {
        expect(name, matches(RegExp(r'^[a-z][a-z0-9_]*$')), reason: name);
        expect(name, startsWith('local_bg_'));
      }
      expect(
        names.toSet().length,
        names.length,
        reason: 'no duplicate event names',
      );
    });
  });
}
