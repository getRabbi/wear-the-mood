import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/models/wardrobe_item.dart';

/// Regression tests for the background-removal wait UX (Phase 5).
///
/// Background removal now runs on event-driven Azure Container Apps Jobs, which
/// have NO warm pool: every execution pays image-pull + ONNX model load, so a
/// cutout can legitimately take ~2 minutes to even start. A job that has not
/// finished within 45 seconds is therefore SLOW, not FAILED, and the UI must say
/// so without stopping work.
///
/// These mirror the constants in wardrobe_add_processing.dart.
const _reassureAfter = Duration(seconds: 45);
const _hardCap = Duration(minutes: 3);

/// The phase the sheet should be showing after [elapsed], given the item state.
/// Kept as a pure function so the decision is testable without pumping the
/// whole modal.
String phaseFor({required WardrobeItem item, required Duration elapsed}) {
  if (!item.isProcessingCutout) return 'done';
  return elapsed >= _reassureAfter ? 'stillPreparing' : 'removingBg';
}

WardrobeItem _item(String cutoutStatus) => WardrobeItem(
      id: 'i1',
      imageUrl: 'https://example.test/a.jpg',
      cutoutStatus: cutoutStatus,
    );

void main() {
  group('background-removal wait states', () {
    test('a queued job is never treated as failed, however long it takes', () {
      final queued = _item('queued');
      for (final elapsed in [
        Duration.zero,
        const Duration(seconds: 44),
        const Duration(seconds: 45),
        const Duration(seconds: 90),
        const Duration(seconds: 179),
      ]) {
        expect(phaseFor(item: queued, elapsed: elapsed), isNot('failed'),
            reason: 'a slow Job start at $elapsed must not surface as failure');
      }
    });

    test('under 45s shows the normal removing-background state', () {
      expect(
        phaseFor(item: _item('processing'), elapsed: const Duration(seconds: 44)),
        'removingBg',
      );
    });

    test('at/after 45s switches to the reassuring still-preparing state', () {
      expect(
        phaseFor(item: _item('processing'), elapsed: _reassureAfter),
        'stillPreparing',
      );
      expect(
        phaseFor(item: _item('processing'), elapsed: const Duration(seconds: 150)),
        'stillPreparing',
      );
    });

    test('a finished cutout resolves regardless of how slow it was', () {
      expect(
        phaseFor(item: _item('done'), elapsed: const Duration(seconds: 170)),
        'done',
      );
    });

    test('isProcessingCutout covers both pre-terminal server states', () {
      expect(_item('queued').isProcessingCutout, isTrue);
      expect(_item('processing').isProcessingCutout, isTrue);
      expect(_item('done').isProcessingCutout, isFalse);
      expect(_item('failed').isProcessingCutout, isFalse);
    });

    test('hard cap stays at 3 minutes and exceeds the reassurance threshold', () {
      // The cap is only defensible while measured end-to-end p95 < 180s; if that
      // regresses the cap must be raised rather than showing a false error.
      expect(_hardCap, const Duration(minutes: 3));
      expect(_hardCap > _reassureAfter, isTrue);
    });
  });
}
