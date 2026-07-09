import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/tryon/two_d/fit_memory.dart';

/// In-memory [FitMemoryStore] so the persistence logic is testable without the
/// platform secure-storage channel.
class _MemStore implements FitMemoryStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

FitPlacement _p({
  double nx = 0.1,
  double ny = 0.2,
  double scale = 1.5,
  double rotation = 0.3,
  double opacity = 0.8,
  bool flipX = true,
  int zIndex = 2,
  double aspect = 0.7,
  DateTime? at,
}) =>
    FitPlacement(
      nx: nx,
      ny: ny,
      scale: scale,
      rotation: rotation,
      opacity: opacity,
      flipX: flipX,
      zIndex: zIndex,
      aspect: aspect,
      updatedAt: at ?? DateTime(2026, 7, 2),
    );

void main() {
  group('keyFor', () {
    test('composes user | body | item', () {
      expect(
        FitMemoryService.keyFor(userId: 'u1', bodyId: 'b1', itemId: 'i1'),
        'u1|b1|i1',
      );
    });

    test('falls back to anon for a null user', () {
      expect(
        FitMemoryService.keyFor(userId: null, bodyId: 'b', itemId: 'i'),
        'anon|b|i',
      );
    });
  });

  group('normalizeBodyId', () {
    test('strips the (expiring) query string', () {
      expect(
        FitMemoryService.normalizeBodyId('https://cdn/x/body.jpg?token=abc&e=1'),
        'https://cdn/x/body.jpg',
      );
    });

    test('empty url → mannequin', () {
      expect(FitMemoryService.normalizeBodyId('   '), 'mannequin');
    });
  });

  group('save / load round-trip (Phase 4 — fit memory loads previous fit)', () {
    test('a saved fit loads back with the same values', () async {
      final svc = FitMemoryService(_MemStore());
      final placement = _p();
      await svc.saveAll({'u1|b1|i1': placement});

      final loaded = await svc.loadAll();
      final got = loaded['u1|b1|i1']!;
      expect(got.nx, placement.nx);
      expect(got.ny, placement.ny);
      expect(got.scale, placement.scale);
      expect(got.rotation, placement.rotation);
      expect(got.opacity, placement.opacity);
      expect(got.flipX, placement.flipX);
      expect(got.zIndex, placement.zIndex);
    });

    test('saveAll merges without dropping earlier entries', () async {
      final svc = FitMemoryService(_MemStore());
      await svc.saveAll({'k1': _p(nx: 0.1)});
      await svc.saveAll({'k2': _p(nx: 0.9)});

      final loaded = await svc.loadAll();
      expect(loaded.keys, containsAll(['k1', 'k2']));
      expect(loaded['k1']!.nx, 0.1);
      expect(loaded['k2']!.nx, 0.9);
    });
  });

  group('reset clears memory (Phase 4/7)', () {
    test('remove deletes one key, leaves others', () async {
      final svc = FitMemoryService(_MemStore());
      await svc.saveAll({'k1': _p(), 'k2': _p()});

      await svc.remove('k1');

      final loaded = await svc.loadAll();
      expect(loaded.containsKey('k1'), isFalse);
      expect(loaded.containsKey('k2'), isTrue);
    });

    test('removeAll clears every listed key (reset all)', () async {
      final svc = FitMemoryService(_MemStore());
      await svc.saveAll({'k1': _p(), 'k2': _p(), 'k3': _p()});

      await svc.removeAll(['k1', 'k2']);

      final loaded = await svc.loadAll();
      expect(loaded.keys, ['k3']);
    });
  });

  group('robustness', () {
    test('a corrupt blob loads as empty (never crashes the editor)', () async {
      final store = _MemStore()..value = 'not-json{{{';
      final svc = FitMemoryService(store);
      expect(await svc.loadAll(), isEmpty);
    });

    test('storage is pruned so it cannot grow without bound', () async {
      final svc = FitMemoryService(_MemStore());
      // 450 entries; oldest first so the pruned survivors are the newest.
      final entries = <String, FitPlacement>{};
      for (var i = 0; i < 450; i++) {
        entries['k$i'] = _p(at: DateTime(2026, 1, 1).add(Duration(minutes: i)));
      }
      await svc.saveAll(entries);

      final loaded = await svc.loadAll();
      expect(loaded.length, 400); // capped
      expect(loaded.containsKey('k0'), isFalse); // oldest dropped
      expect(loaded.containsKey('k449'), isTrue); // newest kept
    });
  });
}
