import 'package:app/core/media/image_pick_permission.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isImagePermissionDenied', () {
    test('matches image_picker denial/restriction codes', () {
      for (final code in [
        'camera_access_denied',
        'photo_access_denied',
        'camera_access_restricted',
        'photo_access_restricted',
      ]) {
        expect(
          isImagePermissionDenied(PlatformException(code: code)),
          isTrue,
          reason: '$code is an OS permission denial',
        );
      }
    });

    test('does not swallow unrelated platform errors', () {
      expect(
        isImagePermissionDenied(PlatformException(code: 'multiple_request')),
        isFalse,
      );
      expect(isImagePermissionDenied(StateError('boom')), isFalse);
      expect(isImagePermissionDenied('camera_access_denied'), isFalse);
    });
  });
}
