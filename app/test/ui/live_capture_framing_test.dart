import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/mirror/capture/live_capture_framing.dart';

/// The capture rules and the capture CLOCK, tested apart from the camera.
///
/// The framing evaluator is pure, so it is exercised as a table. The timing —
/// "valid for a second, then 3-2-1, then exactly one shutter, and cancel the
/// moment they step out" — runs on an injected clock, so six seconds of real
/// waiting per case becomes a few microseconds and nothing here is flaky.
void main() {
  /// A well-framed standing person: head near the top, ankles near the bottom,
  /// everything comfortably inside the side margins.
  FramingPose goodPose({
    double headY = 0.08,
    double ankleY = 0.94,
    double x = 0.5,
    double likelihood = 0.9,
  }) => FramingPose(
    head: FramingLandmark(x, headY, likelihood),
    leftShoulder: FramingLandmark(x - 0.07, headY + 0.08, likelihood),
    rightShoulder: FramingLandmark(x + 0.07, headY + 0.08, likelihood),
    leftHip: FramingLandmark(x - 0.05, 0.5, likelihood),
    rightHip: FramingLandmark(x + 0.05, 0.5, likelihood),
    leftKnee: FramingLandmark(x - 0.05, 0.72, likelihood),
    rightKnee: FramingLandmark(x + 0.05, 0.72, likelihood),
    leftAnkle: FramingLandmark(x - 0.04, ankleY, likelihood),
    rightAnkle: FramingLandmark(x + 0.04, ankleY, likelihood),
  );

  LiveFramingCheck check(
    FramingPose? pose, {
    int people = 1,
    FrameQuality quality = FrameQuality.unknown,
  }) => evaluateFraming(
    personCount: pose == null ? 0 : people,
    pose: pose,
    quality: quality,
  );

  group('framing rules', () {
    test('a well-framed single person passes and carries a score', () {
      final result = check(goodPose());
      expect(result.ok, isTrue);
      expect(result.issue, LiveFramingIssue.none);
      expect(result.score, greaterThan(80));
    });

    test('an empty frame asks the user to step in', () {
      expect(check(null).issue, LiveFramingIssue.noPerson);
    });

    test('two people is refused — a try-on body must be unambiguous', () {
      expect(
        check(goodPose(), people: 2).issue,
        LiveFramingIssue.multiplePeople,
      );
    });

    test('a dark room is reported before any geometry complaint', () {
      // The head is ALSO out of frame here. Lighting still wins, because a
      // landmark measured off an unusable frame is a guess.
      final result = check(
        goodPose(headY: 0.0),
        quality: const FrameQuality(luminance: 0.05, sharpness: 1),
      );
      expect(result.issue, LiveFramingIssue.poorLighting);
    });

    test('a blown-out frame is also poor lighting', () {
      expect(
        check(
          goodPose(),
          quality: const FrameQuality(luminance: 0.98, sharpness: 1),
        ).issue,
        LiveFramingIssue.poorLighting,
      );
    });

    test('a smeared frame is refused as blurry', () {
      expect(
        check(
          goodPose(),
          quality: const FrameQuality(luminance: 0.5, sharpness: 0.01),
        ).issue,
        LiveFramingIssue.blurry,
      );
    });

    test('a head above the top edge is refused', () {
      expect(
        check(goodPose(headY: 0.005)).issue,
        LiveFramingIssue.headOutOfFrame,
      );
    });

    test('a head the detector cannot find is refused', () {
      final pose = FramingPose(
        head: const FramingLandmark(0.5, 0.08, 0.1), // below minLikelihood
        leftShoulder: const FramingLandmark(0.43, 0.16, 0.9),
        leftHip: const FramingLandmark(0.45, 0.5, 0.9),
        leftKnee: const FramingLandmark(0.45, 0.72, 0.9),
        leftAnkle: const FramingLandmark(0.46, 0.94, 0.9),
      );
      expect(check(pose).issue, LiveFramingIssue.headOutOfFrame);
    });

    test('feet below the bottom edge are refused', () {
      expect(
        check(goodPose(ankleY: 0.995)).issue,
        LiveFramingIssue.feetOutOfFrame,
      );
    });

    test('no ankles at all is refused', () {
      const pose = FramingPose(
        head: FramingLandmark(0.5, 0.08, 0.9),
        leftShoulder: FramingLandmark(0.43, 0.16, 0.9),
        leftHip: FramingLandmark(0.45, 0.5, 0.9),
        leftKnee: FramingLandmark(0.45, 0.72, 0.9),
      );
      expect(check(pose).issue, LiveFramingIssue.feetOutOfFrame);
    });

    test('missing knees is not a full body', () {
      const pose = FramingPose(
        head: FramingLandmark(0.5, 0.08, 0.9),
        leftShoulder: FramingLandmark(0.43, 0.16, 0.9),
        leftHip: FramingLandmark(0.45, 0.5, 0.9),
        leftAnkle: FramingLandmark(0.46, 0.94, 0.9),
      );
      expect(check(pose).issue, LiveFramingIssue.bodyOutOfFrame);
    });

    test('a body against the side edge is asked to centre', () {
      expect(
        check(goodPose(x: 0.05)).issue,
        LiveFramingIssue.bodyOutOfFrame,
      );
    });

    test('a small figure is told to come closer', () {
      expect(
        check(goodPose(headY: 0.30, ankleY: 0.60)).issue,
        LiveFramingIssue.tooFar,
      );
    });

    test('a figure filling the frame edge to edge is told to step back', () {
      // Inside the edge margins — so the head/feet checks pass — but filling
      // more of the frame than the extent ceiling allows.
      expect(
        check(goodPose(headY: 0.03, ankleY: 0.96)).issue,
        LiveFramingIssue.tooClose,
      );
    });
  });

  group('auto-capture timing', () {
    /// A clock the test advances by hand.
    late DateTime now;
    late AutoCaptureTracker tracker;

    setUp(() {
      now = DateTime(2026, 8, 28, 12);
      tracker = AutoCaptureTracker(clock: () => now);
    });

    void advance(Duration d) => now = now.add(d);

    const good = LiveFramingCheck(LiveFramingIssue.none, score: 90);
    const bad = LiveFramingCheck(LiveFramingIssue.noPerson);

    test('a bad frame never starts anything', () {
      expect(tracker.update(bad), AutoCapturePhase.waiting);
      advance(const Duration(seconds: 10));
      expect(tracker.update(bad), AutoCapturePhase.waiting);
      expect(tracker.fired, isFalse);
    });

    test('valid framing HOLDS before it counts', () {
      expect(tracker.update(good), AutoCapturePhase.holding);
      advance(const Duration(milliseconds: 400));
      expect(tracker.update(good), AutoCapturePhase.holding);
      expect(tracker.countdown, isNull);
    });

    test('one second of valid framing starts the countdown at 3', () {
      tracker.update(good);
      advance(LiveFramingRules.stableFor);
      expect(tracker.update(good), AutoCapturePhase.countingDown);
      expect(tracker.countdown, 3);
    });

    test('the countdown steps 3 -> 2 -> 1 and then fires', () {
      tracker.update(good);
      advance(LiveFramingRules.stableFor);
      expect(tracker.update(good), AutoCapturePhase.countingDown);
      expect(tracker.countdown, 3);

      advance(const Duration(seconds: 1));
      expect(tracker.update(good), AutoCapturePhase.countingDown);
      expect(tracker.countdown, 2);

      advance(const Duration(seconds: 1));
      expect(tracker.update(good), AutoCapturePhase.countingDown);
      expect(tracker.countdown, 1);

      advance(const Duration(seconds: 1));
      expect(tracker.update(good), AutoCapturePhase.capture);
      expect(tracker.fired, isTrue);
    });

    test('stepping out of frame CANCELS the countdown outright', () {
      tracker.update(good);
      advance(LiveFramingRules.stableFor);
      tracker.update(good);
      expect(tracker.countdown, 3);

      // Gone.
      expect(tracker.update(bad), AutoCapturePhase.waiting);
      expect(tracker.countdown, isNull);

      // Coming back does not resume at 2 — it starts the hold over, which is
      // the only cadence the user can predict.
      advance(const Duration(milliseconds: 200));
      expect(tracker.update(good), AutoCapturePhase.holding);
      expect(tracker.countdown, isNull);
    });

    test('the shutter latches — later frames cannot fire a second capture', () {
      tracker.update(good); // hold begins
      advance(LiveFramingRules.stableFor);
      tracker.update(good); // countdown begins
      advance(
        LiveFramingRules.countdownTick * LiveFramingRules.countdownFrom,
      );
      expect(tracker.update(good), AutoCapturePhase.capture);

      // The preview does not stop for the still, so frames keep arriving.
      for (var i = 0; i < 20; i++) {
        advance(const Duration(milliseconds: 33));
        expect(tracker.update(good), AutoCapturePhase.capture);
      }
      // And a bad frame after firing cannot un-fire it either.
      expect(tracker.update(bad), AutoCapturePhase.capture);
      expect(tracker.fired, isTrue);
    });

    test('reset returns it to square one for a retake', () {
      tracker.update(good);
      advance(LiveFramingRules.stableFor);
      tracker.update(good);
      advance(
        LiveFramingRules.countdownTick * LiveFramingRules.countdownFrom,
      );
      tracker.update(good);
      expect(tracker.fired, isTrue);

      tracker.reset();
      expect(tracker.fired, isFalse);
      expect(tracker.countdown, isNull);
      expect(tracker.update(good), AutoCapturePhase.holding);
    });
  });

  group('stand-back distance adapts to the preview geometry', () {
    test('a 4:3 front camera asks for a plausible full-body distance', () {
      final d = recommendedStandBack(4 / 3);
      expect(d.near, greaterThanOrEqualTo(1.5));
      expect(d.far, greaterThan(d.near));
      expect(d.far, lessThanOrEqualTo(5.0));
    });

    test('a taller (16:9) preview lets the user stand closer than a 4:3 one', () {
      // More vertical coverage per metre => less distance needed.
      expect(
        recommendedStandBack(16 / 9).near,
        lessThanOrEqualTo(recommendedStandBack(4 / 3).near),
      );
    });

    test('the label is a readable range, not a false precision', () {
      final label = standBackLabel(4 / 3);
      expect(label, contains('–')); // en dash
      expect(label, isNot(contains('.13')));
    });

    test('an absurd aspect ratio cannot produce absurd advice', () {
      for (final ratio in [0.0, -3.0, 0.01, 100.0]) {
        final d = recommendedStandBack(ratio);
        expect(d.near, inInclusiveRange(1.5, 4.0), reason: '$ratio');
        expect(d.far, inInclusiveRange(2.0, 5.0), reason: '$ratio');
      }
    });
  });

  group('frame quality is measured from pixels, not assumed', () {
    Uint8List bgra(int w, int h, int Function(int x, int y) luma) {
      final bytes = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final v = luma(x, y);
          bytes[i] = v; // B
          bytes[i + 1] = v; // G
          bytes[i + 2] = v; // R
          bytes[i + 3] = 255;
        }
      }
      return bytes;
    }

    test('a black frame reads as dark', () {
      final q = measureBgraQuality(bgra(64, 64, (_, _) => 0), 64, 64);
      expect(q.luminance, lessThan(LiveFramingRules.minLuminance));
    });

    test('a white frame reads as blown out', () {
      final q = measureBgraQuality(bgra(64, 64, (_, _) => 255), 64, 64);
      expect(q.luminance, greaterThan(LiveFramingRules.maxLuminance));
    });

    test('a flat mid-grey frame reads as unsharp', () {
      final q = measureBgraQuality(bgra(64, 64, (_, _) => 128), 64, 64);
      expect(q.luminance, closeTo(0.5, 0.05));
      expect(q.sharpness, lessThan(LiveFramingRules.minSharpness));
    });

    test('a high-contrast frame reads as sharp', () {
      final q = measureBgraQuality(
        bgra(64, 64, (x, _) => x.isEven ? 20 : 235),
        64,
        64,
      );
      expect(q.sharpness, greaterThan(LiveFramingRules.minSharpness));
    });

    test('a degenerate buffer falls back rather than throwing', () {
      expect(
        measureBgraQuality(Uint8List(0), 0, 0).luminance,
        FrameQuality.unknown.luminance,
      );
    });
  });
}
