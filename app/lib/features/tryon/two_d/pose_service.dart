import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'body_anchor.dart';

/// On-device body-landmark detection for the FREE 2D try-on (Google ML Kit Pose —
/// runs locally, no network, no API/GPU cost, no FASHN). Returns a normalized
/// [BodyPose] or null. Defensive by design: ANY failure (no pose, weak detection,
/// platform/codec error) returns null so the editor falls back to the category
/// heuristic — 2D never breaks.
class PoseService {
  /// Minimum landmark confidence to trust a point; weaker points are dropped so
  /// a poor photo degrades gracefully to the heuristic.
  static const _minLikelihood = 0.5;

  Future<BodyPose?> detect(ui.Image image) async {
    if (image.width <= 0 || image.height <= 0) return null;
    File? tempFile;
    Directory? tempDir;
    PoseDetector? detector;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) return null;

      tempDir = await Directory.systemTemp.createTemp('wtm_pose');
      tempFile = File('${tempDir.path}/body.png');
      await tempFile.writeAsBytes(bytes, flush: true);

      detector = PoseDetector(
        options: PoseDetectorOptions(mode: PoseDetectionMode.single),
      );
      final poses = await detector.processImage(
        InputImage.fromFilePath(tempFile.path),
      );
      if (poses.isEmpty) return null;

      final landmarks = poses.first.landmarks;
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      ui.Offset? at(PoseLandmarkType type) {
        final l = landmarks[type];
        if (l == null || l.likelihood < _minLikelihood) return null;
        return ui.Offset(l.x / w, l.y / h);
      }

      final pose = BodyPose(
        leftShoulder: at(PoseLandmarkType.leftShoulder),
        rightShoulder: at(PoseLandmarkType.rightShoulder),
        leftHip: at(PoseLandmarkType.leftHip),
        rightHip: at(PoseLandmarkType.rightHip),
        leftKnee: at(PoseLandmarkType.leftKnee),
        rightKnee: at(PoseLandmarkType.rightKnee),
        leftAnkle: at(PoseLandmarkType.leftAnkle),
        rightAnkle: at(PoseLandmarkType.rightAnkle),
        nose: at(PoseLandmarkType.nose),
      );
      // Need at least a torso to anchor anything meaningfully.
      return pose.hasTorso ? pose : null;
    } catch (_) {
      return null;
    } finally {
      await detector?.close();
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final poseServiceProvider = Provider<PoseService>((_) => PoseService());
