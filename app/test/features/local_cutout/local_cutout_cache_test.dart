import 'dart:io';

import 'package:app/features/wardrobe/local_cutout/local_cutout_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Temp-file ownership (local BG §4, §8.4).
///
/// Local removal writes a mask and a cutout of the user's clothing to disk. Those
/// files must not survive the operation, and a crash must not leave them there
/// indefinitely — so cleanup is tested as a feature, not assumed.
void main() {
  late Directory root;
  const cache = LocalCutoutCache();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wtm-bg-test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<Directory> makeOperation(String id) async {
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}mask.png').writeAsBytes([1, 2, 3]);
    await File('${dir.path}${Platform.pathSeparator}cutout.png').writeAsBytes([4, 5, 6]);
    return dir;
  }

  group('deleteOperationDirectory', () {
    test('removes the directory and everything in it', () async {
      final dir = await makeOperation('op-1');
      expect(await dir.exists(), isTrue);

      expect(await cache.deleteOperationDirectory(dir.path), isTrue);
      expect(await dir.exists(), isFalse);
    });

    test('is idempotent — deleting twice is still a success', () async {
      final dir = await makeOperation('op-2');
      expect(await cache.deleteOperationDirectory(dir.path), isTrue);
      expect(await cache.deleteOperationDirectory(dir.path), isTrue);
    });

    test('a never-created directory is a success, not an error', () async {
      final missing = '${root.path}${Platform.pathSeparator}never-existed';
      expect(await cache.deleteOperationDirectory(missing), isTrue);
    });

    test('null and blank paths are safe no-ops', () async {
      expect(await cache.deleteOperationDirectory(null), isTrue);
      expect(await cache.deleteOperationDirectory(''), isTrue);
      expect(await cache.deleteOperationDirectory('   '), isTrue);
      // Crucially, a blank path must not have taken the root with it.
      expect(await root.exists(), isTrue);
    });
  });

  group('deleteFiles', () {
    test('removes the files it is given and counts them', () async {
      final dir = await makeOperation('op-3');
      final mask = '${dir.path}${Platform.pathSeparator}mask.png';
      final cutout = '${dir.path}${Platform.pathSeparator}cutout.png';

      expect(await cache.deleteFiles([mask, cutout]), 2);
      expect(await File(mask).exists(), isFalse);
      expect(await File(cutout).exists(), isFalse);
      // Only the files went; the directory itself is the caller's business.
      expect(await dir.exists(), isTrue);
    });

    test('skips nulls, blanks and already-missing files', () async {
      final dir = await makeOperation('op-4');
      final mask = '${dir.path}${Platform.pathSeparator}mask.png';

      final removed = await cache.deleteFiles([
        null,
        '',
        '${dir.path}${Platform.pathSeparator}not-here.png',
        mask,
      ]);
      expect(removed, 1);
    });
  });

  group('sweepStale', () {
    test('removes an operation directory once it ages past maxAge', () async {
      final stale = await makeOperation('stale');
      // `dart:io` cannot set a directory's mtime, so advance the clock instead
      // of back-dating the filesystem.
      final later = DateTime.now().add(const Duration(hours: 9));

      final removed = await LocalCutoutCache(
        clock: () => later,
      ).sweepStale(rootPath: root.path, maxAge: const Duration(hours: 6));

      expect(removed, 1);
      expect(await stale.exists(), isFalse);
    });

    test('discriminates stale from fresh within a single sweep', () async {
      // Files DO support setLastModified, so this exercises the real cutoff
      // comparison against real mtimes with the real clock.
      final stale = File('${root.path}${Platform.pathSeparator}stale.png');
      final fresh = File('${root.path}${Platform.pathSeparator}fresh.png');
      await stale.writeAsBytes([1]);
      await fresh.writeAsBytes([2]);
      await stale.setLastModified(DateTime.now().subtract(const Duration(hours: 9)));

      final removed = await cache.sweepStale(
        rootPath: root.path,
        maxAge: const Duration(hours: 6),
      );

      expect(removed, 1);
      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    });

    test('never deletes an in-flight operation', () async {
      final inFlight = await makeOperation('running');
      final removed = await cache.sweepStale(
        rootPath: root.path,
        maxAge: const Duration(hours: 6),
      );
      expect(removed, 0);
      expect(await inFlight.exists(), isTrue);
    });

    test('a missing root sweeps zero rather than throwing', () async {
      final removed = await cache.sweepStale(
        rootPath: '${root.path}${Platform.pathSeparator}no-such-root',
      );
      expect(removed, 0);
    });

    test('an empty root sweeps zero', () async {
      expect(await cache.sweepStale(rootPath: root.path), 0);
    });

    test('sweeps stale loose files as well as directories', () async {
      final loose = File('${root.path}${Platform.pathSeparator}orphan.png');
      await loose.writeAsBytes([7, 8, 9]);
      await loose.setLastModified(DateTime.now().subtract(const Duration(days: 2)));

      expect(await cache.sweepStale(rootPath: root.path), 1);
      expect(await loose.exists(), isFalse);
    });

    test('the default max age is the documented six hours', () {
      expect(LocalCutoutCache.defaultMaxAge, const Duration(hours: 6));
    });
  });
}
