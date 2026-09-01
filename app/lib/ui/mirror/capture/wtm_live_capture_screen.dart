import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/profile/pose_validator.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/wtm_colors.dart';
import '../../../theme/wtm_shapes.dart';
import '../../../theme/wtm_typography.dart';
import '../../widgets/widgets.dart';
import 'live_camera.dart';
import 'live_capture_framing.dart';
import 'live_frame_analyzer.dart';

/// Where the flow is.
enum _Phase { prep, opening, live, capturing, review, denied, unavailable }

/// The iOS/iPadOS live self-capture for a try-on PERSON image.
///
/// Pushed instead of a source sheet wherever the media policy answers
/// `liveFrontCameraOnly`. It has no gallery affordance, no Files affordance, no
/// camera-switch control and no import of any kind — the only way a picture
/// leaves this screen is the front lens, and the only way it leaves at all is
/// the user tapping Use This Photo.
///
/// Pops with the temporary file path of an accepted capture, or null for
/// every other exit (cancel, back, denial, failure). The caller owns the file
/// from that moment; this screen owns it until then and deletes it on Retake,
/// Cancel and any unrecoverable failure.
class WtmLiveCaptureScreen extends ConsumerStatefulWidget {
  const WtmLiveCaptureScreen({super.key, this.clock});

  /// The clock the auto-capture timing runs on.
  ///
  /// Injected for tests only. `tester.pump(duration)` advances Flutter's timer
  /// queue but NOT `DateTime.now()`, so a hold-then-count-down sequence driven
  /// off wall time could only be tested by really waiting six seconds — which
  /// is both slow and exactly the kind of timing-dependent flake this suite is
  /// not allowed to have. Production passes nothing and gets the real clock.
  @visibleForTesting
  final DateTime Function()? clock;

  @override
  ConsumerState<WtmLiveCaptureScreen> createState() =>
      _WtmLiveCaptureScreenState();
}

