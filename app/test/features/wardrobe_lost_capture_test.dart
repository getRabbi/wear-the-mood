import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/features/wardrobe/wardrobe_image_service.dart';

/// Recovering a capture Android threw away.
///
/// On a fresh install on a mid-range phone, launching the camera can get our
/// activity reclaimed: the photo is taken, the process is rebuilt, and the
/// result is dropped. The user sees nothing happen and taps again — which is
/// exactly the "works from the second attempt" report. `retrieveLostData` is the
/// official recovery, and it is self-clearing, so a photo that already arrived
/// normally can never be handled twice.
class _FakePicker implements ImagePicker {
  _FakePicker({this.lost, this.throwsOnRetrieve = false});

  LostDataResponse? lost;
  bool throwsOnRetrieve;
  int retrieveCalls = 0;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveCalls++;
    if (throwsOnRetrieve) throw StateError('platform blew up');
    final response = lost ?? LostDataResponse.empty();
    // The real platform hands each lost result over ONCE and then forgets it.
    lost = null;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WardrobeImageService service(_FakePicker picker) =>
      WardrobeImageService(_NullSupabase(), picker: picker);

  group('recoverLostCapture', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('nothing lost → null, and the screen carries on', () async {
      final picker = _FakePicker();

      expect(await service(picker).recoverLostCapture(), isNull);
      expect(picker.retrieveCalls, 1);
    });

    test('an empty response is not treated as a photo', () async {
      final picker = _FakePicker(lost: LostDataResponse.empty());

      expect(await service(picker).recoverLostCapture(), isNull);
    });

    test('a platform failure never throws at the user', () async {
      // Someone who has not done anything yet must not be shown an error.
      final picker = _FakePicker(throwsOnRetrieve: true);

      expect(await service(picker).recoverLostCapture(), isNull);
    });

    test('a lost capture is only ever handed over once', () async {
      final picker = _FakePicker(
        lost: LostDataResponse(
          file: XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'lost.jpg',
            mimeType: 'image/jpeg',
          ),
          type: RetrieveType.image,
        ),
      );
      final s = service(picker);

      // The first call consumes it (the decode itself fails on fake bytes,
      // which is fine — what matters is the platform is asked exactly once
      // per lost result and never re-serves it).
      await s.recoverLostCapture().catchError((_) => null);
      final second = await s.recoverLostCapture();

      expect(second, isNull, reason: 'no photo may be processed twice');
      expect(picker.retrieveCalls, 2);
    });

    test('it is Android-only — iOS has no equivalent loss', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final picker = _FakePicker();

      expect(await service(picker).recoverLostCapture(), isNull);
      expect(
        picker.retrieveCalls,
        0,
        reason: 'do not call a platform API that does not apply',
      );
    });
  });
}

/// The service only touches Supabase on the LEGACY upload path, which none of
/// these exercise.
class _NullSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}
