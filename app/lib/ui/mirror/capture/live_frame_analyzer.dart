import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'live_camera.dart';
import 'live_capture_framing.dart';

/// Turns one preview frame into a framing verdict.
///
/// Abstract so the capture screen can be driven by a scripted sequence of
/// verdicts in tests — "not framed, not framed, framed, framed, …" — which is
/// the only way to prove the countdown starts, cancels and fires correctly
/// without a camera, a person and six seconds per case.
abstract class LiveFrameAnalyzer {
  Future<LiveFramingCheck> analyze(LiveFrame frame);
  Future<void> dispose();
}

/// The on-device implementation: ML Kit pose detection (already shipped for
/// the post-capture check) plus a sparse pixel read for exposure and focus.
///
/// **No new network moderation provider, and nothing leaves the device.** This
/// is the same detector class the gallery path already runs, used on preview
/// frames instead of a file — a capture-quality aid, not an identity check.
class MlKitFrameAnalyzer implements LiveFrameAnalyzer {
  MlKitFrameAnalyzer({PoseDetector? detector})
    : _detector =
          detector ??
          PoseDetector(
            // Stream mode: tuned for successive frames rather than one-shot
            // stills, which is exactly what a live preview is.
            options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
          );

  final PoseDetector _detector;

  /// Guards against queueing detections faster than they complete. Dropping a
  /// frame is free — another arrives in 33ms — while a backlog would make the
  /// countdown react to what the user was doing a second ago.
  bool _busy = false;
  LiveFramingCheck _last = const LiveFramingCheck(LiveFramingIssue.noPerson);

  @override
  Future<LiveFramingCheck> analyze(LiveFrame frame) async {
    if (_busy) return _last;
    _busy = true;
    try {
      final quality = measureBgraQuality(
        frame.bytes,
        frame.width,
        frame.height,
      );
      final input = InputImage.fromBytes(
        bytes: frame.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: _rotation(frame.rotationDegrees),
          format: InputImageFormat.bgra8888,
          bytesPerRow: frame.bytesPerRow,
        ),
      );
      final poses = await _detector.processImage(input);
      _last = evaluateFraming(
        personCount: poses.length,
        pose: poses.isEmpty
            ? null
            : _toFramingPose(poses.first, frame.width, frame.height),
        quality: quality,
      );
      return _last;
    } catch (_) {
      // A detector hiccup must never fire the shutter. Reporting "no person"
      // holds the countdown rather than starting one on bad information.
      _last = const LiveFramingCheck(LiveFramingIssue.noPerson);
      return _last;
    } finally {
      _busy = false;
    }
  }

  static InputImageRotation _rotation(int degrees) => switch (degrees % 360) {
    90 => InputImageRotation.rotation90deg,
    180 => InputImageRotation.rotation180deg,
    270 => InputImageRotation.rotation270deg,
    _ => InputImageRotation.rotation0deg,
  };

  /// ML Kit reports landmark positions in IMAGE pixels; the framing rules work
  /// in 0..1 of the preview so they are resolution- and device-independent.
  static FramingPose _toFramingPose(Pose pose, int width, int height) {
    final w = width.toDouble();
    final h = height.toDouble();
    FramingLandmark? at(PoseLandmarkType type) {
      final lm = pose.landmarks[type];
      if (lm == null) return null;
      return FramingLandmark(lm.x / w, lm.y / h, lm.likelihood);
    }

    // The head anchor is whichever of nose/eyes is most confident: a head
    // turned in profile loses the nose long before it loses both eyes, and
    // "turn back to the camera" is not an instruction this flow gives.
    final headCandidates = [
      at(PoseLandmarkType.nose),
      at(PoseLandmarkType.leftEye),
      at(PoseLandmarkType.rightEye),
    ].nonNulls.toList()..sort((a, b) => b.likelihood.compareTo(a.likelihood));

    return FramingPose(
      head: headCandidates.firstOrNull,
      leftShoulder: at(PoseLandmarkType.leftShoulder),
      rightShoulder: at(PoseLandmarkType.rightShoulder),
      leftHip: at(PoseLandmarkType.leftHip),
      rightHip: at(PoseLandmarkType.rightHip),
      leftKnee: at(PoseLandmarkType.leftKnee),
      rightKnee: at(PoseLandmarkType.rightKnee),
      leftAnkle: at(PoseLandmarkType.leftAnkle),
      rightAnkle: at(PoseLandmarkType.rightAnkle),
    );
  }

  @override
  Future<void> dispose() => _detector.close();
}

/// Built per capture session (and closed with it) rather than kept alive for
/// the app's lifetime: a stream-mode detector holds camera-shaped state that
/// is meaningless once the camera is gone.
final liveFrameAnalyzerProvider = Provider.autoDispose<LiveFrameAnalyzer>((ref) {
  final analyzer = MlKitFrameAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});