class _WtmLiveCaptureScreenState extends ConsumerState<WtmLiveCaptureScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.prep;
  LiveCamera? _camera;

  /// One tracker per live session. Its `fired` latch is what makes a duplicate
  /// capture impossible however many frames arrive after the shutter.
  late final _auto = AutoCaptureTracker(clock: widget.clock);
  LiveFramingCheck _check = const LiveFramingCheck(LiveFramingIssue.noPerson);
  int? _countdown;

  /// Increments once per countdown tick and once at the shutter, driving the
  /// full-screen luminance pulse. A counter rather than a bool because each
  /// pulse must restart from full brightness — see [_FlashPulse].
  int _flash = 0;

  /// The fallback timer's remaining seconds, or null when it is not running.
  Timer? _timer;
  int? _timerRemaining;

  /// The pending capture. Owned by this screen, deleted unless accepted.
  String? _capturePath;
  bool _captureUsable = true;

  /// Latches across the whole screen, not just one tracker: a rapid double tap
  /// on the shutterless timer and a simultaneous auto-fire must still produce
  /// exactly one `takePicture`.
  bool _capturing = false;

  /// Guards against two concurrent opens (a double tap on "Open camera", or a
  /// Retake racing the button underneath it).
  ///
  /// Deliberately its own flag rather than a check on `_phase == opening`:
  /// Retake sets that phase itself to show the spinner, so a phase-based guard
  /// refused the very reopen it was asked to perform and left the user on a
  /// dead "starting the camera" screen.
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Fire-and-forget: the widget is going away and neither call can be
    // awaited here. Both are individually safe to run unobserved.
    unawaited(_camera?.dispose());
    unawaited(_discardCapture());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A camera session does not survive backgrounding on iOS — the OS takes
    // the capture device away — so leaving one open produces a frozen black
    // preview on return. Tear down on the way out and rebuild on the way back
    // in, which also re-runs the permission check for free.
    if (_phase != _Phase.live && _phase != _Phase.opening) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Not awaited: this callback is synchronous, and the teardown is safe to
      // run unobserved — the phase change below already stops anything from
      // using the session while it closes.
      unawaited(_stopCamera());
      if (mounted) setState(() => _phase = _Phase.prep);
    }
  }

  // ---- camera lifecycle -----------------------------------------------------

  Future<void> _stopCamera() async {
    _timer?.cancel();
    _timer = null;
    _timerRemaining = null;
    final camera = _camera;
    _camera = null;
    _auto.reset();
    _countdown = null;
    await camera?.dispose();
  }

  Future<void> _openCamera() async {
    if (_opening) return;
    _opening = true;
    setState(() {
      _phase = _Phase.opening;
      _error = null;
      _check = const LiveFramingCheck(LiveFramingIssue.noPerson);
    });
    _auto.reset();
    try {
      final camera = await ref.read(liveCameraOpenerProvider).openFront();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      setState(() => _phase = _Phase.live);
      await camera.streamFrames(_onFrame);
    } on LiveCameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _phase = e.failure == LiveCameraFailure.denied
            ? _Phase.denied
            : _Phase.unavailable,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.unavailable);
    } finally {
      _opening = false;
    }
  }

  void _onFrame(LiveFrame frame) {
    if (!mounted || _capturing || _phase != _Phase.live) return;
    unawaited(_analyze(frame));
  }

  Future<void> _analyze(LiveFrame frame) async {
    final check = await ref.read(liveFrameAnalyzerProvider).analyze(frame);
    if (!mounted || _capturing || _phase != _Phase.live) return;

    // The fallback timer is the user's explicit decision to capture at a fixed
    // moment. Auto-capture must not pre-empt it, so framing is still shown
    // (they can see whether they made it) but it cannot fire the shutter.
    final phase = _timer != null
        ? AutoCapturePhase.waiting
        : _auto.update(check);
    final countdown = _timer != null ? null : _auto.countdown;

    if (check != _check || countdown != _countdown) {
      final wasCounting = _countdown;
      setState(() {
        _check = check;
        _countdown = countdown;
      });
      if (countdown != null && countdown != wasCounting && countdown > 0) {
        _tick(
          AppLocalizations.of(context).liveCaptureCountdownLabel(countdown),
        );
      }
    }
    if (phase == AutoCapturePhase.capture) await _capture();
  }

  /// The countdown's non-visual half, for the person standing three metres
  /// away who cannot read small text and cannot feel the device.
  ///
  /// Four cues, because no single one survives every device state:
  ///
  ///  * a system sound — [SystemSoundType.tick], which the iOS engine maps to
  ///    `kWheelsOfTimeSoundId`, the picker-wheel tick. NOT
  ///    [SystemSoundType.click]: that maps to `kKeyPressClickSoundId`, the
  ///    keyboard tock, which is the quietest sound iOS ships and means "you
  ///    typed something" rather than "the shutter is coming";
  ///  * a haptic bump, for anyone still holding the device;
  ///  * a full-screen luminance pulse — the ONLY cue here that survives the
  ///    Ring/Silent switch. Every Flutter system sound goes through
  ///    `AudioServicesPlaySystemSound`, which a silenced iPhone suppresses
  ///    entirely, so audio alone would leave a muted device counting down in
  ///    silence. It is also what Apple's own Camera timer does; and
  ///  * a VoiceOver announcement, for users who have it turned on.
  ///
  /// None of them needs the microphone, and none needs the user to be reading
  /// the screen at the moment it fires.
  void _tick(String announcement) {
    unawaited(SystemSound.play(SystemSoundType.tick));
    unawaited(HapticFeedback.lightImpact());
    if (mounted) setState(() => _flash++);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        announcement,
        TextDirection.ltr,
        // Assertive: a countdown that VoiceOver queues politely behind the
        // framing banner would be spoken after the shutter has already fired.
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  // ---- capture --------------------------------------------------------------

  Future<void> _capture() async {
    // ONE shutter. Guarded here rather than only in the tracker because the
    // fallback timer, a rapid tap and an auto-fire are three different callers
    // and they all end up on this line.
    if (_capturing) return;
    _capturing = true;
    _timer?.cancel();
    _timer = null;
    final camera = _camera;
    if (camera == null) {
      _capturing = false;
      return;
    }
    if (mounted) {
      setState(() {
        _phase = _Phase.capturing;
        _timerRemaining = null;
        // The shutter's own pulse, for the same reason the ticks have one: on
        // a silenced phone this is the only signal that the photo was taken.
        _flash++;
      });
    }
    unawaited(HapticFeedback.mediumImpact());
    try {
      final path = await camera.takePicture();
      // Validate the HIGH-RESOLUTION still, not the preview frame that started
      // the countdown. The preview is a lower-resolution, differently-exposed
      // approximation, and a person who stepped out during the shutter would
      // otherwise sail through on the strength of the frame before it.
      final result = await ref.read(poseValidatorProvider).inspectFile(path);
      if (!mounted) {
        await _deleteFile(path);
        return;
      }
      await _discardCapture();
      setState(() {
        _capturePath = path;
        _captureUsable = result.check.ok;
        _phase = _Phase.review;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).liveCaptureFailed;
        _phase = _Phase.live;
      });
      _auto.reset();
      // Taking the still stopped the frame stream. Without restarting it the
      // preview keeps drawing but no framing verdicts arrive, so auto-capture
      // is silently dead and the user is left tapping at a camera that will
      // never fire again.
      _capturing = false;
      await camera.streamFrames(_onFrame);
    } finally {
      _capturing = false;
    }
  }

  void _startTimer() {
    if (_timer != null || _capturing) return;
    // The user has chosen the moment; auto-capture stands down for the
    // duration, and starts fresh if they change their mind.
    _auto.reset();
    var remaining = LiveFramingRules.timerFallback.inSeconds;
    setState(() => _timerRemaining = remaining);
    _tick(AppLocalizations.of(context).liveCaptureTimerRunning(remaining));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (remaining <= 0) {
        timer.cancel();
        _timer = null;
        unawaited(_capture());
        return;
      }
      setState(() => _timerRemaining = remaining);
      // The last three seconds get the same audible cadence as auto-capture,
      // so somebody standing across the room hears the same thing either way.
      if (remaining <= 3) {
        _tick(AppLocalizations.of(context).liveCaptureTimerRunning(remaining));
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    // The tracker was not consulted while the timer ran, so its "framing has
    // been valid since…" mark is stale. Clearing it means cancelling the timer
    // gives the ordinary hold-then-count-down again, rather than firing on the
    // next frame for reasons the user cannot see.
    _auto.reset();
    setState(() {
      _timerRemaining = null;
      _countdown = null;
    });
  }

  // ---- capture file lifecycle ----------------------------------------------

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best effort. The OS clears the app's temp directory anyway; failing to
      // delete must never block leaving the screen.
    }
  }

  /// Drops the pending capture. Called on Retake, Cancel, a replacement
  /// capture and teardown — every exit except acceptance.
  Future<void> _discardCapture() async {
    final path = _capturePath;
    _capturePath = null;
    if (path != null) await _deleteFile(path);
  }

  Future<void> _retake() async {
    await _discardCapture();
    if (!mounted) return;
    _auto.reset();
    setState(() {
      _phase = _Phase.opening;
      _error = null;
    });
    // The still stopped the frame stream, and a stopped stream cannot simply
    // be restarted on iOS without a fresh session — so reopen rather than
    // resume. It is also the one moment when a permission that changed while
    // we were away gets re-checked.
    await _stopCamera();
    await _openCamera();
  }

  void _accept() {
    final path = _capturePath;
    if (path == null || !_captureUsable) return;
    // Ownership transfers to the caller with this pop; do NOT delete it here.
    _capturePath = null;
    Navigator.of(context).pop(LiveCaptureResult(path: path));
  }

  void _cancel() {
    unawaited(_discardCapture());
    Navigator.of(context).pop();
  }

  // ---- copy -----------------------------------------------------------------

  String _issueText(AppLocalizations l) => switch (_check.issue) {
    LiveFramingIssue.noPerson => l.liveCaptureNoPerson,
    LiveFramingIssue.multiplePeople => l.liveCaptureMultiplePeople,
    LiveFramingIssue.poorLighting => l.liveCaptureLighting,
    LiveFramingIssue.blurry => l.liveCaptureBlurry,
    LiveFramingIssue.headOutOfFrame => l.liveCaptureHead,
    LiveFramingIssue.feetOutOfFrame => l.liveCaptureFeet,
    LiveFramingIssue.bodyOutOfFrame => l.liveCaptureCentre,
    LiveFramingIssue.tooFar => l.liveCaptureTooFar,
    LiveFramingIssue.tooClose => l.liveCaptureTooClose,
    LiveFramingIssue.none => l.liveCaptureHold,
  };

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A system back / edge swipe is a cancel like any other, and the pending
      // capture must not survive it.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_discardCapture());
      },
      child: switch (_phase) {
        _Phase.prep => _prep(),
        _Phase.denied => _denied(),
        _Phase.unavailable => _unavailable(),
        _Phase.review => _review(),
        _ => _live(),
      },
    );
  }

  Widget _prep() {
    final l10n = AppLocalizations.of(context);
    // Before a camera exists there is no preview geometry to read, so the
    // preparation copy uses the 4:3 default every front camera at least meets.
    final distance = standBackLabel(_camera?.previewAspectRatio ?? 4 / 3);
    return WtmPage(
      fullBleed: true,
      title: l10n.liveCaptureTitle,
      eyebrow: l10n.liveCaptureEyebrow,
      onBack: _cancel,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientCta(
            label: l10n.liveCapturePrepStart,
            icon: const WtmIcon(
              WtmGlyph.camera,
              size: 15,
              color: WtmColors.ctaText,
            ),
            onPressed: _openCamera,
          ),
          const SizedBox(height: WtmSpace.s10),
          GhostButton(label: l10n.liveCaptureCancel, onPressed: _cancel),
        ],
      ),
      children: [
        const SizedBox(height: WtmSpace.s18),
        Text(
          l10n.liveCapturePrepTitle,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 20),
        ),
        const SizedBox(height: WtmSpace.s8),
        Text(
          l10n.liveCapturePrepBody,
          textAlign: TextAlign.center,
          style: WtmType.sub.copyWith(height: 1.5),
        ),
        const SizedBox(height: WtmSpace.s22),
        _Step(1, l10n.liveCapturePrepStand),
        _Step(2, l10n.liveCapturePrepDistance(distance)),
        _Step(3, l10n.liveCapturePrepFull),
        _Step(4, l10n.liveCapturePrepLight),
        _Step(5, l10n.liveCapturePrepPose),
        const SizedBox(height: WtmSpace.s18),
      ],
    );
  }

  Widget _denied() => _Blocker(
    title: AppLocalizations.of(context).liveCaptureDeniedTitle,
    message: AppLocalizations.of(context).liveCaptureDeniedBody,
    // Settings, and Cancel. There is deliberately no third option: offering
    // the photo library here is exactly the bypass this whole change removes,
    // and a denial is not a network or sign-in problem to be dressed up as one.
    primaryLabel: AppLocalizations.of(context).liveCaptureOpenSettings,
    onPrimary: () => unawaited(launchUrl(Uri.parse('app-settings:'))),
    onCancel: _cancel,
  );

  Widget _unavailable() => _Blocker(
    title: AppLocalizations.of(context).liveCaptureUnavailableTitle,
    message: AppLocalizations.of(context).liveCaptureUnavailableBody,
    primaryLabel: AppLocalizations.of(context).liveCaptureRetry,
    onPrimary: _openCamera,
    onCancel: _cancel,
  );

  Widget _live() {
    final l10n = AppLocalizations.of(context);
    final camera = _camera;
    final counting = _countdown != null && _countdown! > 0;
    final timerRunning = _timerRemaining != null;

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null)
            Semantics(
              label: l10n.liveCapturePreviewLabel,
              image: true,
              excludeSemantics: true,
              // MIRRORED HERE, AND ONLY HERE. A selfie preview that moves the
              // wrong way is unusable for framing, so the preview is flipped
              // for display — but the flip is a Transform on the widget, not a
              // change to any pixels, so the captured still stays exactly as
              // the lens recorded it (garment prints read the right way round)
              // and nothing downstream can mirror it a second time.
              child: Transform.scale(
                scaleX: -1,
                child: SizedBox.expand(child: camera.buildPreview()),
              ),
            )
          else
            const AuroraBox(
              borderRadius: BorderRadius.zero,
              border: false,
              vignette: true,
            ),

          // The full-body guide, sized to the live preview.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BodyGuidePainter(valid: _check.ok || counting),
              ),
            ),
          ),

          // Bottom scrim so the copy stays legible over any room.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0008060F), Color(0xE608060F)],
                  ),
                ),
              ),
            ),
          ),

          // The countdown cue that survives a silenced phone (see [_tick]).
          // Over everything, so it reads in peripheral vision from across the
          // room — and inside IgnorePointer, so it can never swallow Cancel or
          // the timer button underneath it.
          if (!MediaQuery.of(context).disableAnimations)
            Positioned.fill(child: IgnorePointer(child: _FlashPulse(_flash))),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WtmSpace.screenH),
              child: Column(
                children: [
                  Row(
                    children: [
                      WtmIconButton(
                        WtmGlyph.back,
                        surface: WtmIconButtonSurface.image,
                        semanticLabel: l10n.liveCaptureCancel,
                        onTap: _cancel,
                      ),
                      const Spacer(),
                      // States the lens in use. There is no control here to
                      // change it, by design.
                      _Tag(l10n.liveCaptureEyebrow),
                    ],
                  ),
                  const Spacer(),
                  if (counting)
                    _Countdown(_countdown!, l10n)
                  else if (_phase == _Phase.capturing)
                    _Banner(l10n.liveCaptureCapturing, ok: true)
                  else if (_phase == _Phase.opening)
                    _Banner(l10n.liveCaptureStarting, ok: false)
                  else if (timerRunning)
                    // The same 64pt numeral auto-capture uses, not the 17pt
                    // banner this used to show. The timer exists precisely for
                    // the user who is too far away for auto-capture to settle,
                    // so it is the one countdown that MUST be readable from
                    // across the room.
                    _Countdown(_timerRemaining!, l10n)
                  else
                    _Banner(_issueText(l10n), ok: _check.ok),
                  if (_error != null) ...[
                    const SizedBox(height: WtmSpace.s10),
                    _Banner(_error!, ok: false),
                  ],
                  const SizedBox(height: WtmSpace.s14),
                  // The ONLY control besides Cancel. No shutter (auto-capture
                  // owns that), no gallery, no lens switch, no import.
                  GhostButton(
                    label: timerRunning
                        ? l10n.liveCaptureTimerCancel
                        : l10n.liveCaptureTimer,
                    onPressed: _phase == _Phase.live
                        ? (timerRunning ? _stopTimer : _startTimer)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _review() {
    final l10n = AppLocalizations.of(context);
    final path = _capturePath;
    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          if (path != null)
            Positioned.fill(
              // `contain`, so the review shows the whole capture — a cropped
              // preview would hide exactly the head or feet the user is being
              // asked to check.
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0008060F), Color(0xE608060F)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WtmSpace.screenH),
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    l10n.liveCaptureReviewTitle,
                    textAlign: TextAlign.center,
                    style: WtmType.h2.copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: WtmSpace.s6),
                  Text(
                    _captureUsable
                        ? l10n.liveCaptureReviewBody
                        : l10n.liveCaptureRetakeNeeded,
                    textAlign: TextAlign.center,
                    style: WtmType.sub,
                  ),
                  const SizedBox(height: WtmSpace.s14),
                  // Two actions. There is no Choose from Gallery, no Browse
                  // and no Import here or anywhere else in this flow.
                  GradientCta(
                    label: l10n.liveCaptureUse,
                    icon: const WtmIcon(
                      WtmGlyph.check,
                      size: 15,
                      color: WtmColors.ctaText,
                    ),
                    onPressed: _captureUsable ? _accept : null,
                  ),
                  const SizedBox(height: WtmSpace.s10),
                  GhostButton(
                    label: l10n.liveCaptureRetake,
                    onPressed: () => unawaited(_retake()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What an accepted capture hands back.
///
/// A typed wrapper rather than a bare `String`, so a route's pop value cannot
/// be confused with any other string the navigator might return.
///
/// It carries only the path. The quality score this screen computed is
/// deliberately NOT passed on: the caller re-runs the same check on the
/// COMPRESSED, EXIF-stripped bytes it is about to upload, which is the image
/// that actually ships — reusing this screen's number would mean the gallery
/// badge described a file nobody stored.
@immutable
class LiveCaptureResult {
  const LiveCaptureResult({required this.path});

  final String path;
}

// ---------------------------------------------------------------------------
// Presentation pieces.
// ---------------------------------------------------------------------------

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WtmSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sized in text-scale units so the numeral badge grows with Dynamic
          // Type instead of clipping its own digit at 200%.
          Container(
            width:
                26 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
            height:
                26 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: WtmColors.pillBg,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: WtmColors.pillBorder),
              ),
            ),
            child: Text('$n', style: WtmType.pill),
          ),
          const SizedBox(width: WtmSpace.s12),
          Expanded(
            child: Text(text, style: WtmType.body.copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s12,
        vertical: WtmSpace.s6,
      ),
      decoration: BoxDecoration(
        color: WtmColors.pillBg,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: Text(label, style: WtmType.pill),
    );
  }
}

