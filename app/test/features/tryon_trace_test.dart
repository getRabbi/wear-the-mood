import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/tryon/tryon_trace.dart';

/// The measurement tool itself.
///
/// It exists to answer "where do the 1-2 minutes go" with evidence, so the two
/// things that matter are that it correlates with the backend and that it can
/// never leak anything about the user.
void main() {
  group('the correlation token', () {
    test('is the first eight characters, matching the backend rule', () {
      // The backend derives the same prefix from the same idempotency key, so
      // the app, the submit endpoint and the worker line up in a log search
      // without any of them sending the token to the others.
      expect(
        TryOnTrace.traceToken('AB12CD34-EF56-7890-ABCD-EF1234567890'),
        'ab12cd34',
      );
    });

    test('strips separators the same way the backend does', () {
      expect(TryOnTrace.traceToken('--ab-12-cd-34-ef--'), 'ab12cd34');
    });

    test('is a PREFIX, never the whole key', () {
      // Dashed, like the uuid4 the controller actually mints. A bare
      // 32-hex-char literal here reads to a secret scanner as a high-entropy
      // credential assigned to something called `key` — which is exactly what
      // it is not.
      const idempotency = 'ab12cd34-ef56-7890-abcd-ef1234567890';
      final token = TryOnTrace.traceToken(idempotency);
      expect(token.length, 8);
      expect(
        idempotency.startsWith(token) && token != idempotency,
        isTrue,
        reason: 'enough to correlate, far too little to replay',
      );
    });

    test('degrades safely rather than throwing', () {
      expect(TryOnTrace.traceToken(''), 'none');
      expect(TryOnTrace.traceToken('---'), 'none');
      expect(TryOnTrace.traceToken('ab'), 'ab');
    });
  });

  group('stages', () {
    test('record elapsed and delta from the tap', () async {
      final trace = TryOnTrace('ab12cd34ef')..mark(TryOnStages.tap);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      trace.mark(TryOnStages.bodyResolved);

      final stages = trace.stages;
      expect(stages.map((s) => s.name), [
        TryOnStages.tap,
        TryOnStages.bodyResolved,
      ]);
      expect(stages.last.elapsedMs, greaterThanOrEqualTo(15));
      expect(stages.last.deltaMs, greaterThanOrEqualTo(15));
    });

    test('the first mark of a name wins', () {
      // A rebuild, a retried listener or a second poll must not distort the
      // numbers by re-stamping a stage that already happened.
      final trace = TryOnTrace('abc')
        ..mark(TryOnStages.firstPoll)
        ..mark(TryOnStages.firstPoll)
        ..mark(TryOnStages.firstPoll);

      expect(
        trace.stages.where((s) => s.name == TryOnStages.firstPoll).length,
        1,
      );
    });

    test('an optional integer rides along, and nothing else can', () {
      final trace = TryOnTrace('abc')..mark(TryOnStages.terminal, 14);
      expect(trace.stages.single.value, 14);
      // The API takes a String name from a fixed vocabulary and an int. There
      // is deliberately no free-text field for a URL or a filename to reach.
      expect(trace.render(), contains('terminal='));
      expect(trace.render(), contains('(14)'));
    });
  });

  group('the rendered line', () {
    test('carries only the token, durations and counts', () {
      final trace = TryOnTrace('ab12cd34ef567890')
        ..mark(TryOnStages.tap)
        ..mark(TryOnStages.bodyResolved)
        ..mark(TryOnStages.submitSent)
        ..mark(TryOnStages.submitAccepted)
        ..mark(TryOnStages.terminal, 8);

      final line = trace.render();

      expect(line, startsWith('tryon.client trace=ab12cd34'));
      expect(line, contains('total='));
      // Nothing that could identify a person or a resource.
      expect(line, isNot(contains('http')));
      expect(line, isNot(contains('.jpg')));
      expect(line, isNot(contains('@'))); // no address-shaped text
      expect(
        line,
        isNot(contains('ab12cd34ef567890')),
        reason: 'the full idempotency key must never be logged',
      );
    });

    test('is one line, so it can be copied out of a device log', () {
      final trace = TryOnTrace('abc')
        ..mark(TryOnStages.tap)
        ..mark(TryOnStages.uiVisible);
      expect(trace.render().contains('\n'), isFalse);
    });
  });
}
