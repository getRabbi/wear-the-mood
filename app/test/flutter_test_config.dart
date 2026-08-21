import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Global test setup, applied automatically by Flutter to every test under
/// `test/`.
///
/// `flutter_cache_manager` — reached through `cached_network_image` — opens a
/// sqflite database the first time an image cache is consulted. On a device the
/// sqflite plugin is registered and that works. On a test host there is no
/// registrant, so `databaseFactory` is unset and the open throws
/// `Bad state: databaseFactory not initialized`.
///
/// That throw could not be caught. It is an uncaught ASYNCHRONOUS error in the
/// test zone, reported by the binding's own reporter ("EXCEPTION CAUGHT BY
/// FLUTTER TEST FRAMEWORK") rather than routed through `FlutterError.onError`,
/// so `takeException()` and every `FlutterError.onError` override missed it.
/// It also lands on whichever test is running when the cache chain resolves, so
/// skipping the affected test simply moved the failure to the next one.
///
/// Giving the test host a real database engine removes the cause instead of
/// chasing the symptom, and is exactly what the error message prescribes. It is
/// a dev dependency: nothing here is compiled into the app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await testMain();
}