/// The framing line. One message at a time, large enough to read from across
/// the room, and announced to VoiceOver as a live region so it is spoken as it
/// changes rather than only when focused.
class _Banner extends StatelessWidget {
  const _Banner(this.text, {required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: WtmSpace.s16,
          vertical: WtmSpace.s12,
        ),
        decoration: BoxDecoration(
          color: ok ? WtmColors.chipOnBg : const Color(0xB3100C1D),
          borderRadius: BorderRadius.circular(WtmRadius.chip),
          border: Border.all(
            color: ok ? WtmColors.chipOnBorder : WtmColors.line,
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: WtmType.body.copyWith(
            fontSize: 17,
            color: ok ? WtmColors.gold : WtmColors.text,
          ),
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown(this.value, this.l10n);

  final int value;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: l10n.liveCaptureCountdownLabel(value),
      excludeSemantics: true,
      child: Container(
        width: 132,
        height: 132,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x99100C1D),
          shape: BoxShape.circle,
          border: Border.all(color: WtmColors.chipOnBorder, width: 2),
        ),
        child: Text(
          l10n.liveCaptureCountdown(value),
          style: WtmType.display.copyWith(fontSize: 64, color: WtmColors.gold),
        ),
      ),
    );
  }
}

/// One bright pulse per countdown tick, and one at the shutter.
///
/// The only countdown cue on this screen that a silenced iPhone still gives:
/// every Flutter system sound routes through `AudioServicesPlaySystemSound`,
/// which the Ring/Silent switch suppresses, so on a muted device the numeral
/// and this pulse are the whole countdown. A full-screen luminance change is
/// what carries across a room and into peripheral vision — which is exactly
/// where the user is standing.
///
/// The caller suppresses it entirely under Reduce Motion: a repeating
/// full-screen flash is the pattern that setting exists to turn off. The
/// numeral, the sound and the haptic all remain, so nothing is lost but the
/// pulse.
class _FlashPulse extends StatelessWidget {
  const _FlashPulse(this.tick);

