import 'dart:ui' show Rect;

import 'package:app/features/wardrobe/local_cutout/local_cutout_models.dart';
import 'package:app/features/wardrobe/local_cutout/local_cutout_quality_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_cutout_fakes.dart';

/// The quality policy (local BG §5).
///
/// The central tension these tests encode: hard rejection costs the user ~90 s in
/// the cloud fallback, so it is reserved for structurally broken output. Lace,
/// chiffon, thin straps and edge-touching garments must be ACCEPTED with a
/// warning — rejecting them would quietly undo the entire point of going local.
void main() {
  const policy = kDefaultLocalCutoutQualityPolicy;
  const width = 1600;
  const height = 1200;

  LocalCutoutQualityVerdict judge(LocalCutoutMetrics metrics) =>
      policy.evaluate(metrics, sourceWidth: width, sourceHeight: height);

  group('accepts good output', () {
    test('a clean flat-lay passes with no warnings', () {
      final verdict = judge(fakeMetrics());
      expect(verdict.isAccepted, isTrue);
      expect(verdict.rejection, isNull);
      expect(verdict.warnings, isEmpty);
      expect(verdict.hasWarnings, isFalse);
    });

    test('the shipped thresholds are the conservative ones from the spec', () {
      expect(policy.minForegroundAreaRatio, 0.01);
      expect(policy.maxForegroundAreaRatio, 0.995);
      expect(policy.minSubjectCount, 1);
    });
  });

  group('hard rejection — structural failure only', () {
    test('mask dimensions must match the source exactly', () {
      final verdict = judge(fakeMetrics(width: 1599));
      expect(verdict.isAccepted, isFalse);
      expect(verdict.rejection, LocalCutoutFallbackReason.invalidOutput);
      // A rejection never carries warnings — it is not a partial result.
      expect(verdict.warnings, isEmpty);
    });

    test('a zero-dimension source is rejected', () {
      final verdict = policy.evaluate(
        fakeMetrics(),
        sourceWidth: 0,
        sourceHeight: height,
      );
      expect(verdict.rejection, LocalCutoutFallbackReason.invalidOutput);
    });

    test('NaN or infinite metrics are rejected', () {
      expect(
        judge(fakeMetrics(foregroundAreaRatio: double.nan)).rejection,
        LocalCutoutFallbackReason.invalidOutput,
      );
      expect(
        judge(fakeMetrics(uncertainPixelRatio: double.infinity)).rejection,
        LocalCutoutFallbackReason.invalidOutput,
      );
    });

    test('no subject is its own reason, distinct from a quality rejection', () {
      final verdict = judge(fakeMetrics(subjectCount: 0));
      expect(verdict.rejection, LocalCutoutFallbackReason.noSubjectFound);
    });

    test('an effectively empty mask is rejected', () {
      expect(
        judge(fakeMetrics(foregroundAreaRatio: 0.001)).rejection,
        LocalCutoutFallbackReason.qualityRejected,
      );
    });

    test('a mask covering essentially the whole frame is rejected', () {
      expect(
        judge(fakeMetrics(foregroundAreaRatio: 0.999)).rejection,
        LocalCutoutFallbackReason.qualityRejected,
      );
    });

    test('the area bounds are inclusive at both ends', () {
      expect(judge(fakeMetrics(foregroundAreaRatio: 0.01)).isAccepted, isTrue);
      expect(judge(fakeMetrics(foregroundAreaRatio: 0.995)).isAccepted, isTrue);
      expect(
        judge(fakeMetrics(foregroundAreaRatio: 0.0099)).isAccepted,
        isFalse,
      );
      expect(
        judge(fakeMetrics(foregroundAreaRatio: 0.9951)).isAccepted,
        isFalse,
      );
    });
  });

  group('soft warnings — accepted and observed, never rejected', () {
    test('lace/chiffon (high uncertain-pixel ratio) is KEPT', () {
      final verdict = judge(fakeMetrics(uncertainPixelRatio: 0.6));
      expect(verdict.isAccepted, isTrue);
      expect(
        verdict.warnings,
        contains(LocalCutoutQualityWarning.highUncertainty),
      );
    });

    test('a garment touching the frame edge is KEPT', () {
      final verdict = judge(fakeMetrics(borderForegroundRatio: 0.8));
      expect(verdict.isAccepted, isTrue);
      expect(
        verdict.warnings,
        contains(LocalCutoutQualityWarning.highBorderContact),
      );
    });

    test('many separate subjects is a warning, not a rejection', () {
      final verdict = judge(fakeMetrics(subjectCount: 9));
      expect(verdict.isAccepted, isTrue);
      expect(
        verdict.warnings,
        contains(LocalCutoutQualityWarning.manySubjects),
      );
    });

    test('low engine confidence is a warning, not a rejection', () {
      final verdict = judge(fakeMetrics(meanForegroundConfidence: 0.2));
      expect(verdict.isAccepted, isTrue);
      expect(
        verdict.warnings,
        contains(LocalCutoutQualityWarning.lowConfidence),
      );
    });

    test('a tiny subject bounding box is a warning', () {
      final verdict = judge(
        fakeMetrics(foregroundBounds: const Rect.fromLTRB(0, 0, 40, 40)),
      );
      expect(verdict.isAccepted, isTrue);
      expect(
        verdict.warnings,
        contains(LocalCutoutQualityWarning.smallSubject),
      );
    });

    test('a comfortably large bounding box raises nothing', () {
      final verdict = judge(
        fakeMetrics(
          foregroundBounds: const Rect.fromLTRB(100, 100, 1400, 1100),
        ),
      );
      expect(verdict.warnings, isEmpty);
    });

    test('absent bounds cannot raise the small-subject warning', () {
      expect(judge(fakeMetrics()).warnings, isEmpty);
    });

    test(
      'warnings accumulate and expose stable sorted names for analytics',
      () {
        final verdict = judge(
          fakeMetrics(
            subjectCount: 9,
            borderForegroundRatio: 0.9,
            uncertainPixelRatio: 0.9,
            meanForegroundConfidence: 0.1,
          ),
        );
        expect(verdict.isAccepted, isTrue);
        expect(verdict.warnings.length, 4);
        expect(verdict.warningNames, [
          'highBorderContact',
          'highUncertainty',
          'lowConfidence',
          'manySubjects',
        ]);
      },
    );
  });

  group('thresholds are injectable', () {
    test(
      'a stricter policy can be constructed without touching the default',
      () {
        const strict = LocalCutoutQualityPolicy(
          minForegroundAreaRatio: 0.30,
          softMaxUncertainPixelRatio: 0.01,
        );
        final metrics = fakeMetrics(
          foregroundAreaRatio: 0.2,
          uncertainPixelRatio: 0.5,
        );

        expect(
          strict
              .evaluate(metrics, sourceWidth: width, sourceHeight: height)
              .rejection,
          LocalCutoutFallbackReason.qualityRejected,
        );
        // The shipped default is unchanged by that construction.
        expect(judge(metrics).isAccepted, isTrue);
      },
    );
  });
}
