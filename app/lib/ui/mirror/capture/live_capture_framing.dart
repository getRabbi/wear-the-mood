import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Why a live preview frame is not yet good enough to capture from.
///
/// Ordered by what the user should fix FIRST: there is no point telling
/// somebody their knees are cropped when the room is too dark to find them.
/// [LiveFramingCheck.issue] returns the single most important one, because a
/// list of four complaints on a live preview is unreadable from three metres
/// away — which is exactly where the user is standing.
enum LiveFramingIssue {
  /// Nothing person-shaped in frame at all.
  noPerson,

  /// More than one person — a try-on body must be unambiguous.
  multiplePeople,

  /// Too dark (or blown out) to detect or to render from.
  poorLighting,

  /// Motion blur / out of focus.
  blurry,

  /// Head above the top edge, or not detected.
  headOutOfFrame,

  /// Feet below the bottom edge, or not detected.
  feetOutOfFrame,

  /// Torso landmarks present but too close to a side edge.
  bodyOutOfFrame,

  /// The person fills too little of the guide — they are too far away.
  tooFar,

  /// The person overflows the guide — they are too close.
  tooClose,

  /// Everything is right; hold still.
  none,
}

/// One landmark's normalized position in the preview, plus how sure we are.
///
/// Normalized (0..1 across the preview) rather than pixels so the whole
/// evaluator is resolution-, device- and orientation-independent — an iPhone
/// 15 preview, an iPad Air preview and a synthetic test fixture all speak the
/// same units, which is what makes this file unit-testable without a camera.
@immutable
class FramingLandmark {
  const FramingLandmark(this.x, this.y, this.likelihood);

  final double x;
  final double y;
  final double likelihood;

  bool get confident => likelihood >= LiveFramingRules.minLikelihood;
}

/// The landmarks the full-body check needs. Named rather than a map keyed by
/// ML Kit's enum so this file has no plugin import and can run on the test VM.
@immutable
class FramingPose {
  const FramingPose({
    this.head,
    this.leftShoulder,
    this.rightShoulder,
    this.leftHip,
    this.rightHip,
    this.leftKnee,
    this.rightKnee,
    this.leftAnkle,
    this.rightAnkle,
  });

  final FramingLandmark? head;
  final FramingLandmark? leftShoulder;
  final FramingLandmark? rightShoulder;
  final FramingLandmark? leftHip;
  final FramingLandmark? rightHip;
  final FramingLandmark? leftKnee;
  final FramingLandmark? rightKnee;
  final FramingLandmark? leftAnkle;
  final FramingLandmark? rightAnkle;

  Iterable<FramingLandmark?> get _all => [
    head,
    leftShoulder,
    rightShoulder,
    leftHip,
    rightHip,
    leftKnee,
    rightKnee,
    leftAnkle,
    rightAnkle,
  ];

  /// Mean confidence over the landmarks that matter — the same 0–100 shape the
  /// shipped [PoseValidator.scoreFrom] produces, so the gallery badge keeps
  /// meaning the same thing whether the shot came from a picker or from here.
  int get score {
    final values = _all.map((l) => l?.likelihood ?? 0.0).toList();
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    return (mean * 100).round().clamp(0, 100);
  }
}

/// A frame's non-pose qualities, measured from the pixels rather than inferred.
@immutable
class FrameQuality {
  const FrameQuality({required this.luminance, required this.sharpness});

  /// Mean luminance, 0..1.
  final double luminance;

  /// Normalized high-frequency energy, 0..1. Higher is sharper.
  final double sharpness;

  /// Used where a caller has no pixel access (widget tests, the timer path):
  /// assume the frame is fine and let the pose rules decide alone.
  static const unknown = FrameQuality(luminance: 0.5, sharpness: 1);
}

/// The thresholds, in one place so a device tuning pass is a diff to one file.
abstract final class LiveFramingRules {
  /// In-frame likelihood below which a landmark is "not visible". Matches the
  /// shipped [PoseValidator] so the live check and the post-capture check
  /// cannot disagree about the same body.
  static const minLikelihood = 0.5;

  /// Margins (fractions of the preview) a landmark must stay inside.
  static const topMargin = 0.02;
  static const bottomMargin = 0.02;
  static const sideMargin = 0.02;

