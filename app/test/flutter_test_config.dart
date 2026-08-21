import 'dart:async';

import 'package:flutter/foundation.dart';

/// Global test setup, applied automatically to every test under `test/`.
///
/// It exists for one reason: `flutter_cache_manager` opens a sqflite database
/// the first time an image cache is consulted, and sqflite has no
/// implementation on a test host — there is no plugin registrant, so
/// `databaseFactory` is never set and the open throws
/// `Bad state: databaseFactory not initialized`.
///
/// That throw arrives ASYNCHRONOUSLY, several suspensions after whatever
/// rendered the image, so a test cannot catch it at any particular line — by
/// the time it lands the widget under test is long finished. It also only
/// surfaces on macOS, which is the single host where an iOS release is cut, so
/// it passed on Windows and on the ubuntu CI runner and failed exactly where it
/// was most expensive.
///
/// Nothing under test depends on the disk cache; the widgets are only being
/// asked to draw an image. So the error is dropped — and ONLY this error,
/// matched on its message, with every other failure handed straight back to the
/// framework's own reporter.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains(
      'databaseFactory not initialized',
    )) {
      return;
    }
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  await testMain();
}
