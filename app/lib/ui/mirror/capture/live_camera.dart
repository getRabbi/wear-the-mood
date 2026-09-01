import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which physical lens a live session is using.
///
/// Deliberately its OWN enum rather than the plugin's `CameraLensDirection`:
/// the screen, the mirroring rule and every test reason about "front or rear",
/// and none of them should have to import the `camera` package to say so. It
/// also keeps the two lenses the app supports closed — an external or
/// telephoto lens is not a thing this flow offers.
enum CameraLens {
  /// The selfie lens. The default, and the one the solo flow is built around:
  /// the user props the device up, walks back, and needs to see themselves.
  front,

  /// The main rear lens. For when somebody else is holding the device and
  /// framing the user — which is the only way some people can get a usable
  /// full-body shot at all.
  rear,
}

/// Why a live camera could not be opened.
///
/// [denied] and [unavailable] are told apart because they need opposite
/// answers from the UI: a denial is fixed in Settings and must NEVER be
/// softened into "try the gallery instead", while an unavailable camera
/// (simulator, hardware fault) is not the user's doing and must not send them
/// to a Settings screen that will not help.
enum LiveCameraFailure { denied, unavailable }

@immutable
class LiveCameraException implements Exception {
  const LiveCameraException(this.failure, [this.detail]);

  final LiveCameraFailure failure;
  final String? detail;

  @override
  String toString() => 'LiveCameraException(${failure.name}: $detail)';
}

/// One preview frame, in the shape the analyzer needs.
///
/// Deliberately raw and plugin-free so a test can build one from a byte list.
@immutable
class LiveFrame {
  const LiveFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotationDegrees,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
}

/// An open camera the capture screen drives.
///
/// Abstract so the screen can be widget-tested against a fake with no plugin,
/// no hardware and no platform channel. The real implementation is the only
/// thing in the app that touches the `camera` package.
abstract class LiveCamera {
  /// The lens this session actually opened.
  ///
  /// Read back from the opened device rather than remembered from what was
  /// asked for, so the screen's mirroring decision can never be based on an
  /// intention that the hardware did not honour.
  CameraLens get lens;

  /// Preview aspect ratio (width / height), for laying the guide over it.
  double get previewAspectRatio;

  /// The platform preview view. NOT mirrored here — mirroring is a display
  /// decision made once, by the screen, so it can never be applied twice.
  Widget buildPreview();

  /// Begin delivering preview frames. At most one listener.
  Future<void> streamFrames(void Function(LiveFrame frame) onFrame);

  /// Stop the frame stream (before a still, and on teardown).
  Future<void> stopFrames();

  /// Capture a full-resolution still and return its temporary file path.
  Future<String> takePicture();

  Future<void> dispose();
}

/// Opens a live camera, or explains why it could not.
abstract class LiveCameraOpener {
  /// Which lenses this device ACTUALLY has.
  ///
  /// Enumerated, never assumed. An iPad without a rear camera, a device whose
  /// rear lens is unavailable, and a simulator all exist, and the switch
  /// control must not appear on any of them — an affordance that fails when
  /// tapped is worse than no affordance.
  Future<Set<CameraLens>> availableLenses();

  /// Opens [lens]. Throws [LiveCameraException] if it cannot.
  Future<LiveCamera> open(CameraLens lens);
}

// ---------------------------------------------------------------------------
// The real implementation (the only `camera` package usage in the app).
// ---------------------------------------------------------------------------

class _PluginLiveCamera implements LiveCamera {
  _PluginLiveCamera(this._controller, this._description);

  final CameraController _controller;
  final CameraDescription _description;
  bool _streaming = false;
  bool _disposed = false;

  @override
  CameraLens get lens => _description.lensDirection == CameraLensDirection.front
      ? CameraLens.front
      : CameraLens.rear;

  @override
  double get previewAspectRatio => _controller.value.aspectRatio;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<void> streamFrames(void Function(LiveFrame frame) onFrame) async {
    if (_streaming || _disposed) return;
    _streaming = true;
    await _controller.startImageStream((image) {
      if (_disposed) return;
      final plane = image.planes.first;
      onFrame(
        LiveFrame(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: plane.bytesPerRow,
          rotationDegrees: _description.sensorOrientation,
        ),
      );
    });
  }

  @override
  Future<void> stopFrames() async {
    if (!_streaming || _disposed) return;
    _streaming = false;
    try {
      await _controller.stopImageStream();
    } catch (_) {
      // Already stopped (a lifecycle race). Nothing to undo.
    }
  }

  @override
  Future<String> takePicture() async {
    // The stream is stopped FIRST. Taking a still while frames are being
    // delivered is a documented source of dropped captures and stalls on iOS,
    // and this screen has exactly one shutter press to get right.
    await stopFrames();
    final file = await _controller.takePicture();
    return file.path;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopFrames();
    await _controller.dispose();
  }
}

class _PluginLiveCameraOpener implements LiveCameraOpener {
  const _PluginLiveCameraOpener();

  static Future<List<CameraDescription>> _enumerate() async {
    try {
      return await availableCameras();
    } on CameraException catch (e) {
      throw LiveCameraException(_map(e), e.description);
    }
  }

  static CameraLensDirection _direction(CameraLens lens) =>
      lens == CameraLens.front
      ? CameraLensDirection.front
      : CameraLensDirection.back;

  @override
  Future<Set<CameraLens>> availableLenses() async {
    final cameras = await _enumerate();
    return {
      for (final lens in CameraLens.values)
        if (cameras.any((c) => c.lensDirection == _direction(lens))) lens,
    };
  }

  @override
  Future<LiveCamera> open(CameraLens lens) async {
    final cameras = await _enumerate();

    // The requested lens or nothing. NOT "prefer, else fall back to the other
    // one": silently opening the rear lens for a solo self-capture gives a
    // photo of a wall, and silently opening the front lens while a helper is
    // holding the phone gives a photo of the helper. Either way the person
    // would be looking at a preview that does not match the control they just
    // used, which is worse than an honest failure.
    final description = cameras
        .where((c) => c.lensDirection == _direction(lens))
        .firstOrNull;
    if (description == null) {
      throw LiveCameraException(
        LiveCameraFailure.unavailable,
        'no ${lens.name} camera',
      );
    }

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      // No Microphone permission is requested, anywhere in this flow — for
      // EITHER lens. The countdown is visual plus haptics + the platform's own
      // accessibility announcements, none of which need the mic, and the rear
      // lens takes a still on a button press.
      enableAudio: false,
      // iOS delivers BGRA8888; the frame analyzer reads exactly that. This
      // flow is iOS-only by policy, so there is one format to support.
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw LiveCameraException(_map(e), e.description);
    }
    return _PluginLiveCamera(controller, description);
  }

  /// AVFoundation's denial codes, as surfaced by `camera_avfoundation`.
  static LiveCameraFailure _map(CameraException e) {
    const denials = {
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
      'cameraPermission',
      'AudioAccessDenied',
    };
    return denials.contains(e.code)
        ? LiveCameraFailure.denied
        : LiveCameraFailure.unavailable;
  }
}

/// The camera opener. Overridden in tests with a fake that counts opens,
/// scripts failures and never touches a platform channel.
final liveCameraOpenerProvider = Provider<LiveCameraOpener>(
  (ref) => const _PluginLiveCameraOpener(),
);
