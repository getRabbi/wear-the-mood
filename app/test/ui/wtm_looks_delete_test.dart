import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/profile/wtm_looks_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// Saved Looks are DEVICE-LOCAL: an encrypted, per-user namespaced record, no
/// table and no RLS. So these tests drive the real store through a fake secure
/// storage and assert on what it persisted — there is no endpoint to mock and
/// no server authorization to prove, because ownership here is structural.
class _MemoryStorage implements FlutterSecureStorage {
  _MemoryStorage([Map<String, String>? seed]) : store = {...?seed};

  final Map<String, String> store;

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// The exact storage key the store uses for user `u1`.
const _key = 'fashionos.u1.saved_look_records';

String _seed(List<String> ids) => jsonEncode([
  for (final id in ids)
    {
      'id': id,
      'image_url': 'https://cdn.wearthemood.com/looks/$id.jpg',
      'created_at': '2026-08-01T10:00:00.000Z',
    },
]);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<(ProviderContainer, _MemoryStorage)> boot(
    WidgetTester tester, {
    required List<String> looks,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final storage = _MemoryStorage({_key: _seed(looks)});
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        collectionsStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).push(AppRoute.wtmLooks);
    await settle(tester);
    return (container, storage);
  }

  Finder tileDelete(String id) => find.byKey(Key('wtm-look-delete-$id'));

  group('deleting a saved look', () {
    testWidgets('every tile carries a delete action', (tester) async {
      await boot(tester, looks: ['a', 'b']);

      expect(find.byType(WtmLooksScreen), findsOneWidget);
      expect(tileDelete('a'), findsOneWidget);
      expect(tileDelete('b'), findsOneWidget);
    });

    testWidgets('it confirms before removing anything', (tester) async {
      final (container, _) = await boot(tester, looks: ['a']);

      await tester.tap(tileDelete('a'));
      await settle(tester);

      expect(find.text('Delete this look?'), findsOneWidget);
      expect(
        find.textContaining('Posts you already shared stay up.'),
        findsOneWidget,
        reason: 'the render can already be in a community post',
      );
      expect(
        container.read(savedLookRecordsProvider).length,
        1,
        reason: 'nothing may go before the confirmation is answered',
      );
    });

    testWidgets('cancel leaves the look exactly where it was', (tester) async {
      final (container, storage) = await boot(tester, looks: ['a']);

      await tester.tap(tileDelete('a'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(container.read(savedLookRecordsProvider).length, 1);
      expect(storage.store[_key], contains('"id":"a"'));
      // Usable again — cancelling must not strand the tile.
      expect(tester.widget<WtmIconButton>(tileDelete('a')).onTap, isNotNull);
    });

    testWidgets('confirming removes it from the grid, state and storage', (
      tester,
    ) async {
      final (container, storage) = await boot(tester, looks: ['a', 'b']);

      await tester.tap(tileDelete('a'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      // State + the grid, on the same frame — no restart, no refetch.
      final remaining = container.read(savedLookRecordsProvider);
      expect(remaining.map((l) => l.id), ['b']);
      expect(tileDelete('a'), findsNothing);
      expect(tileDelete('b'), findsOneWidget);
      expect(find.text('Look deleted'), findsOneWidget);
      // And it survived to disk.
      expect(storage.store[_key], isNot(contains('"id":"a"')));
      expect(storage.store[_key], contains('"id":"b"'));
    });

    testWidgets('deleting the last look reveals the empty state', (
      tester,
    ) async {
      final (container, _) = await boot(tester, looks: ['a']);

      await tester.tap(tileDelete('a'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(container.read(savedLookRecordsProvider), isEmpty);
      expect(find.byType(WtmEmptyState), findsOneWidget);
    });

    testWidgets('a double tap opens only one confirmation', (tester) async {
      final (container, _) = await boot(tester, looks: ['a']);

      await tester.tap(tileDelete('a'), warnIfMissed: false);
      await tester.tap(tileDelete('a'), warnIfMissed: false);
      await settle(tester);

      expect(
        find.text('Delete this look?'),
        findsOneWidget,
        reason: 'the latch is taken before the dialog, not after it',
      );
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(container.read(savedLookRecordsProvider), isEmpty);
    });

    testWidgets('deleting one look never disables the others', (tester) async {
      await boot(tester, looks: ['a', 'b']);

      await tester.tap(tileDelete('a'));
      await settle(tester);

      // The confirmation for 'a' is open; 'b' is untouched behind it.
      expect(tester.widget<WtmIconButton>(tileDelete('b')).onTap, isNotNull);
    });

    testWidgets('the full-screen viewer offers the same delete', (
      tester,
    ) async {
      final (container, _) = await boot(tester, looks: ['a']);

      // Open the look, then delete from inside the viewer.
      await tester.tap(find.byKey(const Key('wtm-look-open-a')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('wtm-look-viewer-delete')));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(container.read(savedLookRecordsProvider), isEmpty);
    });
  });

  group('the store itself', () {
    test('remove is idempotent — an already-gone id is a safe no-op', () {
      final container = ProviderContainer(
        overrides: [
          authUserIdProvider.overrideWithValue('u1'),
          collectionsStorageProvider.overrideWithValue(_MemoryStorage()),
        ],
      );
      addTearDown(container.dispose);
      final store = container.read(savedLookRecordsProvider.notifier);

      store.add(
        SavedLook(
          id: 'a',
          imageUrl: 'https://x/a.jpg',
          createdAt: DateTime.now(),
        ),
      );
      store.remove('a');
      store.remove('a'); // again — must not throw or corrupt state
      store.remove('never-existed');

      expect(container.read(savedLookRecordsProvider), isEmpty);
    });

    test('removing a record leaves the durable image URL untouched', () {
      // The point of the whole design: the render lives in R2 and a shared
      // community post can reference that exact URL. Deletion is local.
      final container = ProviderContainer(
        overrides: [
          authUserIdProvider.overrideWithValue('u1'),
          collectionsStorageProvider.overrideWithValue(_MemoryStorage()),
        ],
      );
      addTearDown(container.dispose);
      final store = container.read(savedLookRecordsProvider.notifier);
      const url = 'https://cdn.wearthemood.com/looks/a.jpg';

      store.add(SavedLook(id: 'a', imageUrl: url, createdAt: DateTime.now()));
      store.remove('a');

      // Re-saving the same id restores it from the same URL — nothing about the
      // stored object was invalidated by the delete.
      store.add(SavedLook(id: 'a', imageUrl: url, createdAt: DateTime.now()));
      expect(container.read(savedLookRecordsProvider).single.imageUrl, url);
    });
  });
}