  /// Head-to-ankle extent as a fraction of preview height. Below the floor the
  /// person is too far to render usefully; above the ceiling they are so close
  /// that head or feet are about to leave.
  ///
  /// The ceiling has to sit BELOW what the edge margins already allow, or it
  /// can never be reached: with a 2% margin top and bottom the largest extent
  /// that survives the head/feet checks is 0.96, so a ceiling of 0.97 would
  /// have made "step back" unreachable and let somebody frame themselves right
  /// up against both edges — one small sway from a cropped render. 0.90 leaves
  /// the warning a real band to fire in, and still calls a body filling 45-90%
  /// of the frame well framed.
  static const minBodyExtent = 0.45;
  static const maxBodyExtent = 0.90;

  /// Usable exposure window.
  static const minLuminance = 0.18;
  static const maxLuminance = 0.92;

  /// Below this the frame is motion-blurred or out of focus.
  static const minSharpness = 0.12;

  /// How long framing must stay valid before the countdown starts.
  static const stableFor = Duration(milliseconds: 1000);

  /// The countdown itself: 3 … 2 … 1.
  static const countdownFrom = 3;
  static const countdownTick = Duration(seconds: 1);

  /// The solo fallback: place the device, then step in.
  static const timerFallback = Duration(seconds: 10);
}

/// The verdict on one preview frame.
@immutable
class LiveFramingCheck {
  const LiveFramingCheck(this.issue, {this.score = 0});

  final LiveFramingIssue issue;

  /// Pose confidence 0–100, carried through so a successful capture can store
  /// the same quality badge the picker path stores.
  final int score;

  bool get ok => issue == LiveFramingIssue.none;

  @override
  bool operator ==(Object other) =>
      other is LiveFramingCheck && other.issue == issue && other.score == score;

  @override
  int get hashCode => Object.hash(issue, score);

  @override
  String toString() => 'LiveFramingCheck(${issue.name}, score: $score)';
}

/// Decide whether a preview frame is ready to capture from.
///
/// Pure: same inputs, same answer, no clock, no camera, no ML Kit. Everything
/// stateful about auto-capture lives in [AutoCaptureTracker] instead, so the
/// rules can be exhaustively tested as a table and the timing can be tested
/// with a fake clock.
///
/// [poses] is the count of detected people; [pose] is the most prominent one.
LiveFramingCheck evaluateFraming({
  required int personCount,
  required FramingPose? pose,
  FrameQuality quality = FrameQuality.unknown,
}) {
  if (personCount == 0 || pose == null) {
    return const LiveFramingCheck(LiveFramingIssue.noPerson);
  }
  if (personCount > 1) {
    return const LiveFramingCheck(LiveFramingIssue.multiplePeople);
  }

  // Exposure and focus come before geometry: a landmark position measured off
  // a dark or smeared frame is a guess, and acting on a guess is how the
  // countdown fires at the wrong moment.
  if (quality.luminance < LiveFramingRules.minLuminance ||
      quality.luminance > LiveFramingRules.maxLuminance) {
    return const LiveFramingCheck(LiveFramingIssue.poorLighting);
  }
  if (quality.sharpness < LiveFramingRules.minSharpness) {
    return const LiveFramingCheck(LiveFramingIssue.blurry);
  }

  bool has(FramingLandmark? l) => l != null && l.confident;

  final head = pose.head;
  if (!has(head)) {
    return const LiveFramingCheck(LiveFramingIssue.headOutOfFrame);
  }
  if (head!.y < LiveFramingRules.topMargin) {
    return const LiveFramingCheck(LiveFramingIssue.headOutOfFrame);
  }

  final ankles = [
    pose.leftAnkle,
    pose.rightAnkle,
  ].where(has).cast<FramingLandmark>().toList();
  if (ankles.isEmpty) {
    return const LiveFramingCheck(LiveFramingIssue.feetOutOfFrame);
  }
  final lowest = ankles.map((a) => a.y).reduce(math.max);
  if (lowest > 1 - LiveFramingRules.bottomMargin) {
    return const LiveFramingCheck(LiveFramingIssue.feetOutOfFrame);
  }

  // Shoulders, hips and knees must all be present: "full body" is the whole
  // point, and a shot missing the knees renders a garment onto nothing.
  final torso = <FramingLandmark?>[
    pose.leftShoulder,
    pose.rightShoulder,
    pose.leftHip,
    pose.rightHip,
    pose.leftKnee,
    pose.rightKnee,
  ];
  if (!torso.any(has)) {
    return const LiveFramingCheck(LiveFramingIssue.noPerson);
  }
  final shouldersOk = has(pose.leftShoulder) || has(pose.rightShoulder);
  final hipsOk = has(pose.leftHip) || has(pose.rightHip);
  final kneesOk = has(pose.leftKnee) || has(pose.rightKnee);
  if (!shouldersOk || !hipsOk || !kneesOk) {
    return const LiveFramingCheck(LiveFramingIssue.bodyOutOfFrame);
  }

  final present = [
    head,
    ...torso.where(has).cast<FramingLandmark>(),
    ...ankles,
  ];
  final minX = present.map((l) => l.x).reduce(math.min);
  final maxX = present.map((l) => l.x).reduce(math.max);
  if (minX < LiveFramingRules.sideMargin ||
      maxX > 1 - LiveFramingRules.sideMargin) {
    return const LiveFramingCheck(LiveFramingIssue.bodyOutOfFrame);
  }

  final extent = lowest - head.y;
  if (extent < LiveFramingRules.minBodyExtent) {
    return const LiveFramingCheck(LiveFramingIssue.tooFar);
  }
  if (extent > LiveFramingRules.maxBodyExtent) {
    return const LiveFramingCheck(LiveFramingIssue.tooClose);
  }

  return LiveFramingCheck(LiveFramingIssue.none, score: pose.score);
}

