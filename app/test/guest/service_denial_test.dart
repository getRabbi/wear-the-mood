import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/auth/auth_required.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/media/media_upload_service.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/features/discover/application/saved_products.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/repositories/tryon_repository.dart';

import '../helpers/fake_dio.dart';

/// SERVICE-LAYER DENIAL.
///
/// The network guard proves nothing left the app. These prove something
/// stronger and earlier: for a guest, the protected DEPENDENCY is never even
/// reached — no repository call, no idempotency key minted, no analytics event
/// claiming a run started, no optimistic UI write.
///
/// Every counter below asserts **zero**.
class _CountingTryOnRepo implements TryOnRepository {
  int createCalls = 0;
  int pollCalls = 0;

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
    createCalls++;
    throw StateError('a guest must never reach createTryOn');
  }

  @override
  Future<TryOnJob> getJob(String jobId) async {
    pollCalls++;
    throw StateError('a guest must never reach getJob');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingDiscoverRepo implements DiscoverRepository {
  int saveCalls = 0;
  int unsaveCalls = 0;

  @override
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async {
    saveCalls++;
    throw StateError('a guest must never reach save');
  }

  @override
  Future<void> unsave(String productId) async {
    unsaveCalls++;
    throw StateError('a guest must never reach unsave');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final product = Product(
    id: 'p1',
    merchant: const MerchantSummary(id: 'm1', name: 'Merchant'),
    title: 'Linen shirt',
    price: const Money(amountMinor: 4500, currency: 'USD'),
  );

  /// A container in the iOS GUEST state.
  ///
  /// `appSessionProvider` is overridden directly rather than by faking Supabase:
  /// deterministic, no global mutation, and it is the single provider every gate
  /// reads, so overriding it is overriding the real thing.
  // `List<dynamic>` deliberately: `Override` is sealed and not exported for
  // naming, so the repo's idiom is to take the list untyped and `.cast()` it
  // (see test/ui/wtm_retention_layout_test.dart).
  ProviderContainer guest({List<dynamic> overrides = const []}) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(platform: TargetPlatform.iOS),
        ),
        appSessionProvider.overrideWithValue(AppSessionState.guest),
        ...overrides.cast(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  ProviderContainer member({List<dynamic> overrides = const []}) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appSessionProvider.overrideWithValue(AppSessionState.authenticated),
        ...overrides.cast(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('try-on: no job, no key, no repository call', () {
    test(
      'a guest Generate throws AuthRequiredException and calls nothing',
      () async {
        final repo = _CountingTryOnRepo();
        final container = guest(
          overrides: [tryOnRepositoryProvider.overrideWithValue(repo)],
        );
        final controller = container.read(tryOnControllerProvider.notifier);

        await expectLater(
          controller.start(
            personImageUrl: 'https://example.test/me.jpg',
            garments: const [
              TryOnGarmentRef(imageUrl: 'https://example.test/g.jpg'),
            ],
          ),
          throwsA(isA<AuthRequiredException>()),
        );

        expect(repo.createCalls, 0, reason: 'no AI job may be created');
        expect(repo.pollCalls, 0);
        // And the controller did not pretend a run was under way.
        expect(container.read(tryOnControllerProvider), isA<TryOnIdle>());
      },
    );

    test(
      'the exception names the try-on action, so the sheet is specific',
      () async {
        final container = guest(
          overrides: [
            tryOnRepositoryProvider.overrideWithValue(_CountingTryOnRepo()),
          ],
        );
        try {
          await container
              .read(tryOnControllerProvider.notifier)
              .start(
                personImageUrl: 'https://example.test/me.jpg',
                garments: const [
                  TryOnGarmentRef(imageUrl: 'https://example.test/g.jpg'),
                ],
              );
          fail('expected AuthRequiredException');
        } on AuthRequiredException catch (error) {
          expect(error.action, ProtectedAction.tryOn);
        }
      },
    );

    test('retry after a denial still calls nothing', () async {
      final repo = _CountingTryOnRepo();
      final container = guest(
        overrides: [tryOnRepositoryProvider.overrideWithValue(repo)],
      );
      final controller = container.read(tryOnControllerProvider.notifier);

      await expectLater(
        controller.start(
          personImageUrl: 'https://example.test/me.jpg',
          garments: const [
            TryOnGarmentRef(imageUrl: 'https://example.test/g.jpg'),
          ],
        ),
        throwsA(isA<AuthRequiredException>()),
      );
      // A denial must not have recorded the request as retryable — otherwise a
      // Retry would sail past the gate on inputs the guard already refused.
      expect(controller.canRetry, isFalse);
      await controller.retry();
      expect(repo.createCalls, 0);
    });

    test('unknown session state is denied exactly like guest', () async {
      final repo = _CountingTryOnRepo();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appSessionProvider.overrideWithValue(AppSessionState.unknown),
          tryOnRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(tryOnControllerProvider.notifier)
            .start(
              personImageUrl: 'https://example.test/me.jpg',
              garments: const [
                TryOnGarmentRef(imageUrl: 'https://example.test/g.jpg'),
              ],
            ),
        throwsA(isA<AuthRequiredException>()),
      );
      expect(repo.createCalls, 0);
    });
  });

  group('save a product: no write, no optimistic lie', () {
    test('a guest toggle throws and never calls the repository', () async {
      final repo = _CountingDiscoverRepo();
      final container = guest(
        overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
      );

      await expectLater(
        container.read(savedOverridesProvider.notifier).toggle(product),
        throwsA(isA<AuthRequiredException>()),
      );

      expect(repo.saveCalls, 0);
      expect(repo.unsaveCalls, 0);
    });

    test('the heart is not filled in and then emptied again', () async {
      final repo = _CountingDiscoverRepo();
      final container = guest(
        overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
      );
      final notifier = container.read(savedOverridesProvider.notifier);

      await expectLater(
        notifier.toggle(product),
        throwsA(isA<AuthRequiredException>()),
      );

      // No override was written at all — the guard runs BEFORE the optimistic
      // write, so the UI never showed a save that was not going to happen.
      expect(container.read(savedOverridesProvider), isEmpty);
      expect(notifier.isSaved(product), isFalse);
    });

    test('the exception names the save action', () async {
      final container = guest(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(_CountingDiscoverRepo()),
        ],
      );
      try {
        await container.read(savedOverridesProvider.notifier).toggle(product);
        fail('expected AuthRequiredException');
      } on AuthRequiredException catch (error) {
        expect(error.action, ProtectedAction.saveProduct);
      }
    });
  });

  group('uploads: not one byte, on either path', () {
    /// Counts BOTH upload routes — the R2 signing call and the legacy Supabase
    /// fallback — because guarding only one of them is a half-closed gate.
    ({
      MediaUploadService service,
      List<String> apiCalls,
      List<String> puts,
      List<String> legacy,
    })
    harness({required AppSessionState session}) {
      final apiCalls = <String>[];
      final puts = <String>[];
      final legacy = <String>[];

      final adapter = FakeAdapter((options) {
        apiCalls.add(options.path);
        return jsonResponse(const {
          'upload_url': 'https://r2.test/put',
          'object_key': 'k',
          'public_url': 'https://cdn.test/k',
        });
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

      final container = ProviderContainer(
        overrides: [appSessionProvider.overrideWithValue(session)],
      );
      addTearDown(container.dispose);

      final service = MediaUploadService(
        dio,
        put: (url, bytes, type) async => puts.add(url),
        ensureAccount: () => requireAuthenticatedUser(
          container.read(_refProbe),
          ProtectedAction.bodyPhoto,
        ),
      );
      return (service: service, apiCalls: apiCalls, puts: puts, legacy: legacy);
    }

    test(
      'a guest upload signs nothing, puts nothing, falls back to nothing',
      () async {
        final h = harness(session: AppSessionState.guest);

        await expectLater(
          h.service.upload(
            bytes: Uint8List.fromList([1, 2, 3]),
            sector: 'body',
            legacy: () async {
              h.legacy.add('legacy');
              return 'https://legacy.test/x.jpg';
            },
          ),
          throwsA(isA<AuthRequiredException>()),
        );

        expect(h.apiCalls, isEmpty, reason: 'no presigned URL may be minted');
        expect(h.puts, isEmpty, reason: 'no bytes may reach R2');
        expect(h.legacy, isEmpty, reason: 'the legacy path must be closed too');
      },
    );

    test('an authenticated upload still works end to end', () async {
      final h = harness(session: AppSessionState.authenticated);

      final ref = await h.service.upload(
        bytes: Uint8List.fromList([1, 2, 3]),
        sector: 'body',
        legacy: () async => 'https://legacy.test/x.jpg',
      );

      expect(h.apiCalls, ['/v1/media/upload-url']);
      expect(h.puts, ['https://r2.test/put']);
      expect(ref.objectKey, 'k');
    });
  });

  group('the guard itself', () {
    test('canPerform is false for guest, unknown and signedOut', () {
      for (final state in [
        AppSessionState.guest,
        AppSessionState.unknown,
        AppSessionState.signedOut,
      ]) {
        final container = ProviderContainer(
          overrides: [appSessionProvider.overrideWithValue(state)],
        );
        addTearDown(container.dispose);
        expect(canPerform(container.read(_refProbe)), isFalse);
      }
    });

    test('canPerform is true only for an authenticated session', () {
      final container = member();
      expect(canPerform(container.read(_refProbe)), isTrue);
    });

    test('AuthRequiredException carries no user data', () {
      const error = AuthRequiredException(ProtectedAction.tryOn);
      // Safe to log: the action name and nothing else.
      expect(error.toString(), 'AuthRequiredException(tryOn)');
    });
  });
}

/// Hands a raw [Ref] to tests that need to call the `Ref`-shaped guards
/// directly. A provider is the only legitimate source of one.
final _refProbe = Provider<Ref>((ref) => ref);
