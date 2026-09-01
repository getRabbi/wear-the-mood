import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/features/profile/pose_validator.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/mirror/capture/live_camera.dart';
import 'package:app/ui/mirror/capture/live_capture_framing.dart';
import 'package:app/ui/mirror/capture/live_frame_analyzer.dart';
import 'package:app/ui/mirror/capture/wtm_live_capture_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// THE CAMERA EXPERIENCE, without a camera.
///
/// The screen is driven against a fake [LiveCamera] and a scripted
/// [LiveFrameAnalyzer], so every branch — front lens only, auto-capture after
/// stable framing, a countdown that cancels when the user steps out, the timer
/// fallback, exactly one shutter under rapid input, denial, an unusable camera,
/// backgrounding, and the temporary-file lifecycle — is deterministic and runs
/// in milliseconds.

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeCamera implements LiveCamera {
  _FakeCamera({required this.file, this.failCapture = false});

  /// The path `takePicture` returns. A REAL file on disk, so the screen's
  /// delete-on-retake / delete-on-cancel behaviour is observable.
  final File file;
  final bool failCapture;

  int takePictureCalls = 0;
  int disposeCalls = 0;
  int stopFrameCalls = 0;
  void Function(LiveFrame)? _onFrame;

  bool get streaming => _onFrame != null;

  /// Push one preview frame through the screen.
  void emit() => _onFrame?.call(
    LiveFrame(
      bytes: Uint8List(16),
      width: 2,
      height: 2,
      bytesPerRow: 8,
      rotationDegrees: 90,
    ),
  );

  @override
  bool get isFrontFacing => true;

  @override
  double get previewAspectRatio => 3 / 4;

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF222222));

  @override
  Future<void> streamFrames(void Function(LiveFrame frame) onFrame) async {
    _onFrame = onFrame;
  }

  @override
  Future<void> stopFrames() async {
    stopFrameCalls++;
    _onFrame = null;
  }

  @override
  Future<String> takePicture() async {
    takePictureCalls++;
    await stopFrames();
    if (failCapture) throw StateError('shutter failed');
    return file.path;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await stopFrames();
  }
}

class _FakeOpener implements LiveCameraOpener {
  _FakeOpener(this.camera, {this.failure});

  final _FakeCamera? camera;
  final LiveCameraFailure? failure;
  int opens = 0;

  @override
  Future<LiveCamera> openFront() async {
    opens++;
    final f = failure;
    if (f != null) throw LiveCameraException(f, 'scripted');
    return camera!;
  }
}

/// The post-capture check on the HIGH-RESOLUTION still.
///
/// Real ML Kit needs a platform channel, so it is faked — but the screen's
/// dependency on it is not removed: these tests still prove that a still which
/// fails the full-body check cannot be accepted.
class _FakePoseValidator implements PoseValidator {
  _FakePoseValidator({this.issue = PoseIssue.none});

  final PoseIssue issue;
  int calls = 0;

