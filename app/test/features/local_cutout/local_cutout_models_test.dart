import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channel contract decoding (local BG §4).
///
/// The native side is untrusted input like any other: a malformed or truncated
/// reply must produce a typed fallback, never a crash and never a "successful"
/// result with missing files.
void main() {
  group('LocalCutoutEngine wire names', () {
    test('round-trip, and the strings are the shipped contract', () {
      expect(LocalCutoutEngine.appleVision.wireName, 'apple_vision');
      expect(LocalCutoutEngine.googleMlKit.wireName, 'google_mlkit');
      for (final engine in LocalCutoutEngine.values) {
        expect(LocalCutoutEngine.fromWireName(engine.wireName), engine);
      }
    });

    test('an unknown or absent engine decodes to null', () {
      expect(LocalCutoutEngine.fromWireName('some_future_engine'), isNull);
      expect(LocalCutoutEngine.fromWireName(null), isNull);
    });
  });

  group('LocalCutoutMetrics.fromMap', () {
    Map<Object?, Object?> validMap() => <Object?, Object?>{
      'width': 1600,
      'height': 1200,
      'subjectCount': 1,
      'foregroundAreaRatio': 0.42,
      'borderForegroundRatio': 0.03,
      'uncertainPixelRatio': 0.11,
      'meanForegroundConfidence': 0.88,
      'foregroundBounds': <Object?, Object?>{
        'left': 100.0,
        'top': 50.0,
        'right': 900.0,
        'bottom': 1000.0,
      },
    };

    test('decodes a complete payload including bounds', () {
      final metrics = LocalCutoutMetrics.fromMap(validMap())!;
      expect(metrics.width, 1600);
      expect(metrics.height, 1200);
      expect(metrics.subjectCount, 1);
      expect(metrics.foregroundAreaRatio, closeTo(0.42, 1e-9));
      expect(metrics.foregroundBounds, const Rect.fromLTRB(100, 50, 900, 1000));
      expect(metrics.isWellFormed, isTrue);
    });

    test('accepts ints where doubles are expected (channel codecs narrow)', () {
      final map = validMap()..['foregroundAreaRatio'] = 1;
      expect(LocalCutoutMetrics.fromMap(map)!.foregroundAreaRatio, 1.0);
    });

    test('a missing required field decodes to null', () {
      for (final key in [
        'width',
        'height',
        'subjectCount',
        'foregroundAreaRatio',
        'borderForegroundRatio',
        'uncertainPixelRatio',
        'meanForegroundConfidence',
      ]) {
        final map = validMap()..remove(key);
        expect(LocalCutoutMetrics.fromMap(map), isNull, reason: 'missing $key');
      }
    });

    test('bounds are optional, and a malformed box is dropped not fatal', () {
      final without = validMap()..remove('foregroundBounds');
      expect(LocalCutoutMetrics.fromMap(without)!.foregroundBounds, isNull);

      final malformed = validMap()
        ..['foregroundBounds'] = <Object?, Object?>{'left': 1.0, 'top': 2.0};
      final metrics = LocalCutoutMetrics.fromMap(malformed);
      expect(metrics, isNotNull);
      expect(metrics!.foregroundBounds, isNull);
    });

    test('a non-finite bound is dropped', () {
      final map = validMap()
        ..['foregroundBounds'] = <Object?, Object?>{
          'left': 0.0,
          'top': 0.0,
          'right': double.infinity,
          'bottom': 10.0,
        };
      expect(LocalCutoutMetrics.fromMap(map)!.foregroundBounds, isNull);
    });

    test('null map decodes to null', () {
      expect(LocalCutoutMetrics.fromMap(null), isNull);
    });
  });

  group('LocalCutoutMetrics.isWellFormed', () {
    LocalCutoutMetrics build({
      int width = 1600,
      int height = 1200,
      int subjectCount = 1,
      double area = 0.4,
      double border = 0.1,
      double uncertain = 0.1,
      double confidence = 0.9,
    }) => LocalCutoutMetrics(
      width: width,
      height: height,
      subjectCount: subjectCount,
      foregroundAreaRatio: area,
      borderForegroundRatio: border,
      uncertainPixelRatio: uncertain,
      meanForegroundConfidence: confidence,
    );

    test('a plausible result is well formed', () {
      expect(build().isWellFormed, isTrue);
    });

    test('NaN and infinity are never well formed', () {
      expect(build(area: double.nan).isWellFormed, isFalse);
      expect(build(border: double.infinity).isWellFormed, isFalse);
      expect(build(uncertain: double.negativeInfinity).isWellFormed, isFalse);
      expect(build(confidence: double.nan).isWellFormed, isFalse);
    });

    test('out-of-range ratios and zero dimensions are not well formed', () {
      expect(build(area: 1.5).isWellFormed, isFalse);
      expect(build(area: -0.1).isWellFormed, isFalse);
      expect(build(width: 0).isWellFormed, isFalse);
      expect(build(height: -1).isWellFormed, isFalse);
    });
  });

  group('LocalCutoutResult.fromMap', () {
    Map<Object?, Object?> validMap() => <Object?, Object?>{
      'engine': 'google_mlkit',
      'engineVersion': '16.0.0-beta1',
      'operationId': 'a1b2c3',
      'operationDirectory': '/cache/wtm-bg/a1b2c3',
      'maskFilePath': '/cache/wtm-bg/a1b2c3/m.png',
      'cutoutFilePath': '/cache/wtm-bg/a1b2c3/c.png',
      'latencyMs': 1234,
      'metrics': <Object?, Object?>{
        'width': 1600,
        'height': 1200,
        'subjectCount': 2,
        'foregroundAreaRatio': 0.5,
        'borderForegroundRatio': 0.02,
        'uncertainPixelRatio': 0.07,
        'meanForegroundConfidence': 0.81,
      },
    };

    test('decodes a complete payload', () {
      final result = LocalCutoutResult.fromMap(validMap())!;
      expect(result.engine, LocalCutoutEngine.googleMlKit);
      expect(result.engineVersion, '16.0.0-beta1');
      expect(result.operationId, 'a1b2c3');
      expect(result.maskFilePath, '/cache/wtm-bg/a1b2c3/m.png');
      expect(result.cutoutFilePath, '/cache/wtm-bg/a1b2c3/c.png');
      expect(result.latency, const Duration(milliseconds: 1234));
      expect(result.metrics.subjectCount, 2);
    });

    test('never returns a "success" with a missing or empty path', () {
      for (final key in [
        'operationId',
        'operationDirectory',
        'maskFilePath',
        'cutoutFilePath',
      ]) {
        expect(
          LocalCutoutResult.fromMap(validMap()..remove(key)),
          isNull,
          reason: 'missing $key',
        );
        expect(
          LocalCutoutResult.fromMap(validMap()..[key] = ''),
          isNull,
          reason: 'empty $key',
        );
      }
    });

    test('an unknown engine or malformed metrics decodes to null', () {
      expect(LocalCutoutResult.fromMap(validMap()..['engine'] = 'magic'), isNull);
      expect(
        LocalCutoutResult.fromMap(
          validMap()..['metrics'] = <Object?, Object?>{'width': 10},
        ),
        isNull,
      );
    });

    test('a missing or negative latency clamps to zero rather than failing', () {
      expect(
        LocalCutoutResult.fromMap(validMap()..remove('latencyMs'))!.latency,
        Duration.zero,
      );
      expect(
        LocalCutoutResult.fromMap(validMap()..['latencyMs'] = -5)!.latency,
        Duration.zero,
      );
    });

    test('an over-long engine version is bounded, not trusted verbatim', () {
      final result = LocalCutoutResult.fromMap(
        validMap()..['engineVersion'] = 'x' * 500,
      )!;
      expect(result.engineVersion.length, 64);
    });

    test('a missing engine version falls back to a safe literal', () {
      expect(
        LocalCutoutResult.fromMap(validMap()..remove('engineVersion'))!.engineVersion,
        'unknown',
      );
    });
  });

  group('LocalCutoutCapability', () {
    test('decodes every known availability', () {
      const wire = {
        'available': LocalCutoutAvailability.available,
        'unsupported_os': LocalCutoutAvailability.unsupportedOs,
        'missing_google_play_services':
            LocalCutoutAvailability.missingGooglePlayServices,
        'model_not_installed': LocalCutoutAvailability.modelNotInstalled,
        'model_download_failed': LocalCutoutAvailability.modelDownloadFailed,
      };
      wire.forEach((value, expected) {
        final capability = LocalCutoutCapability.fromMap(<Object?, Object?>{
          'availability': value,
          'engine': 'google_mlkit',
        });
        expect(capability.availability, expected, reason: value);
      });
    });

    test('an unrecognised availability is transient, not permanent', () {
      // A newer native layer must never convince an older Dart layer that the
      // device is permanently incapable.
      final capability = LocalCutoutCapability.fromMap(<Object?, Object?>{
        'availability': 'something_new',
        'engine': 'apple_vision',
      });
      expect(capability.availability, LocalCutoutAvailability.temporarilyUnavailable);
      expect(capability.isAvailable, isFalse);
    });

    test('null map and the unsupported constant are both unsupported', () {
      expect(
        LocalCutoutCapability.fromMap(null).availability,
        LocalCutoutAvailability.unsupportedOs,
      );
      expect(const LocalCutoutCapability.unsupported().isAvailable, isFalse);
    });

    test('available without an engine is not usable', () {
      final capability = LocalCutoutCapability.fromMap(<Object?, Object?>{
        'availability': 'available',
      });
      expect(capability.availability, LocalCutoutAvailability.available);
      expect(capability.isAvailable, isFalse);
    });
  });

  group('error-code mapping', () {
    test('every native code maps to its reason', () {
      const cases = {
        LocalCutoutErrorCode.unsupported: LocalCutoutFallbackReason.unsupportedOs,
        LocalCutoutErrorCode.missingPlayServices:
            LocalCutoutFallbackReason.missingGooglePlayServices,
        LocalCutoutErrorCode.modelNotInstalled:
            LocalCutoutFallbackReason.modelNotInstalled,
        LocalCutoutErrorCode.modelDownloadFailed:
            LocalCutoutFallbackReason.modelDownloadFailed,
        LocalCutoutErrorCode.noSubject: LocalCutoutFallbackReason.noSubjectFound,
        LocalCutoutErrorCode.invalidOutput: LocalCutoutFallbackReason.invalidOutput,
        LocalCutoutErrorCode.timeout: LocalCutoutFallbackReason.timeout,
        LocalCutoutErrorCode.cancelled: LocalCutoutFallbackReason.cancelled,
        LocalCutoutErrorCode.busy: LocalCutoutFallbackReason.temporarilyUnavailable,
        LocalCutoutErrorCode.cacheUnavailable:
            LocalCutoutFallbackReason.temporarilyUnavailable,
        LocalCutoutErrorCode.internal: LocalCutoutFallbackReason.nativeError,
      };
      cases.forEach((code, reason) {
        expect(LocalCutoutErrorCode.toFallbackReason(code), reason, reason: code);
      });
    });

    test('an unknown or null code is a generic native error, never a crash', () {
      expect(
        LocalCutoutErrorCode.toFallbackReason('brand_new_code'),
        LocalCutoutFallbackReason.nativeError,
      );
      expect(
        LocalCutoutErrorCode.toFallbackReason(null),
        LocalCutoutFallbackReason.nativeError,
      );
    });

    test('availability maps onto the matching fallback reason', () {
      expect(
        fallbackReasonFor(LocalCutoutAvailability.unsupportedOs),
        LocalCutoutFallbackReason.unsupportedOs,
      );
      expect(
        fallbackReasonFor(LocalCutoutAvailability.missingGooglePlayServices),
        LocalCutoutFallbackReason.missingGooglePlayServices,
      );
      expect(
        fallbackReasonFor(LocalCutoutAvailability.modelDownloadFailed),
        LocalCutoutFallbackReason.modelDownloadFailed,
      );
    });
  });

  group('analytics fields carry no identifying data', () {
    test('values are buckets, not raw measurements', () {
      final fields = LocalCutoutMetrics(
        width: 1600,
        height: 1200,
        subjectCount: 3,
        foregroundAreaRatio: 0.42,
        borderForegroundRatio: 0.02,
        uncertainPixelRatio: 0.30,
        meanForegroundConfidence: 0.9,
      ).toAnalyticsFields();

      expect(fields['subject_count'], 3);
      expect(fields['foreground_area_bucket'], '25-50');
      expect(fields['uncertain_pixel_bucket'], '25-50');
      expect(fields['border_contact_bucket'], '0-5');
      expect(fields['size_bucket'], 'le1600');
      // No raw pixel dimensions, no paths, no ids.
      expect(fields.keys, isNot(contains('width')));
      expect(fields.keys, isNot(contains('height')));
    });

    test('subject count is clamped so a runaway value cannot fingerprint', () {
      final fields = LocalCutoutMetrics(
        width: 100,
        height: 100,
        subjectCount: 5000,
        foregroundAreaRatio: 0.99,
        borderForegroundRatio: 0.99,
        uncertainPixelRatio: 0.0,
        meanForegroundConfidence: 1.0,
      ).toAnalyticsFields();

      expect(fields['subject_count'], 10);
      expect(fields['foreground_area_bucket'], '95-100');
      expect(fields['size_bucket'], 'le800');
    });
  });

  group('UnsupportedLocalCutoutPlatform', () {
    test('reports unsupported and never throws on the no-op methods', () async {
      const platform = UnsupportedLocalCutoutPlatform();
      expect((await platform.capability()).isAvailable, isFalse);
      expect(
        (await platform.prepare(timeout: const Duration(seconds: 1))).isAvailable,
        isFalse,
      );
      await platform.cancel('op');
      await platform.cleanup('op');
      expect(await platform.sweepCache(maxAge: const Duration(hours: 1)), 0);
    });

    test('removeBackground throws the typed unsupported failure', () async {
      const platform = UnsupportedLocalCutoutPlatform();
      await expectLater(
        platform.removeBackground(
          imageBytes: Uint8List(0),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(
          isA<LocalCutoutPlatformException>().having(
            (e) => e.reason,
            'reason',
            LocalCutoutFallbackReason.unsupportedOs,
          ),
        ),
      );
    });
  });
}
