/// Ownership of the local-cutout temp files (local BG §4, §8.4).
///
/// The native engines write a mask PNG and a cutout PNG into a per-operation
/// directory inside the app cache and hand back paths. **Dart owns the lifetime
/// of those files** and must remove them on every terminal path — success,
/// failure, cancellation, widget disposal — plus sweep whatever a crash or a
/// force-kill left behind on the next run.
///
/// Uses `dart:io` directly rather than adding a path-provider dependency: the
/// native side already chose the cache root, so Dart only ever deletes paths it
/// was given. Every operation is best-effort and idempotent — a missing directory
/// is a success, and a cleanup failure must never fail a user's add.
library;

import 'dart:io';

/// Deletes local-cutout scratch directories.
///
/// Fully unit-testable: point it at a temp directory, no engine required.
class LocalCutoutCache {
  /// [clock] exists only so the sweep is testable: `dart:io` can set a file's
  /// modification time but not a directory's, so tests advance the clock instead
  /// of back-dating the filesystem. Production always uses the real one.
  const LocalCutoutCache({DateTime Function()? clock})
    // ignore: prefer_initializing_formals — a private field can't be a named formal.
    : _clock = clock;

  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  /// How long an orphaned operation directory may survive before a sweep takes
  /// it. Generous enough that a slow in-flight run is never deleted underneath
  /// itself, short enough that a crash does not leave images on disk for long.
  static const Duration defaultMaxAge = Duration(hours: 6);

  /// Recursively deletes one operation directory.
  ///
  /// Returns true when the directory is gone afterwards (including when it never
  /// existed). Never throws.
  Future<bool> deleteOperationDirectory(String? directoryPath) async {
    if (directoryPath == null || directoryPath.trim().isEmpty) return true;
    final dir = Directory(directoryPath);
    try {
      if (!await dir.exists()) return true;
      await dir.delete(recursive: true);
      return true;
    } on FileSystemException {
      // Locked by the OS, or a race with the native side deleting it first.
      // Whatever survives is caught by the next sweep.
      return false;
    }
  }

  /// Deletes the individual files of one operation without removing the
  /// directory — used when only the outputs need to go.
  ///
  /// Returns how many files were actually removed. Never throws.
  Future<int> deleteFiles(Iterable<String?> filePaths) async {
    var removed = 0;
    for (final path in filePaths) {
      if (path == null || path.trim().isEmpty) continue;
      final file = File(path);
      try {
        if (await file.exists()) {
          await file.delete();
          removed++;
        }
      } on FileSystemException {
        // Best-effort by design.
      }
    }
    return removed;
  }

  /// Removes every entry directly under [rootPath] last modified more than
  /// [maxAge] ago — the recovery sweep for directories a crash orphaned.
  ///
  /// Only the immediate children of [rootPath] are considered, so this can never
  /// walk out of the cache root. Returns how many entries were removed; never
  /// throws, and a missing root is simply zero.
  Future<int> sweepStale({
    required String rootPath,
    Duration maxAge = defaultMaxAge,
  }) async {
    final root = Directory(rootPath);
    var removed = 0;
    try {
      if (!await root.exists()) return 0;
      final cutoff = _now.subtract(maxAge);
      await for (final entity in root.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isAfter(cutoff)) continue;
          await entity.delete(recursive: true);
          removed++;
        } on FileSystemException {
          // Skip this entry; the next sweep retries it.
        }
      }
    } on FileSystemException {
      // An unreadable cache root is not an error worth surfacing.
    }
    return removed;
  }
}
