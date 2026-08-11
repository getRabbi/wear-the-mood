import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where one try-on's time actually goes, on the client half (CLAUDE.md §14).
///
/// A logical try-on spans three processes — this app, the submit endpoint and a
/// scale-to-zero worker — so the only way to read it as one story is a shared
/// correlation token and the same log shape in each. The token is the first
/// eight characters of the request's idempotency key, which the backend derives
/// independently from the same value, so the three lines line up in a search.
///
/// **Privacy (§10, §11, §14).** A trace records DURATIONS and COUNTS. It is
/// never handed an image, a signed URL, a token, or anything identifying a
/// person, and [mark] deliberately has no free-text field to smuggle one in.
///
/// **Cost.** One `Stopwatch` read and a list append per stage, and one
/// `debugPrint` per run in debug builds only. Nothing here makes a request,
/// creates a job, or changes behaviour in any way.
@immutable
class TryOnStage {
  const TryOnStage(this.name, this.elapsedMs, this.deltaMs, [this.value]);

  /// Fixed-vocabulary stage name, e.g. `submit_accepted`.
  final String name;

  /// Milliseconds since the user tapped Generate.
  final int elapsedMs;

  /// Milliseconds since the previous stage.
  final int deltaMs;

  /// An optional integer for the stage — a poll count, a byte size. Never a
  /// string, and never anything derived from user content.
  final int? value;
}

/// The stage names the try-on client records, so a reader knows the full set.
abstract final class TryOnStages {
  /// Generate tapped. Always t=0.
  static const tap = 'tap';

  /// The chosen body photo / studio model resolved to a URL.
  static const bodyResolved = 'body_resolved';

  /// The generating screen is on screen — the user's first visible feedback.
  static const uiVisible = 'ui_visible';

  /// `POST /v1/tryon` sent.
  static const submitSent = 'submit_sent';

  /// 202 received: the job exists and credits are reserved.
  static const submitAccepted = 'submit_accepted';

  /// The first status check after the job was accepted.
  static const firstPoll = 'first_poll';

  /// A terminal status came back. Carries the number of polls it took.
  static const terminal = 'terminal';

  /// The result image has painted its first frame.
  static const resultRendered = 'result_rendered';
}

/// One try-on's client-side timings.
class TryOnTrace {
  TryOnTrace(String idempotencyKey) : token = traceToken(idempotencyKey);

  /// The eight-character correlation token shared with the backend.
  final String token;
  final Stopwatch _clock = Stopwatch()..start();
  final List<TryOnStage> _stages = <TryOnStage>[];
  int _lastMs = 0;

  List<TryOnStage> get stages => List.unmodifiable(_stages);

  /// Derive the correlation token the backend also derives, so the two agree
  /// without either sending it. A PREFIX by design: enough to correlate, far
  /// too little to replay a request with.
  static String traceToken(String idempotencyKey) {
    final cleaned = idempotencyKey
        .toLowerCase()
        .split('')
        .where(
          (c) =>
              (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) ||
              (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7a),
        )
        .join();
    if (cleaned.isEmpty) return 'none';
    return cleaned.length <= 8 ? cleaned : cleaned.substring(0, 8);
  }

  /// Record a stage. Idempotent per name: the first one wins, so a rebuild or a
  /// retried listener cannot distort the numbers.
  void mark(String name, [int? value]) {
    if (_stages.any((s) => s.name == name)) return;
    final elapsed = _clock.elapsedMilliseconds;
    _stages.add(TryOnStage(name, elapsed, elapsed - _lastMs, value));
    _lastMs = elapsed;
  }

  int get totalMs => _clock.elapsedMilliseconds;

  /// One copyable line, in the same shape as the backend's.
  ///
  /// `stage=<since previous>ms(<value>)+<since tap>` — the running total is what
  /// makes "the button did nothing for two seconds" readable at a glance.
  /// Deliberately contains no `@`, `http`, or file extension, so a line can be
  /// pasted anywhere without a second look.
  String render() {
    final parts = _stages
        .map(
          (s) =>
              '${s.name}=${s.deltaMs}ms'
              '${s.value != null ? '(${s.value})' : ''}'
              '+${s.elapsedMs}',
        )
        .join(' ');
    return 'tryon.client trace=$token total=${totalMs}ms $parts';
  }
}

/// Where a finished trace goes.
///
/// Behind a provider so a test can capture instead of print, and so a future
/// build could route this at an analytics sink without touching a call site.
typedef TryOnTraceSink = void Function(TryOnTrace trace);

/// Debug builds print; release builds drop it.
///
/// Deliberately NOT wired to Sentry or PostHog: this is a measurement tool for
/// a device run, not production telemetry, and shipping a per-render log to a
/// third party is not something to do quietly.
void _debugPrintTrace(TryOnTrace trace) {
  if (kDebugMode) debugPrint('[WTM-TIMING] ${trace.render()}');
}

final tryOnTraceSinkProvider = Provider<TryOnTraceSink>(
  (ref) => _debugPrintTrace,
);
