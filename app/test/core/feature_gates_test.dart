import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/config/feature_gates.dart';

void main() {
  test('cutout editor gate defaults OFF without a --dart-define', () {
    // The gate is a compile-time const: an un-flagged build — including every
    // already-shipped production build — never exposes "Fix cutout" or the editor.
    // It is only true when built with --dart-define=CUTOUT_EDITOR_ENABLED=true.
    expect(kCutoutEditorEnabled, isFalse);
  });

  group('local-first background removal gates', () {
    // These ship dormant. `flutter test` runs with no --dart-define, so this is
    // exactly the state of an un-flagged build: local removal is compiled out and
    // Add Garment keeps using the existing Azure BiRefNet flow.
    test('master gate defaults OFF', () {
      expect(kLocalBgRemovalEnabled, isFalse);
    });

    test('both platform arms default OFF', () {
      expect(kLocalBgAndroidEnabled, isFalse);
      expect(kLocalBgIosEnabled, isFalse);
    });

    test('no local gate is on in a default build', () {
      // One assertion that fails loudly if ANY of the three is ever given a
      // true default — the single change that could ship the feature by accident.
      expect([
        kLocalBgRemovalEnabled,
        kLocalBgAndroidEnabled,
        kLocalBgIosEnabled,
      ], everyElement(isFalse));
    });
  });
}
