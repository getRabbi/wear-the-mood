import 'dart:async';
import 'dart:convert';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory FlutterSecureStorage with an optional read gate, so we can hold a
/// load open and switch accounts mid-flight (the async-race regression).
class _FakeStorage extends FlutterSecureStorage {
  _FakeStorage({Map<String, String>? seed, this.readGate}) {
    if (seed != null) data.addAll(seed);
  }

  final Map<String, String> data = {};
  final Future<void> Function()? readGate;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readGate != null) await readGate!();
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

String _look(String id) => jsonEncode([
  {'id': id, 'image_url': 'https://cdn/$id.png', 'created_at': '2026-01-01T00:00:00Z'},
]);

class _TestUid extends Notifier<String?> {
  @override
  String? build() => 'userA';
  void set(String? v) => state = v;
}

final _testUid = NotifierProvider<_TestUid, String?>(_TestUid.new);

ProviderContainer _container(_FakeStorage fake) => ProviderContainer(
  overrides: [
    collectionsStorageProvider.overrideWithValue(fake),
    authUserIdProvider.overrideWith((ref) => ref.watch(_testUid)),
  ],
);

void main() {
  test('saved looks are namespaced per user and never leak across a switch', () async {
    final fake = _FakeStorage(seed: {'fashionos.userA.saved_look_records': _look('lookA')});
    final c = _container(fake);
    addTearDown(c.dispose);
    c.listen(savedLookRecordsProvider, (_, _) {}); // instantiate + keep alive

    // A sees their own saved look.
    await pumpEventQueue();
    expect(c.read(savedLookRecordsProvider).map((l) => l.id), ['lookA']);

    // Switch to a brand-new account B → B sees NOTHING (no leak).
    c.read(_testUid.notifier).set('userB');
    await pumpEventQueue();
    expect(c.read(savedLookRecordsProvider), isEmpty);

    // Switch back to A → only A's namespaced look is restored.
    c.read(_testUid.notifier).set('userA');
    await pumpEventQueue();
    expect(c.read(savedLookRecordsProvider).map((l) => l.id), ['lookA']);
  });

  test('closet favorites are per-user and a new account inherits none', () async {
    final fake = _FakeStorage(seed: {'fashionos.userA.favorites': jsonEncode(['itemA'])});
    final c = _container(fake);
    addTearDown(c.dispose);
    c.listen(closetFavoritesProvider, (_, _) {});

    await pumpEventQueue();
    expect(c.read(closetFavoritesProvider), {'itemA'});

    c.read(_testUid.notifier).set('userB');
    await pumpEventQueue();
    expect(c.read(closetFavoritesProvider), isEmpty);
  });

  test('a guest namespace never inherits a signed-in user records', () async {
    final fake = _FakeStorage(seed: {'fashionos.userA.saved_look_records': _look('lookA')});
    final c = _container(fake);
    addTearDown(c.dispose);
    c.listen(savedLookRecordsProvider, (_, _) {});

    c.read(_testUid.notifier).set(null); // signed out → guest scope
    await pumpEventQueue();
    expect(c.read(savedLookRecordsProvider), isEmpty);
  });

  test('a delayed load from account A cannot populate account B state (async race)', () async {
    final gate = Completer<void>();
    final fake = _FakeStorage(
      seed: {'fashionos.userA.saved_look_records': _look('lookA')},
      readGate: () => gate.future,
    );
    final c = _container(fake);
    addTearDown(c.dispose);
    c.listen(savedLookRecordsProvider, (_, _) {}); // starts A's gated load

    // Switch to B BEFORE A's read resolves, then release the read.
    c.read(_testUid.notifier).set('userB');
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    // A's late result was discarded by the scope guard — B stays empty.
    expect(c.read(savedLookRecordsProvider), isEmpty);
  });

  test('purge deletes the legacy global keys exactly once', () async {
    final fake = _FakeStorage(seed: {
      'fashionos.saved_look_records': _look('legacy'),
      'fashionos.favorites': jsonEncode(['x']),
      'fashionos.saved_looks': jsonEncode(['y']),
      'fashionos.outfit_favorites': jsonEncode(['z']),
    });
    await purgeLegacyGlobalCollections(fake);
    expect(fake.data.containsKey('fashionos.saved_look_records'), isFalse);
    expect(fake.data.containsKey('fashionos.favorites'), isFalse);
    expect(fake.data.containsKey('fashionos.saved_looks'), isFalse);
    expect(fake.data.containsKey('fashionos.outfit_favorites'), isFalse);
    expect(fake.data['fashionos.legacy_collections_purged'], '1');

    // Idempotent: a second run leaves the flag and does nothing.
    fake.data['fashionos.favorites'] = jsonEncode(['reappeared']);
    await purgeLegacyGlobalCollections(fake);
    expect(fake.data['fashionos.favorites'], jsonEncode(['reappeared']));
  });
}