  /// Increments once per cue. Used as the widget key so each pulse RESTARTS at
  /// full brightness — without it the tween would be reused mid-flight and the
  /// second tick of a countdown would barely show.
  final int tick;

  @override
  Widget build(BuildContext context) {
    // Nothing has happened yet: no overlay at all, so the preview is never
    // tinted while the user is still framing.
    if (tick == 0) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(tick),
      tween: Tween<double>(begin: 0.34, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, value, child) =>
          ColoredBox(color: WtmColors.gold.withValues(alpha: value)),
    );
  }
}

/// A dead-end that is honest about why. Used for both camera denial and a
/// camera that will not start — never for a gallery fallback, which does not
/// exist on this path.
class _Blocker extends StatelessWidget {
  const _Blocker({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCancel,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      fullBleed: true,
      title: l10n.liveCaptureTitle,
      onBack: onCancel,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientCta(label: primaryLabel, onPressed: onPrimary),
          const SizedBox(height: WtmSpace.s10),
          // Cancel returns to the exact screen the flow was entered from.
          GhostButton(label: l10n.liveCaptureCancel, onPressed: onCancel),
        ],
      ),
      children: [
        const SizedBox(height: WtmSpace.s22),
        Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: AuroraBox(
              borderRadius: WtmRadius.arch,
              vignette: true,
              child: const Center(
                child: WtmIcon(
                  WtmGlyph.camera,
                  size: 34,
                  color: WtmColors.muted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WtmSpace.s22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 20),
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: WtmType.sub.copyWith(height: 1.55),
        ),
      ],
    );
  }
}