  @override
  Future<({PoseCheck check, int score})> inspectFile(String path) async {
    calls++;
    // A rejected still scores 0, exactly as the real validator does — the
    // score the capture carries forward is only meaningful when it passed.
    return (check: PoseCheck(issue), score: issue == PoseIssue.none ? 88 : 0);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// Returns whatever the test currently says the framing is.
class _ScriptedAnalyzer implements LiveFrameAnalyzer {
  LiveFramingCheck next = const LiveFramingCheck(LiveFramingIssue.noPerson);
  int calls = 0;

  @override
  Future<LiveFramingCheck> analyze(LiveFrame frame) async {
    calls++;
    return next;
  }

  @override
  Future<void> dispose() async {}
}

/// The capture screen's clock, advanced by [feed] alongside `tester.pump`.
var _now = DateTime(2026, 8, 28, 12);

/// The auto-capture countdown numeral, whichever second it is currently on.
final _countdownDigit = find.byWidgetPredicate(
  (w) => w is Text && const ['3', '2', '1'].contains(w.data),
);

/// The rendered size of a countdown numeral. The whole point of the numeral
/// is that it is legible from across a room, so the tests assert the size
/// rather than merely that the digits exist.
double _countdownFontSize(WidgetTester tester, String digits) =>
    tester.widget<Text>(find.text(digits)).style!.fontSize!;

/// Drives a whole countdown, sampling the pulse after EVERY frame, and
/// returns the brightest value seen (null if it never lit).
///
/// Sampled per frame because a pulse is brief by design: it fades over 260ms
/// while frames arrive 600ms apart, so any single arbitrary instant is
/// usually dark. The claim under test is "the screen lights up during the
/// countdown", not "it is lit at this exact moment".
Future<double?> _brightestPulse(
  WidgetTester tester,
  _FakeCamera camera, {
  // Bounded to the live countdown: past ~5 frames auto-capture has fired and
  // the numeral is legitimately gone, which would make the comparison between
  // the two settings bogus rather than meaningful.
  int frames = 4,
}) async {
  double? brightest;
  for (var i = 0; i < frames; i++) {
    camera.emit();
    await tester.pump();
    _now = _now.add(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final v = _pulseOpacity(tester);
    if (v != null && (brightest == null || v > brightest)) brightest = v;
  }
  return brightest;
}

/// The luminance pulse's current alpha, or null when no pulse is on screen.
/// Read from the painted [ColoredBox] rather than from screen state, so the
/// assertion is about what the user can actually see.
double? _pulseOpacity(WidgetTester tester) {
  final boxes = tester
      .widgetList<ColoredBox>(find.byType(ColoredBox))
      .where((b) => b.color.a > 0 && b.color.a < 1)
      .toList();
  if (boxes.isEmpty) return null;
  return boxes.first.color.a;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() => _now = DateTime(2026, 8, 28, 12));

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wtm_capture_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A real 1x1 PNG so `Image.file` in the review step decodes for real.
  File captureFile() {
    final f = File('${tmp.path}/capture.jpg')
      ..writeAsBytesSync(_png, flush: true);
    return f;
  }

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  /// Mounts the capture screen alone (no router), so nothing else can be the
  /// reason a test passes or fails. Returns the value it pops with.
  Future<LiveCaptureResult?> mount(
    WidgetTester tester, {
    required _FakeOpener opener,
    required _ScriptedAnalyzer analyzer,
    _FakePoseValidator? validator,
    Size size = const Size(1179, 2556),
    double dpr = 3.0,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    LiveCaptureResult? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveCameraOpenerProvider.overrideWithValue(opener),
          liveFrameAnalyzerProvider.overrideWithValue(analyzer),
          poseValidatorProvider.overrideWithValue(
            validator ?? _FakePoseValidator(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Wraps the whole app rather than the screen, so the flag reaches the
          // pushed route — a MediaQuery around `home` would not.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<LiveCaptureResult>(
                  MaterialPageRoute(
                    // The screen runs on the test's own clock, which `feed`
                    // advances in step with `tester.pump`.
                    builder: (_) => WtmLiveCaptureScreen(clock: () => _now),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return popped;
  }

  /// Drives the screen from the preparation step into the live preview.
  Future<void> openCamera(WidgetTester tester) async {
    await tester.tap(find.text('Open camera'));
    await settle(tester);
  }

  /// Feeds [count] frames with the analyzer's current verdict, advancing the
  /// wall clock between them so the real [AutoCaptureTracker] can progress.
  Future<void> feed(
    WidgetTester tester,
    _FakeCamera camera, {
    int count = 1,
    Duration gap = const Duration(milliseconds: 600),
  }) async {
    for (var i = 0; i < count; i++) {
      camera.emit();
      await tester.pump();
      _now = _now.add(gap);
      await tester.pump(gap);
      // The analyzer resolves on a microtask; a second pump lets the setState
      // it triggers reach the tree before the next frame is fed.
      await tester.pump();
    }
    await tester.pump();
  }

  group('preparation step', () {
    testWidgets('explains the solo setup before any camera is opened', (
      tester,
    ) async {
      final opener = _FakeOpener(_FakeCamera(file: captureFile()));
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());

      expect(find.text('Set up your shot'), findsOneWidget);
      expect(
        find.textContaining('upright on a table or stand'),
        findsOneWidget,
      );
      expect(
        find.textContaining('metres so your whole body fits'),
        findsOneWidget,
      );
      expect(
        find.textContaining('head and your feet inside the guide'),
        findsOneWidget,
      );
      expect(find.textContaining('even light'), findsOneWidget);
      expect(find.textContaining('arms slightly away'), findsOneWidget);
      // Nothing has been opened yet, so no permission has been requested.
      expect(opener.opens, 0);
    });

    testWidgets('offers no gallery, files or import affordance', (
      tester,
    ) async {
      await mount(
        tester,
        opener: _FakeOpener(_FakeCamera(file: captureFile())),
        analyzer: _ScriptedAnalyzer(),
      );
      for (final forbidden in [
        'Gallery',
        'Photos',
        'Browse',
        'Import',
        'Files',
        'Choose',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: '"$forbidden" must not exist in the capture flow',
        );
      }
    });
  });

  group('live preview', () {
    testWidgets('opens the FRONT camera and shows no lens switch', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final opener = _FakeOpener(camera);
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      expect(opener.opens, 1);
      expect(camera.isFrontFacing, isTrue);
      expect(camera.streaming, isTrue);
      // The lens is stated, never offered as a choice.
      expect(find.text('Front camera only'), findsOneWidget);
      for (final control in ['Switch', 'Flip', 'Rear', 'Back camera']) {
        expect(find.textContaining(control), findsNothing, reason: control);
      }
    });

    testWidgets('shows the framing issue, one message at a time', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer();
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      analyzer.next = const LiveFramingCheck(LiveFramingIssue.tooFar);
      await feed(tester, camera);
      expect(find.text('Come a little closer'), findsOneWidget);

      analyzer.next = const LiveFramingCheck(LiveFramingIssue.feetOutOfFrame);
      await feed(tester, camera);
      expect(find.text('Your feet are out of frame'), findsOneWidget);
      expect(find.text('Come a little closer'), findsNothing);
    });

    testWidgets('auto-captures only after framing has HELD, then 3-2-1', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 91);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      // First valid frame: holding, not counting, nothing captured.
      camera.emit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hold still…'), findsOneWidget);
      expect(camera.takePictureCalls, 0);

      // Hold past the stability window, then run out the countdown.
      await feed(tester, camera, count: 12);
      expect(camera.takePictureCalls, 1);
    });

    testWidgets('leaving the frame cancels the countdown, capturing nothing', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      // Get a countdown running.
      await feed(tester, camera, count: 2);
      expect(camera.takePictureCalls, 0);

      // Step out, and stay out for longer than the whole sequence.
      analyzer.next = const LiveFramingCheck(LiveFramingIssue.noPerson);
      await feed(tester, camera, count: 8);

      expect(camera.takePictureCalls, 0, reason: 'nothing may be captured');
      expect(find.text('Step into the frame'), findsOneWidget);
    });

    testWidgets('exactly ONE capture, however many frames keep arriving', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      await feed(tester, camera, count: 20);
      expect(camera.takePictureCalls, 1);
    });

    testWidgets('the frame stream is stopped before the still is taken', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);

      expect(camera.takePictureCalls, 1);
      expect(camera.streaming, isFalse);
    });
  });

  group('countdown cues (readable and audible from across the room)', () {
    testWidgets('auto-capture shows the large numeral too', (tester) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 4);

      // Whichever digit the countdown is on, it is rendered large.
      expect(_countdownDigit, findsOneWidget);
      expect(
        tester.widget<Text>(_countdownDigit).style!.fontSize!,
        greaterThanOrEqualTo(40),
      );
    });

    testWidgets(
      'a tick pulses the screen — the cue a muted phone still gives',
      (tester) async {
        final camera = _FakeCamera(file: captureFile());
        final analyzer = _ScriptedAnalyzer()
          ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
        await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
        await openCamera(tester);

        // Nothing has ticked yet: the preview is not tinted while framing.
        expect(_pulseOpacity(tester), isNull);

        final lit = await _brightestPulse(tester, camera);
        // Still counting down — the same window the Reduce Motion test asserts
        // over, so the two differ only in the setting under test.
        expect(_countdownDigit, findsOneWidget);
        expect(lit, isNotNull, reason: 'the countdown must pulse the screen');
        expect(
          lit,
          greaterThan(0.2),
          reason: 'a pulse too faint to see across a room is not a cue',
        );
      },
    );

    testWidgets('Reduce Motion suppresses the pulse but keeps the numeral', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(
        tester,
        opener: _FakeOpener(camera),
        analyzer: analyzer,
        reduceMotion: true,
      );
      await openCamera(tester);

      expect(
        await _brightestPulse(tester, camera),
        isNull,
        reason: 'no full-screen flashing under Reduce Motion',
      );
      // The countdown itself is untouched — only the pulse is dropped.
      expect(_countdownDigit, findsOneWidget);
    });

    testWidgets('the pulse never intercepts a tap', (tester) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 2);

      // The timer button is under the pulse overlay; it must still respond.
      await tester.tap(find.text('Start 10-second timer'));
      await tester.pump();
      expect(find.text('Stop timer'), findsOneWidget);
    });
  });

  group('timer fallback', () {
    testWidgets('counts down from 10 and captures once', (tester) async {
      final camera = _FakeCamera(file: captureFile());
      // Framing never becomes valid — this is exactly when the timer earns
      // its place.
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.noPerson);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      expect(find.text('Start 10-second timer'), findsOneWidget);
      await tester.tap(find.text('Start 10-second timer'));
      await tester.pump();
      // The LARGE numeral, not the small banner this used to show: the timer
      // is for the user auto-capture could not settle on, who is by definition
      // too far away to read 17pt.
      expect(find.text('10'), findsOneWidget);
      expect(_countdownFontSize(tester, '10'), greaterThanOrEqualTo(40));
      expect(find.text('Stop timer'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(camera.takePictureCalls, 0);

      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(camera.takePictureCalls, 1);
    });

    testWidgets('stopping the timer restores the full hold and countdown', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      // Framing is already perfect and stays perfect for the timer's whole run.
      await tester.tap(find.text('Start 10-second timer'));
      await feed(tester, camera, count: 8);
      await tester.tap(find.text('Stop timer'));
      await tester.pump();

      // The very next frame must NOT fire: the hold starts over.
      camera.emit();
      await tester.pump();
      _now = _now.add(const Duration(milliseconds: 100));
      await tester.pump();
      expect(camera.takePictureCalls, 0);
      expect(find.text('Hold still…'), findsOneWidget);
    });

    testWidgets('can be stopped without capturing', (tester) async {
      final camera = _FakeCamera(file: captureFile());
      await mount(
        tester,
        opener: _FakeOpener(camera),
        analyzer: _ScriptedAnalyzer(),
      );
      await openCamera(tester);

      await tester.tap(find.text('Start 10-second timer'));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Stop timer'));
      await tester.pump(const Duration(seconds: 15));

      expect(camera.takePictureCalls, 0);
      expect(find.text('Start 10-second timer'), findsOneWidget);
    });

    testWidgets('a running timer is not pre-empted by auto-capture', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 95);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);

      await tester.tap(find.text('Start 10-second timer'));
      await tester.pump();
      // Perfect framing arrives while the timer runs. The user asked for a
      // fixed moment; they get it.
      await feed(
        tester,
        camera,
        count: 12,
        gap: const Duration(milliseconds: 500),
      );
      expect(camera.takePictureCalls, 0);

      await tester.pump(const Duration(seconds: 8));
      await settle(tester);
      expect(camera.takePictureCalls, 1);
    });
  });

  group('review and handoff', () {
    testWidgets('offers Use This Photo and Retake, and nothing else', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);

      expect(find.text('Use this photo'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
      for (final forbidden in [
        'Gallery',
        'Browse',
        'Import',
        'Choose',
        'Files',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('a still that fails the full-body check cannot be accepted', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      // The preview frame said "framed"; the high-resolution still disagrees,
      // which is the case that matters — somebody who stepped out during the
      // shutter must not sail through on the strength of the frame before it.
      final validator = _FakePoseValidator(issue: PoseIssue.feetNotVisible);
      await mount(
        tester,
        opener: _FakeOpener(camera),
        analyzer: analyzer,
        validator: validator,
      );
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);

      expect(validator.calls, 1, reason: 'the STILL is what gets validated');
      expect(
        find.textContaining('whole body needs to be in frame'),
        findsOneWidget,
      );
      // Retake is the only way forward.
      final use = tester.widget<GradientCta>(find.byType(GradientCta));
      expect(use.onPressed, isNull);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('Retake DELETES the capture and reopens the camera', (
      tester,
    ) async {
      final file = captureFile();
      final camera = _FakeCamera(file: file);
      final opener = _FakeOpener(camera);
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: opener, analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);
      expect(file.existsSync(), isTrue);

      await tester.tap(find.text('Retake'));
      // Retake does REAL file I/O before it reopens the camera. Pumped frames
      // alone do not let that complete, so the real event loop gets a turn.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);

      expect(
        file.existsSync(),
        isFalse,
        reason: 'abandoned capture is deleted',
      );
      expect(opener.opens, 2, reason: 'a fresh session, not a resumed one');
    });
  });

  group('camera denial', () {
    testWidgets('offers Settings and Cancel — and NEVER a gallery fallback', (
      tester,
    ) async {
      final opener = _FakeOpener(null, failure: LiveCameraFailure.denied);
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      expect(find.text('Camera access is off'), findsOneWidget);
      expect(
        find.textContaining('taken live with the front camera'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // The whole point.
      for (final forbidden in [
        'Gallery',
        'Photos',
        'Browse',
        'Choose',
        'Files',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('a denial is not dressed up as a network or sign-in error', (
      tester,
    ) async {
      await mount(
        tester,
        opener: _FakeOpener(null, failure: LiveCameraFailure.denied),
        analyzer: _ScriptedAnalyzer(),
      );
      await openCamera(tester);

      for (final wrong in ['connection', 'network', 'sign in', 'account']) {
        expect(find.textContaining(wrong), findsNothing, reason: wrong);
      }
    });

    testWidgets('Cancel returns to the previous screen with no photo', (
      tester,
    ) async {
      await mount(
        tester,
        opener: _FakeOpener(null, failure: LiveCameraFailure.denied),
        analyzer: _ScriptedAnalyzer(),
      );
      await openCamera(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(WtmLiveCaptureScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('an unusable camera is distinguished from a denied one', (
      tester,
    ) async {
      final opener = _FakeOpener(null, failure: LiveCameraFailure.unavailable);
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      // Retry, not Settings — Settings cannot fix a camera another app holds.
      expect(find.text('Camera unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('a shutter failure leaves auto-capture ALIVE, not dead', (
      tester,
    ) async {
      // Taking the still stops the frame stream. If nothing restarts it the
      // preview keeps drawing while no verdict ever arrives again — a camera
      // that looks fine and can never fire.
      final camera = _FakeCamera(file: captureFile(), failCapture: true);
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);

      expect(camera.takePictureCalls, 1);
      expect(camera.streaming, isTrue, reason: 'frames are flowing again');
    });

    testWidgets('a shutter failure explains itself and stays on the camera', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile(), failCapture: true);
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);

      expect(find.textContaining("didn't save"), findsOneWidget);
      expect(find.text('Use this photo'), findsNothing);
    });
  });

  group('lifecycle', () {
    testWidgets('backgrounding tears the session down instead of freezing', (
      tester,
    ) async {
      final camera = _FakeCamera(file: captureFile());
      final opener = _FakeOpener(camera);
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      expect(camera.streaming, isTrue);

      // Flutter's lifecycle state machine only allows resumed -> inactive, so
      // that is the transition a real backgrounding starts with.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);

      expect(camera.disposeCalls, 1);
      // Back to the preparation step, from which reopening rebuilds a fresh
      // session (and re-checks permission for free).
      expect(find.text('Set up your shot'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await openCamera(tester);
      expect(opener.opens, 2);
    });

    testWidgets('cancelling deletes the pending capture', (tester) async {
      final file = captureFile();
      final camera = _FakeCamera(file: file);
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 90);
      await mount(tester, opener: _FakeOpener(camera), analyzer: analyzer);
      await openCamera(tester);
      await feed(tester, camera, count: 12);
      await settle(tester);
      expect(file.existsSync(), isTrue);

      // System back, the path that is easiest to forget.
      final dynamic state = tester.state(find.byType(WtmLiveCaptureScreen));
      Navigator.of(tester.element(find.byType(WtmLiveCaptureScreen))).pop();
      await settle(tester);
      expect(state, isNotNull);

      expect(file.existsSync(), isFalse);
    });
  });

  group('layout', () {
    for (final device in const [
      (name: 'iPhone SE', size: Size(750, 1334), dpr: 2.0),
      (name: 'iPhone 15 Pro', size: Size(1179, 2556), dpr: 3.0),
      (name: 'iPad Air 11-inch portrait', size: Size(1640, 2360), dpr: 2.0),
      (name: 'iPad Air 11-inch landscape', size: Size(2360, 1640), dpr: 2.0),
    ]) {
      testWidgets('${device.name}: preparation does not overflow', (
        tester,
      ) async {
        await mount(
          tester,
          opener: _FakeOpener(_FakeCamera(file: captureFile())),
          analyzer: _ScriptedAnalyzer(),
          size: device.size,
          dpr: device.dpr,
        );
        expect(find.text('Set up your shot'), findsOneWidget);
        expect(find.text('Open camera'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${device.name}: the live preview does not overflow', (
        tester,
      ) async {
        final camera = _FakeCamera(file: captureFile());
        await mount(
          tester,
          opener: _FakeOpener(camera),
          analyzer: _ScriptedAnalyzer(),
          size: device.size,
          dpr: device.dpr,
        );
        await openCamera(tester);
        expect(find.text('Start 10-second timer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('2.0x Dynamic Type does not overflow the preparation step', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveCameraOpenerProvider.overrideWithValue(
              _FakeOpener(_FakeCamera(file: captureFile())),
            ),
            liveFrameAnalyzerProvider.overrideWithValue(_ScriptedAnalyzer()),
            poseValidatorProvider.overrideWithValue(_FakePoseValidator()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 2.0,
              maxScaleFactor: 2.0,
              child: child!,
            ),
            home: WtmLiveCaptureScreen(clock: () => _now),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(GradientCta), findsOneWidget);
    });
  });
}

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
