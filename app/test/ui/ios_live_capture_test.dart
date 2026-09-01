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
  _FakeCamera({
    required this.file,
    this.failCapture = false,
    this.lens = CameraLens.front,
  });

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
  final CameraLens lens;

  @override
  double get previewAspectRatio => 3 / 4;

  /// Keyed by lens, so a test can prove WHICH preview is on screen rather
  /// than inferring it from the label next to it.
  @override
  Widget buildPreview() => ColoredBox(
    key: ValueKey('preview-${lens.name}'),
    color: const Color(0xFF222222),
  );

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

/// Hands out one [_FakeCamera] per lens and records every open.
///
/// It deliberately returns a DISTINCT camera object per lens and keeps them
/// all, so a test can assert which lens is live, that the previous one was
/// disposed exactly once, and that a rapid double tap did not quietly create a
/// second controller nobody owns.
class _FakeOpener implements LiveCameraOpener {
  _FakeOpener(
    _FakeCamera? front, {
    this.failure,
    _FakeCamera? rear,
    Set<CameraLens>? lenses,
    this.openDelay = Duration.zero,
  }) : _cameras = {CameraLens.front: ?front, CameraLens.rear: ?rear},
       lenses = lenses ?? {CameraLens.front, if (rear != null) CameraLens.rear};

  final Map<CameraLens, _FakeCamera> _cameras;
  final LiveCameraFailure? failure;

  /// What this fake device reports having. Independent of [_cameras] so a test
  /// can also model "claims two lenses, second one fails to open".
  final Set<CameraLens> lenses;

  /// Holds a SWITCH in flight so a test can fire a second tap underneath it.
  ///
  /// Deliberately not applied to the first open: the test needs to reach a
  /// live preview (and therefore a switch control) before it can tap one, and
  /// a slow initial open would just make getting there harder without testing
  /// anything.
  final Duration openDelay;

  int opens = 0;
  int enumerations = 0;
  final List<CameraLens> opened = [];

  _FakeCamera? get front => _cameras[CameraLens.front];
  _FakeCamera? get rear => _cameras[CameraLens.rear];

  @override
  Future<Set<CameraLens>> availableLenses() async {
    enumerations++;
    final f = failure;
    if (f != null) throw LiveCameraException(f, 'scripted');
    return lenses;
  }

