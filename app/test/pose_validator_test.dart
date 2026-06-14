import 'package:app/features/profile/pose_validator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the pure decision logic of the try-on photo validator (CLAUDE.md §21:
/// test the core paths). The ML Kit call itself is platform code; here we verify
/// the rules that decide whether a detected pose is a usable full-body shot.
void main() {
  group('PoseValidator.decide', () {
    test('no person detected -> noPerson', () {
      expect(
        PoseValidator.decide(hasPerson: false, hasHead: false, hasFeet: false),
        PoseIssue.noPerson,
      );
    });

    test('person present but head out of frame -> headNotVisible', () {
      expect(
        PoseValidator.decide(hasPerson: true, hasHead: false, hasFeet: true),
        PoseIssue.headNotVisible,
      );
    });

    test('head visible but feet missing -> feetNotVisible', () {
      expect(
        PoseValidator.decide(hasPerson: true, hasHead: true, hasFeet: false),
        PoseIssue.feetNotVisible,
      );
    });

    test('full body (person + head + feet) -> none', () {
      expect(
        PoseValidator.decide(hasPerson: true, hasHead: true, hasFeet: true),
        PoseIssue.none,
      );
    });
  });

  group('PoseCheck', () {
    test('ok only when issue is none', () {
      expect(const PoseCheck(PoseIssue.none).ok, isTrue);
      expect(const PoseCheck(PoseIssue.noPerson).ok, isFalse);
      expect(const PoseCheck(PoseIssue.feetNotVisible).ok, isFalse);
    });
  });

  test('scoreFrom no poses -> 0', () {
    expect(PoseValidator().scoreFrom(const []), 0);
  });
}
