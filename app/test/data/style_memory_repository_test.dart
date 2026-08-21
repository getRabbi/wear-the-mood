import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/style_memory.dart';
import 'package:app/data/repositories/style_memory_repository.dart';

import '../helpers/fake_dio.dart';

/// Style Memory over the wire, and the honesty rules the UI depends on.
///
/// The one that matters most: [StyleMemoryRepository.submitFeedback] must never
/// look like a refund request. It posts a verdict and a reason and nothing
/// else — no amount, no credit field, no job id — because a render that reached
/// the result screen already succeeded, and disliking it is a taste signal
/// rather than money (RETENTION spec §19.3).
void main() {
  Map<String, dynamic> bodyOf(FakeAdapter adapter) =>
      jsonDecode(jsonEncode(adapter.lastRequest!.data)) as Map<String, dynamic>;

  group('feedback', () {
    test('a keep posts only the verdict', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'result_id': 'r1',
          'outcome': 'kept',
          'recorded': true,
        }),
      );
      final result = await StyleMemoryRepository(
        dio,
      ).submitFeedback(resultId: 'r1', kept: true);

      expect(result?.outcome, 'kept');
      expect(adapter.lastRequest!.path, '/v1/tryon/results/r1/feedback');
      expect(bodyOf(adapter), {'outcome': 'kept'});
    });

    test('a rejection carries its structured reason', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'result_id': 'r1',
          'outcome': 'rejected',
          'recorded': true,
        }),
      );
      await StyleMemoryRepository(dio).submitFeedback(
        resultId: 'r1',
        kept: false,
        reason: RejectionReason.notMyStyle,
      );

      // The WIRE value, never the Dart enum name.
      expect(bodyOf(adapter)['reason'], 'not_my_style');
    });

    test('nothing about credits is ever sent', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'result_id': 'r1',
          'outcome': 'rejected',
          'recorded': true,
        }),
      );
      await StyleMemoryRepository(dio).submitFeedback(
        resultId: 'r1',
        kept: false,
        reason: RejectionReason.identityIssue,
      );

      final keys = bodyOf(adapter).keys.toSet();
      expect(keys.any((k) => k.contains('credit')), isFalse);
      expect(keys.any((k) => k.contains('refund')), isFalse);
    });

    test('a deleted result is not an error the user has to see', () async {
      final (dio, _) = fakeDio((_) => jsonResponse({}, status: 404));
      final result = await StyleMemoryRepository(
        dio,
      ).submitFeedback(resultId: 'gone', kept: true);
      expect(result, isNull);
    });

    test(
      'the learned line is carried through when the server sends one',
      () async {
        final (dio, _) = fakeDio(
          (_) => jsonResponse({
            'result_id': 'r1',
            'outcome': 'kept',
            'recorded': true,
            'learned': 'Lately you seem to lean toward black tones.',
          }),
        );
        final result = await StyleMemoryRepository(
          dio,
        ).submitFeedback(resultId: 'r1', kept: true);
        expect(result?.learned, contains('lean toward'));
      },
    );
  });

  group('signals', () {
    test('a flag-off 404 is a silent no-op, not a failure', () async {
      final (dio, _) = fakeDio((_) => jsonResponse({}, status: 404));
      final result = await StyleMemoryRepository(
        dio,
      ).recordSignal(signalType: 'keep_look');
      expect(result, isNull);
    });

    test('a dedupe key rides along so a retry cannot count twice', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({'recorded': true, 'profile': <String, dynamic>{}}),
      );
      await StyleMemoryRepository(
        dio,
      ).recordSignal(signalType: 'keep_look', dedupeKey: 'result-1:kept');
      expect(bodyOf(adapter)['dedupe_key'], 'result-1:kept');
    });
  });

  group('profile parsing', () {
    test('an empty profile is a legitimate state, not an error', () {
      final profile = StyleMemoryProfile.fromJson(const {});
      expect(profile.isEmpty, isTrue);
      expect(profile.preferenceSummary, isNull);
      expect(profile.facets.every((f) => f.items.isEmpty), isTrue);
    });

    test('a weak inference is not confident enough to state', () {
      const item = PreferenceItem(value: 'black', confidence: 0.2);
      expect(item.isConfident, isFalse);
      expect(item.isStated, isFalse);
    });

    test('a stated preference is always confident', () {
      const item = PreferenceItem(
        value: 'olive',
        confidence: 0,
        source: 'stated',
      );
      expect(item.isStated, isTrue);
      expect(item.isConfident, isTrue);
    });

    test('facets expose the API key, not display text', () {
      final profile = StyleMemoryProfile.fromJson(const {
        'preferred_colors': [
          {
            'value': 'black',
            'weight': 3.0,
            'confidence': 0.6,
            'source': 'inferred',
          },
        ],
      });
      final colors = profile.facets.firstWhere(
        (f) => f.facet == 'preferred_colors',
      );
      expect(colors.items.single.value, 'black');
      // The correction endpoint takes this exact string.
      expect(colors.facet, 'preferred_colors');
    });
  });
}