  @override
  Future<LiveCamera> open(CameraLens lens) async {
    opens++;
    opened.add(lens);
    if (opens > 1 && openDelay > Duration.zero) {
      await Future<void>.delayed(openDelay);
    }
    final f = failure;
    if (f != null) throw LiveCameraException(f, 'scripted');
    final camera = _cameras[lens];
    if (camera == null) {
      throw LiveCameraException(
        LiveCameraFailure.unavailable,
        'no ${lens.name} camera',
      );
    }
    return camera;
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

/// Drains the one error a successful Retake is allowed to produce.
///
/// Leaving the review screen does not cancel a decode already in flight, so
/// the `Image.file` for the capture Retake just DELETED can still fail with
/// `PathNotFoundException`. That is the deletion working, not a defect — but
/// an unclaimed framework error fails the test, so it is absorbed explicitly
/// and nothing else is.
void absorbDecodeAfterDelete(WidgetTester tester) {
  for (var i = 0; i < 4; i++) {
    final e = tester.takeException();
    if (e == null) return;
    expect(
      e,
      isA<PathNotFoundException>(),
      reason: 'only a decode-after-delete may surface here',
    );
  }
}

/// The horizontal scale actually applied to the live preview.
///
/// -1 means the preview is mirrored, 1 means it is not. Read off the painted
/// [Transform] rather than from screen state, because mirroring is a claim
/// about what the user sees.
double _previewScaleX(WidgetTester tester, CameraLens lens) {
  final preview = find.byKey(ValueKey('preview-${lens.name}'));
  expect(
    preview,
    findsOneWidget,
    reason: 'the ${lens.name} preview is not on screen',
  );
  final transform = tester.widget<Transform>(
    find.ancestor(of: preview, matching: find.byType(Transform)).first,
  );
  return transform.transform.storage[0];
}

/// The switch control, addressed the way an assistive user would reach it.
final _switchToRear = find.bySemanticsLabel('Switch to rear camera');
final _switchToFront = find.bySemanticsLabel('Switch to front camera');

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
    // Two duration pumps, interleaved with microtask drains.
    //
    // Opening a lens is a multi-hop chain (enumerate, then open, then start
    // the stream), and a zero-duration pump drains microtasks WITHOUT
    // advancing the clock. With only one duration pump, a timer scheduled by a
    // later hop — an opener that models a slow `initialize()` — would never
    // fire. `pumpAndSettle` is not usable here: the fallback timer is a
    // `Timer.periodic`, which it would wait on for ever.
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
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
      expect(opener.opened, [CameraLens.front]);
      expect(camera.lens, CameraLens.front);
      expect(camera.streaming, isTrue);
      // The lens is named. This device has only one, so there is no switch.
      expect(find.text('Front camera'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch to rear camera'), findsNothing);
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

  group('front and rear lenses', () {
    /// A device that really has both lenses.
    _FakeOpener bothLenses() => _FakeOpener(
      _FakeCamera(file: captureFile()),
      rear: _FakeCamera(file: captureFile(), lens: CameraLens.rear),
    );

    testWidgets('opens on FRONT and offers the switch when both lenses exist', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      expect(opener.opened, [CameraLens.front], reason: 'front is the default');
      expect(
        opener.enumerations,
        1,
        reason: 'lenses are enumerated, not assumed',
      );
      expect(find.text('Front camera'), findsOneWidget);
      expect(_switchToRear, findsOneWidget);
      // Still no gallery, files or import — the switch adds a LENS, not a
      // source.
      for (final banned in [
        'Gallery',
        'Photos',
        'Library',
        'Files',
        'Import',
        'Browse',
      ]) {
        expect(find.textContaining(banned), findsNothing, reason: banned);
      }
    });

    testWidgets('a single-lens device gets NO switch control', (tester) async {
      // Front only — an iPad or a simulator with no rear camera.
      final opener = _FakeOpener(_FakeCamera(file: captureFile()));
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      expect(opener.lenses, {CameraLens.front});
      expect(_switchToRear, findsNothing);
      expect(_switchToFront, findsNothing);
    });

    testWidgets('front -> rear -> front opens each lens exactly once per tap', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      await tester.tap(_switchToRear);
      await settle(tester);
      expect(opener.opened, [CameraLens.front, CameraLens.rear]);
      expect(find.text('Rear camera'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-rear')), findsOneWidget);

      await tester.tap(_switchToFront);
      await settle(tester);
      expect(opener.opened, [
        CameraLens.front,
        CameraLens.rear,
        CameraLens.front,
      ]);
      expect(find.text('Front camera'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-front')), findsOneWidget);
    });

    testWidgets('the FRONT preview is mirrored and the REAR one is not', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      // Selfie framing only works if the preview moves with the user.
      expect(_previewScaleX(tester, CameraLens.front), -1);

      await tester.tap(_switchToRear);
      await settle(tester);
      // A helper is looking past the phone at the real person; mirroring would
      // have them correcting the framing the wrong way.
      expect(_previewScaleX(tester, CameraLens.rear), 1);
    });

    testWidgets('the old session is stopped then disposed EXACTLY once', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      final front = opener.front!;

      await tester.tap(_switchToRear);
      await settle(tester);

      expect(
        front.stopFrameCalls,
        greaterThan(0),
        reason: 'frames stopped first',
      );
      expect(front.disposeCalls, 1, reason: 'disposed exactly once');
      expect(front.streaming, isFalse);
      // ...and analysis restarted on the NEW one, only after it opened.
      expect(opener.rear!.streaming, isTrue);
    });

    testWidgets('rapid switch taps create ONE new controller, not several', (
      tester,
    ) async {
      final opener = _FakeOpener(
        _FakeCamera(file: captureFile()),
        rear: _FakeCamera(file: captureFile(), lens: CameraLens.rear),
        openDelay: const Duration(milliseconds: 300),
      );
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      final opensAfterStart = opener.opens;

      // Three taps on the SAME SPOT while the first switch is still in
      // flight. Tapped by position rather than by finder on purpose: the
      // control correctly stops being interactive the moment the switch
      // starts, so a finder would not resolve — but a real thumb lands on the
      // pixels regardless, which is the input this guard has to survive.
      final spot = tester.getCenter(_switchToRear);
      await tester.tap(_switchToRear);
      await tester.pump();
      await tester.tapAt(spot);
      await tester.pump();
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      expect(
        opener.opens - opensAfterStart,
        1,
        reason: 'a second open would leak a controller nobody disposes',
      );
      expect(opener.front!.disposeCalls, 1);
      // Exactly one rear session exists, and it is the live one.
      expect(
        opener.opened.where((l) => l == CameraLens.rear).length,
        1,
        reason: 'a second rear open would be an orphaned controller',
      );
      expect(opener.rear!.disposeCalls, 0);
      expect(find.text('Rear camera'), findsOneWidget);
    });

    testWidgets('a running countdown is cancelled BEFORE the switch', (
      tester,
    ) async {
      final opener = bothLenses();
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(tester, opener: opener, analyzer: analyzer);
      await openCamera(tester);

      // Get a countdown genuinely running.
      await feed(tester, opener.front!, count: 4);
      expect(_countdownDigit, findsOneWidget);

      await tester.tap(_switchToRear);
      await settle(tester);

      // No numeral, and — the part that matters — no shutter fired on a lens
      // the user did not choose.
      expect(_countdownDigit, findsNothing);
      expect(opener.front!.takePictureCalls, 0);
      expect(opener.rear!.takePictureCalls, 0);
    });

    testWidgets('rear mode runs NO countdown, however good the framing is', (
      tester,
    ) async {
      final opener = bothLenses();
      final analyzer = _ScriptedAnalyzer()
        ..next = const LiveFramingCheck(LiveFramingIssue.none, score: 92);
      await mount(tester, opener: opener, analyzer: analyzer);
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);

      // Perfect framing, held for a long time. A helper is about to press the
      // button; the app must not race them.
      await feed(tester, opener.rear!, count: 10);
      expect(_countdownDigit, findsNothing);
      expect(opener.rear!.takePictureCalls, 0);
      // The 10-second timer belongs to solo capture and is gone too.
      expect(find.text('Start 10-second timer'), findsNothing);
    });

    testWidgets('rear mode shows the helper guidance and a real shutter', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);

      expect(find.text('Ask someone to help'), findsOneWidget);
      expect(
        find.textContaining('frame your full body from head to feet'),
        findsOneWidget,
      );
      expect(find.text('Take photo'), findsOneWidget);
    });

    testWidgets('the rear shutter takes ONE high-resolution still', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);

      await tester.tap(find.text('Take photo'));
      await settle(tester);

      expect(opener.rear!.takePictureCalls, 1);
      // Straight to the same review screen the solo flow reaches.
      expect(find.text('Use this photo'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('rapid shutter taps still take exactly ONE photo', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);

      final shutter = find.text('Take photo');
      await tester.tap(shutter);
      await tester.tap(shutter, warnIfMissed: false);
      await tester.tap(shutter, warnIfMissed: false);
      await settle(tester);

      expect(opener.rear!.takePictureCalls, 1);
    });

    testWidgets('Retake reopens the lens the photo was TAKEN on', (
      tester,
    ) async {
      final opener = bothLenses();
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);
      await tester.tap(find.text('Take photo'));
      await settle(tester);

      // Counted BEFORE the retake, so the assertion below cannot pass on the
      // strength of the earlier switch.
      final opensBefore = opener.opened.length;

      await tester.tap(find.text('Retake'));
      // Retake deletes the abandoned capture — real file I/O, which pumped
      // frames do not advance. Give the real event loop a turn, twice, so this
      // does not become load-sensitive when the suite runs in parallel.
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle(tester);
      }
      absorbDecodeAfterDelete(tester);

      // Rear, not the solo default — the helper is still holding the phone.
      expect(opener.opened.length, opensBefore + 1, reason: 'reopened once');
      expect(opener.opened.last, CameraLens.rear);
      expect(find.text('Rear camera'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);
    });

    testWidgets('a NEW capture flow starts on the front lens again', (
      tester,
    ) async {
      // First flow: switch to rear and leave.
      final first = bothLenses();
      await mount(tester, opener: first, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      await tester.tap(_switchToRear);
      await settle(tester);
      expect(first.opened.last, CameraLens.rear);
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await settle(tester);

      // A brand-new screen must not inherit that choice.
      final second = bothLenses();
      await mount(tester, opener: second, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);
      expect(second.opened, [CameraLens.front]);
      expect(find.text('Front camera'), findsOneWidget);
    });

    testWidgets('backgrounding during a switch leaks no controller', (
      tester,
    ) async {
      final opener = _FakeOpener(
        _FakeCamera(file: captureFile()),
        rear: _FakeCamera(file: captureFile(), lens: CameraLens.rear),
        openDelay: const Duration(milliseconds: 300),
      );
      await mount(tester, opener: opener, analyzer: _ScriptedAnalyzer());
      await openCamera(tester);

      await tester.tap(_switchToRear);
      await tester.pump();
      // The OS takes the capture device away mid-switch.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      // Both sessions accounted for: the old one torn down, and the one that
      // finished opening into a backgrounded screen closed rather than kept.
      expect(opener.front!.disposeCalls, 1);
      expect(opener.rear!.disposeCalls, 1);
      expect(opener.rear!.streaming, isFalse);
    });

    for (final device in const [
      (name: 'iPhone SE', size: Size(750, 1334), dpr: 2.0),
      (name: 'iPhone 15 Pro', size: Size(1179, 2556), dpr: 3.0),
      (name: 'iPad Air 11-inch portrait', size: Size(1640, 2360), dpr: 2.0),
      (name: 'iPad Air 11-inch landscape', size: Size(2360, 1640), dpr: 2.0),
    ]) {
      testWidgets('${device.name}: rear mode does not overflow', (
        tester,
      ) async {
        await mount(
          tester,
          opener: bothLenses(),
          analyzer: _ScriptedAnalyzer(),
          size: device.size,
          dpr: device.dpr,
        );
        await openCamera(tester);
        await tester.tap(_switchToRear);
        await settle(tester);

        expect(tester.takeException(), isNull);
        // The helper guidance and the shutter both fit — a rear mode whose
        // only control is off-screen is not usable by the person holding it.
        expect(find.text('Ask someone to help'), findsOneWidget);
        expect(find.text('Take photo'), findsOneWidget);
      });
    }
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
      // alone do not let that complete, so the real event loop gets a turn —
      // twice, with a real (not fake) delay. A single zero-duration turn was
      // enough on an idle machine and intermittently short of it when the rest
      // of the suite was running in parallel, which is a flaky test rather
      // than a real signal.
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle(tester);
      }
      absorbDecodeAfterDelete(tester);

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
      expect(find.textContaining('taken live in the app'), findsOneWidget);
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
