import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Why a candidate try-on photo was rejected. `none` == accepted. The screen maps
/// each reason to a localized, specific message so the user knows what to fix.
enum PoseIssue { none, noPerson, headNotVisible, feetNotVisible }

class PoseCheck {
  const PoseCheck(this.issue);

  final PoseIssue issue;

  bool get ok => issue == PoseIssue.none;
}

/// On-device, offline full-body check for the try-on photo (CLAUDE.md §1, §17).
/// We deliver try-on from this image, so it must show the whole body — ML Kit
/// pose detection lets us reject head-only / cropped shots instantly and for free,
/// with no upload and no biometric data leaving the device.
class PoseValidator {
  PoseValidator({PoseDetector? detector})
    : _detector = detector ?? PoseDetector(options: PoseDetectorOptions());

  final PoseDetector _detector;

  /// In-frame likelihood below which a landmark is treated as "not visible".
  static const double _minLikelihood = 0.5;

  Future<PoseCheck> validateFile(String path) async {
    final poses = await _detector.processImage(InputImage.fromFilePath(path));
    return evaluate(poses);
  }

  /// Runs detection once and returns BOTH the pass/fail check and a 0–100 quality
  /// score (for the gallery badge), so we don't process the image twice.
  Future<({PoseCheck check, int score})> inspectFile(String path) async {
    final poses = await _detector.processImage(InputImage.fromFilePath(path));
    final check = evaluate(poses);
    return (check: check, score: check.ok ? scoreFrom(poses) : 0);
  }

  /// On-device quality score (0–100) from the mean in-frame likelihood of the key
  /// full-body landmarks. Higher = more of the body is clearly, confidently in
  /// frame — used as the "which shot is best" badge.
  int scoreFrom(List<Pose> poses) {
    if (poses.isEmpty) return 0;
    final landmarks = poses.first.landmarks;
    const keys = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];
    var sum = 0.0;
    for (final k in keys) {
      sum += landmarks[k]?.likelihood ?? 0.0;
    }
    return (sum / keys.length * 100).round().clamp(0, 100);
  }

  /// Decide from detected poses whether this is a usable full-body shot. ML Kit
  /// pose detection tracks the single most-prominent subject, so we validate that
  /// one: a person present, with both the head and the feet in frame.
  PoseCheck evaluate(List<Pose> poses) {
    if (poses.isEmpty) return const PoseCheck(PoseIssue.noPerson);
    final landmarks = poses.first.landmarks;

    bool visible(PoseLandmarkType type) {
      final lm = landmarks[type];
      return lm != null && lm.likelihood >= _minLikelihood;
    }

    final hasPerson = visible(PoseLandmarkType.leftShoulder) ||
        visible(PoseLandmarkType.rightShoulder) ||
        visible(PoseLandmarkType.leftHip) ||
        visible(PoseLandmarkType.rightHip);
    final hasHead = visible(PoseLandmarkType.nose) ||
        visible(PoseLandmarkType.leftEye) ||
        visible(PoseLandmarkType.rightEye);
    final hasFeet = visible(PoseLandmarkType.leftAnkle) ||
        visible(PoseLandmarkType.rightAnkle) ||
        visible(PoseLandmarkType.leftHeel) ||
        visible(PoseLandmarkType.rightHeel);

    return PoseCheck(decide(hasPerson: hasPerson, hasHead: hasHead, hasFeet: hasFeet));
  }

  /// Pure decision over the three presence flags — unit-tested without ML Kit.
  static PoseIssue decide({
    required bool hasPerson,
    required bool hasHead,
    required bool hasFeet,
  }) {
    if (!hasPerson) return PoseIssue.noPerson;
    if (!hasHead) return PoseIssue.headNotVisible;
    if (!hasFeet) return PoseIssue.feetNotVisible;
    return PoseIssue.none;
  }

  void dispose() => _detector.close();
}

/// Owns a single detector for the app's lifetime; closed when no longer watched.
final poseValidatorProvider = Provider<PoseValidator>((ref) {
  final validator = PoseValidator();
  ref.onDispose(validator.dispose);
  return validator;
});
