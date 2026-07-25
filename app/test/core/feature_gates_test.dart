import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/config/feature_gates.dart';

void main() {
  test('cutout editor gate defaults OFF without a --dart-define', () {
    // The gate is a compile-time const: an un-flagged build — including every
    // already-shipped production build — never exposes "Fix cutout" or the editor.
    // It is only true when built with --dart-define=CUTOUT_EDITOR_ENABLED=true.
    expect(kCutoutEditorEnabled, isFalse);
  });
}
