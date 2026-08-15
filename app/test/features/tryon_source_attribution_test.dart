import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/tryon/tryon_controller.dart';

/// Every catalog try-on carries its origin to the server.
///
/// This is the last mile of the shopping try-on gate. The server re-checks
/// `product_tryon_ready()` at execution time using `source_product_id` — that is
/// what makes switching a merchant or a product off a real kill switch rather
/// than a change that stale clients ignore. A request that omits the origin is
/// not refused (a closet render legitimately has none), so a catalog render that
/// silently dropped it would sail straight past the guard and spend credits
/// rendering a product the catalog has stopped clearing.
///
/// `wtm_tryon_everywhere_test.dart` already proves every surface SETS the
/// origin. This file proves the two halves that test cannot see: that the origin
/// survives the trip to the wire, and that there is exactly one wire for it to
/// travel down.
///
/// The structural assertions read `lib/` on purpose. "All surfaces agree" is a
/// claim about code that does not exist yet — the seventh surface, the second
/// submit path — and only a test that counts call sites can fail when one is
/// added.

class _RecordingTryOn implements TryOnRepository {
  final calls = <Map<String, Object?>>[];

  @override
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    List<String>? garmentImageUrls,
    List<TryOnGarmentRef>? garments,
    String? wardrobeItemId,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    String? idempotencyKey,
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,
  }) async {
    calls.add({
      'source_product_id': sourceProductId,
      'source_placement': sourcePlacement,
      'source_campaign_id': sourceCampaignId,
    });
    // Terminal on arrival, so the controller never enters its polling loop and
    // the test does not depend on timers.
    return const TryOnJob(
      jobId: 'j1',
      status: TryOnStatus.done,
      resultImageUrl: 'https://cdn.test/result.jpg',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// Reads a file under `lib/`. Flutter tests run with the package root as the
/// working directory.
String _lib(String relative) => File('lib/$relative').readAsStringSync();

List<String> _dartFilesUnderLib() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('.dart'))
    .toList();

void main() {
  group('the origin reaches the wire', () {
    test('a shopping render sends source_product_id', () async {
      final repo = _RecordingTryOn();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [tryOnRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(tryOnControllerProvider.notifier)
          .start(
            personImageUrl: 'https://cdn.test/body.jpg',
            garments: const [
              TryOnGarmentRef(
                imageUrl: 'https://cdn.test/dress.jpg',
                productId: 'p1',
                category: 'Dresses',
              ),
            ],
            sourceProductId: 'p1',
            sourcePlacement: 'feed_grid',
          );

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single['source_product_id'], 'p1');
      expect(repo.calls.single['source_placement'], 'feed_grid');
    });

    test('a closet render sends none, and must not', () async {
      // The server only demands an origin from requests that NAME a product. A
      // wardrobe garment has no product, and inventing one would attribute
      // somebody's own jumper to a merchant.
      final repo = _RecordingTryOn();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [tryOnRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(tryOnControllerProvider.notifier)
          .start(
            personImageUrl: 'https://cdn.test/body.jpg',
            garments: const [
              TryOnGarmentRef(
                imageUrl: 'https://cdn.test/my-coat.jpg',
                category: 'Outerwear',
              ),
            ],
          );

      expect(repo.calls.single['source_product_id'], isNull);
    });

    test('a retry re-sends the same origin', () async {
      // A retried shopping render is still a shopping render — and the server
      // re-checks readiness on every submit, so an origin dropped on retry
      // would be a request that skipped the gate.
      final repo = _RecordingTryOn();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [tryOnRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final controller = container.read(tryOnControllerProvider.notifier);
      await controller.start(
        personImageUrl: 'https://cdn.test/body.jpg',
        garments: const [
              TryOnGarmentRef(
                imageUrl: 'https://cdn.test/dress.jpg',
                productId: 'p1',
                category: 'Dresses',
              ),
            ],
        sourceProductId: 'p1',
        sourcePlacement: 'feed_grid',
      );
      await controller.retry();

      expect(repo.calls, hasLength(2));
      expect(repo.calls.last['source_product_id'], 'p1');
      expect(repo.calls.last['source_placement'], 'feed_grid');
    });
  });

  group('there is exactly one of everything', () {
    test('only the controller creates a job', () {
      // Two submit paths would mean two places the origin could be forgotten,
      // and only one of them would be covered by the tests above.
      final callers = [
        for (final path in _dartFilesUnderLib())
          if (File(path).readAsStringSync().contains('createTryOn(')) path,
      ]..sort();

      expect(callers, [
        'lib/data/repositories/tryon_repository.dart', // the definition
        'lib/features/tryon/tryon_controller.dart', // the only caller
      ]);
    });

    test('only startShoppingTryOn records a shopping origin', () {
      final writers = [
        for (final path in _dartFilesUnderLib())
          if (File(
            path,
          ).readAsStringSync().contains('shoppingTryOnSourceProvider.notifier'))
            path,
      ];

      expect(writers, [
        'lib/features/discover/application/shopping_tryon.dart',
      ]);
    });

    test('the mirror submit reads the ACTIVE origin, not a remembered one', () {
      // `activeShoppingTryOnSourceProvider` is null unless the product is still
      // in the outfit stack. Reading the raw provider here would attach a
      // product to a closet render the user swapped to afterwards.
      final step3 = _lib('ui/mirror/wtm_mirror_step3.dart');
      expect(step3, contains('activeShoppingTryOnSourceProvider'));
      expect(step3, contains('sourceProductId: source?.productId'));
    });
  });

  group('the legacy shell cannot submit an unattributed catalog render', () {
    // `features/tryon/tryon_screen.dart` also submits, and deliberately sends no
    // origin. That is correct only for as long as a catalog product cannot reach
    // it — so that, rather than the omission, is what is pinned here.

    test('the shopping entry point routes to the WTM mirror', () {
      final entry = _lib('features/discover/application/shopping_tryon.dart');
      expect(entry, contains('AppRoute.wtmMirrorGarments'));
      expect(entry, isNot(contains('AppRoute.tryOn')));
    });

    test('and clears the preselect queue the legacy screen consumes', () {
      // The legacy screen seeds its stack from `tryOnPreselectProvider`. The
      // shopping entry point sets the WTM layers directly and CLEARS that
      // queue, so there is no path by which a product arrives there.
      final entry = _lib('features/discover/application/shopping_tryon.dart');
      expect(entry, contains('tryOnPreselectProvider.notifier).clear()'));
    });

    test('the legacy submit takes no origin parameter at all', () {
      // Not "passes null" — has no way to express one. A field that existed but
      // was left unset is a field somebody will one day set.
      final legacy = _lib('features/tryon/tryon_screen.dart');
      expect(legacy, isNot(contains('sourceProductId')));
    });
  });
}
