import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/features/discover/application/product_details.dart';
import 'package:app/features/discover/application/saved_products.dart';

/// Phase 4 domain: the save-state override layer that keeps the feed, Product
/// Details and the Saved screen agreeing, and the failure taxonomy that decides
/// whether a failed outbound click offers a retry.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({this.fails = false});

  final bool fails;
  final savedCalls = <String>[];
  final unsavedCalls = <String>[];

  @override
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async {
    if (fails) throw Exception('offline');
    savedCalls.add(productId);
  }

  @override
  Future<void> unsave(String productId) async {
    if (fails) throw Exception('offline');
    unsavedCalls.add(productId);
  }

  @override
  Future<List<SavedProduct>> saved() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Product _product({String id = 'p1', bool saved = false}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  saved: saved,
);

void main() {
  ProviderContainer boot(_FakeDiscover repo) {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the save override layer', () {
    test('reports the server value until this session changes it', () {
      final container = boot(_FakeDiscover());
      final overrides = container.read(savedOverridesProvider.notifier);

      expect(overrides.isSaved(_product(saved: false)), isFalse);
      expect(overrides.isSaved(_product(id: 'p2', saved: true)), isTrue);
    });

    test('a save is optimistic and then persisted', () async {
      final repo = _FakeDiscover();
      final container = boot(repo);
      final overrides = container.read(savedOverridesProvider.notifier);

      final result = await overrides.toggle(_product());

      expect(result, isTrue);
      expect(repo.savedCalls, ['p1']);
      // And every other surface now agrees, without any of them reloading.
      expect(container.read(savedOverridesProvider)['p1'], isTrue);
    });

    test('unsaving something the server called saved calls unsave', () async {
      final repo = _FakeDiscover();
      final container = boot(repo);

      final result = await container
          .read(savedOverridesProvider.notifier)
          .toggle(_product(saved: true));

      expect(result, isFalse);
      expect(repo.unsavedCalls, ['p1']);
    });

    test('a failed write puts the heart back rather than lying', () async {
      final repo = _FakeDiscover(fails: true);
      final container = boot(repo);
      final overrides = container.read(savedOverridesProvider.notifier);

      await expectLater(
        overrides.toggle(_product()),
        throwsA(isA<Exception>()),
      );

      expect(overrides.isSaved(_product()), isFalse);
      expect(container.read(savedOverridesProvider)['p1'], isFalse);
    });

    test('a fresh page reconciles away the overrides it re-states', () async {
      // The server's copy already reflects this session's saves, so keeping a
      // local value on top of it would only preserve a disagreement.
      final container = boot(_FakeDiscover());
      final overrides = container.read(savedOverridesProvider.notifier);
      await overrides.toggle(_product(id: 'p1'));
      await overrides.toggle(_product(id: 'p9'));

      overrides.reconcile(['p1']);

      final state = container.read(savedOverridesProvider);
      expect(state.containsKey('p1'), isFalse);
      // p9 was not in the page, so nothing has re-stated it.
      expect(state['p9'], isTrue);
    });

    test('reconcile on an empty override map is a no-op', () {
      final container = boot(_FakeDiscover());
      container.read(savedOverridesProvider.notifier).reconcile(['p1', 'p2']);
      expect(container.read(savedOverridesProvider), isEmpty);
    });
  });

  group('shop failure taxonomy', () {
    test('a product that is gone is not retryable', () {
      // Telling someone to try again when the product no longer exists is
      // advice that can never work (§24).
      expect(
        shopFailureFor(
          const ApiException(code: ApiErrorCode.notFound, message: 'gone'),
        ),
        ShopFailure.unavailable,
      );
    });

    test('an unreachable store is retryable', () {
      for (final code in [
        ApiErrorCode.providerError,
        ApiErrorCode.network,
        ApiErrorCode.rateLimited,
      ]) {
        expect(
          shopFailureFor(ApiException(code: code, message: 'x')),
          ShopFailure.unreachable,
          reason: '$code should offer a retry',
        );
      }
    });

    test('an error with no envelope at all is still retryable', () {
      // A dropped connection is not proof the product vanished.
      expect(
        shopFailureFor(DioException(requestOptions: RequestOptions(path: '/'))),
        ShopFailure.unreachable,
      );
      expect(shopFailureFor(Exception('boom')), ShopFailure.unreachable);
    });
  });
}