/// What the capture screen should be doing right now.
enum AutoCapturePhase {
  /// Framing is not valid — show the issue, no countdown.
  waiting,

  /// Framing has been valid but not yet long enough to commit.
  holding,

  /// Counting down; [AutoCaptureTracker.countdown] is 3, 2 or 1.
  countingDown,

  /// Fire the shutter exactly once.
  capture,
}

/// The STATEFUL half of auto-capture: how long framing has held, whether a
/// countdown is running, and whether it is time to fire.
///
/// Separated from [evaluateFraming] and driven by an injected clock so the
/// whole timing contract — "valid for a second, then 3-2-1, then exactly one
/// capture, and cancel the moment the user steps out" — is testable without
/// waiting six real seconds per case.
///
/// [fired] latches. Nothing resets it but [reset], which is what makes a
/// duplicate capture impossible even if frames keep arriving after the shutter
/// (they do — the preview does not stop for the still).
class AutoCaptureTracker {
  AutoCaptureTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  DateTime? _validSince;
  DateTime? _countdownStart;
  bool _fired = false;

  /// True once [update] has returned [AutoCapturePhase.capture]. Latched.
  bool get fired => _fired;

  /// 3, 2, 1 while counting down; null otherwise.
  int? get countdown {
    final start = _countdownStart;
    if (start == null || _fired) return null;
    final elapsed = _clock().difference(start);
    final remaining =
        LiveFramingRules.countdownFrom -
        (elapsed.inMilliseconds ~/ LiveFramingRules.countdownTick.inMilliseconds);
    return remaining.clamp(0, LiveFramingRules.countdownFrom);
  }

  /// Feed one frame's verdict; get back what the UI should do.
  AutoCapturePhase update(LiveFramingCheck check) {
    if (_fired) return AutoCapturePhase.capture;

    if (!check.ok) {
      // Leaving the frame cancels a running countdown outright rather than
      // pausing it. A countdown that resumes where it left off would fire at a
      // moment the user has no way to predict, which is worse than starting
      // over — and starting over is cheap, it costs one second of holding.
      _validSince = null;
      _countdownStart = null;
      return AutoCapturePhase.waiting;
    }

    final now = _clock();
    _validSince ??= now;

    if (_countdownStart == null) {
      if (now.difference(_validSince!) < LiveFramingRules.stableFor) {
        return AutoCapturePhase.holding;
      }
      _countdownStart = now;
      return AutoCapturePhase.countingDown;
    }

    final elapsed = now.difference(_countdownStart!);
    if (elapsed >=
        LiveFramingRules.countdownTick * LiveFramingRules.countdownFrom) {
      _fired = true;
      return AutoCapturePhase.capture;
    }
    return AutoCapturePhase.countingDown;
  }

