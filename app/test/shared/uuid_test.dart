import 'package:flutter_test/flutter_test.dart';

import 'package:app/shared/utils/uuid.dart';

void main() {
  final re = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('uuidV4 produces a valid v4 UUID', () {
    expect(re.hasMatch(uuidV4()), isTrue);
  });

  test('uuidV4 is (practically) unique', () {
    final keys = List.generate(1000, (_) => uuidV4()).toSet();
    expect(keys.length, 1000);
  });
}