/// The full-body silhouette guide.
///
/// Drawn to the LIVE viewport rather than a fixed size, so it is the same
/// proportion of the frame on a 5.4-inch iPhone and on an iPad Air in
/// landscape — the framing rules are expressed in fractions of the preview and
/// the guide has to agree with them or it is lying to the user.
class _BodyGuidePainter extends CustomPainter {
  const _BodyGuidePainter({required this.valid});

  final bool valid;

  @override
  void paint(Canvas canvas, Size size) {
    // The guide occupies the same band the framing rules police: full height
    // less the top/bottom margins, centred, at a natural standing-body ratio.
    final top = size.height * (LiveFramingRules.topMargin + 0.02);
    final bottom = size.height * (1 - LiveFramingRules.bottomMargin - 0.02);
    final height = bottom - top;
    final width = (height * 0.34).clamp(0.0, size.width * 0.72);
    final left = (size.width - width) / 2;
    final rect = Rect.fromLTWH(left, top, width, height);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = valid
          ? WtmColors.gold.withValues(alpha: 0.95)
          : WtmColors.text.withValues(alpha: 0.35);

    // A rounded capsule reads as "stand here" without pretending to be an
    // anatomical outline that the user must match limb for limb.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(width / 2)),
      paint,
    );

    // Head and feet ticks: the two things the rules actually reject on.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = paint.color;
    final headY = top + height * 0.12;
    final feetY = bottom - height * 0.04;
    for (final y in [headY, feetY]) {
      canvas.drawLine(Offset(left - 12, y), Offset(left + 12, y), tick);
      canvas.drawLine(
        Offset(left + width - 12, y),
        Offset(left + width + 12, y),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_BodyGuidePainter oldDelegate) =>
      oldDelegate.valid != valid;
}