  /// Back to square one — used by Retake and when the camera restarts.
  void reset() {
    _validSince = null;
    _countdownStart = null;
    _fired = false;
  }
}

/// Mean luminance + a cheap focus measure, sampled from a BGRA8888 preview
/// frame (the iOS format; this flow is iOS-only).
///
/// Sparse on purpose. A full-frame Laplacian in Dart at 30fps would cost more
/// than the pose detector it is guarding, so this walks a coarse grid: enough
/// signal to tell a dark room from a lit one and a smeared frame from a still
/// one, at a fraction of the cost. It is a capture-QUALITY check, not a
/// measurement anybody downstream depends on.
FrameQuality measureBgraQuality(
  Uint8List bytes,
  int width,
  int height, {
  int gridSteps = 48,
}) {
  if (width <= 1 || height <= 1 || bytes.length < 4) {
    return FrameQuality.unknown;
  }
  final stepX = math.max(1, width ~/ gridSteps);
  final stepY = math.max(1, height ~/ gridSteps);
  final bytesPerRow = bytes.length ~/ height;

  var sum = 0.0;
  var count = 0;
  var gradient = 0.0;
  var gradientCount = 0;
  double? previousInRow;

  for (var y = 0; y + stepY < height; y += stepY) {
    previousInRow = null;
    for (var x = 0; x + stepX < width; x += stepX) {
      final i = y * bytesPerRow + x * 4;
      if (i + 2 >= bytes.length) continue;
      // BGRA: Rec. 601 luma from the first three channels.
      final luma =
          (0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2]) /
          255.0;
      sum += luma;
      count++;
      if (previousInRow != null) {
        gradient += (luma - previousInRow).abs();
        gradientCount++;
      }
      previousInRow = luma;
    }
  }
  if (count == 0) return FrameQuality.unknown;

  final mean = sum / count;
  // Scaled so an ordinary in-focus indoor frame lands near 1 and a smeared one
  // falls under the threshold. Clamped because this is a gate, not a metric.
  final sharpness = gradientCount == 0
      ? 1.0
      : ((gradient / gradientCount) * 12).clamp(0.0, 1.0);
  return FrameQuality(luminance: mean, sharpness: sharpness);
}

/// The stand-back distance to print on the preparation screen, in metres.
///
/// A lens's true field of view is not something `camera` exposes, so this uses
/// the one piece of FOV information that IS available: the preview's aspect
/// ratio. Held in portrait, the frame's vertical extent maps to the sensor's
/// long axis, so a 16:9 preview covers more of a standing body per metre than
/// a 4:3 one and the user can stand closer.
///
/// Derived from the pinhole relation d = h / (2 tan(fov/2)) for a nominal
/// 1.75 m person, with the guide's own headroom folded in, then rounded to
/// half a metre — because "2.13 m" is a false precision to shout at somebody
/// across a room. Returns (near, far) so the copy can offer a range.
({double near, double far}) recommendedStandBack(double previewAspectRatio) {
  // Portrait vertical FOV, estimated from how tall the frame is relative to
  // its width. Clamped to the range real front cameras actually occupy so an
  // absurd aspect ratio cannot produce absurd advice.
  final portraitRatio = previewAspectRatio <= 0
      ? 4 / 3
      : (previewAspectRatio < 1 ? 1 / previewAspectRatio : previewAspectRatio);
  final verticalFovDegrees = (44.0 + (portraitRatio - 1.333) * 18.0).clamp(
    40.0,
    68.0,
  );
  final halfFov = verticalFovDegrees * math.pi / 360;
  // 1.75 m person plus ~15% headroom so the guide is not filled to the edges.
  final ideal = (1.75 * 1.15) / (2 * math.tan(halfFov));
  double round(double v) => (v * 2).roundToDouble() / 2;
  return (near: round(ideal).clamp(1.5, 4.0), far: round(ideal + 1).clamp(2.0, 5.0));
}

/// The distance range as it appears in the preparation copy, e.g. "2-3".
String standBackLabel(double previewAspectRatio) {
  final d = recommendedStandBack(previewAspectRatio);
  String fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${fmt(d.near)}–${fmt(d.far)}';
}
