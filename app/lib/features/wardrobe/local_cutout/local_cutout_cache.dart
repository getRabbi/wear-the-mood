/// Ownership of the local-cutout temp files (local BG §4, §8.4; blocker R10b).
///
/// **Cleanup is by OPERATION ID, never by path.** Native writes the mask and
/// cutout PNGs into a per-operation directory inside an app-owned cache root and
/// hands back the two file paths so Dart can show the preview and upload the
/// mask. It does **not** hand back a directory for Dart to delete, and Dart never
/// asks for a path to be deleted.
///
/// The reason is blunt: a `cleanup(path)` contract would be a filesystem delete
/// primitive reachable from Dart, scoped only by the app sandbox. A malformed or
/// hostile value — `../../databases`, an absolute path, a symlink — would be
/// honoured because "native returned it". So identifiers flow in, paths flow out,
/// and the native side re-validates the id against a strict pattern and proves
/// canonical containment before touching anything.
///
/// Dart still OWNS the lifetime: it must call [disposeOperation] on every terminal
/// path — success, failure, cancellation, widget disposal — and [sweepStale] once
/// per session to clear whatever a crash or force-kill orphaned.
library;

import 'local_cutout_platform.dart';

/// Requests deletion of local-cutout scratch files through the platform.
///
/// Fully testable with a fake platform: no filesystem access happens in Dart.
class LocalCutoutCache {
  const LocalCutoutCache(this._platform);

  final LocalCutoutPlatform _platform;

  /// How long an orphaned operation directory may survive before a sweep takes
  /// it. Generous enough that a slow in-flight run is never deleted underneath
  /// itself, short enough that a crash does not leave images on disk for long.
  static const Duration defaultMaxAge = Duration(hours: 6);

  /// Delete one operation's files.
  ///
  /// Idempotent and never throws — cleanup runs on teardown paths where an
  /// exception helps nobody. A null/blank id is a no-op, and an id the native
  /// side rejects simply reports false.
  Future<bool> disposeOperation(String? operationId) async {
    final id = operationId?.trim() ?? '';
    if (id.isEmpty) return false;
    try {
      await _platform.cleanup(id);
      return true;
    } on Object {
      // A failed cleanup is picked up by the next stale sweep.
      return false;
    }
  }

  /// Delete every operation directory older than [maxAge]; returns how many went.
  ///
  /// Call once after the closet is ready, not on the add path — it is recovery
  /// for a previous session, not part of this one.
  Future<int> sweepStale({Duration maxAge = defaultMaxAge}) async {
    try {
      return await _platform.sweepCache(maxAge: maxAge);
    } on Object {
      return 0;
    }
  }
}
