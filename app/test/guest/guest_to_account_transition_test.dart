import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/network/provider_retry.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/repositories/outfit_repository.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';

/// GUEST → ACCOUNT: the closet must load by itself.
///
/// Reported from the TestFlight build: after signing in from Guest, the Closet
/// (and other account surfaces) sat on an error until "Try again" was tapped,
/// and everything else trickled in slowly.
///
/// The mechanism is Riverpod 3's `defaultRetry`: it retries ANY failure that is
/// not an `Error` — ten times, backing off 200ms, 400ms, … capped at 6.4s, so
/// roughly 38 seconds of retrying. A guest browsing Discover has
/// `wardrobeItemsProvider` on screen, the guest gate refuses it, and the
/// provider spends the whole visit failing and backing off. Sign-in then lands
/// on a provider graph mid-backoff, and the UI waits out timers that were
/// scheduled for a condition that has already changed.
///
/// Retrying a guest denial can never succeed: it is not a transient fault, it
/// is a statement about who is asking. So it must not be retried at all — and
/// these tests run with the app's REAL retry policy, because a test that
/// disables retry (as every other test in this repo does) cannot see any of it.
class _FakeWardrobeRepo implements WardrobeRepository {
  _FakeWardrobeRepo(this._hasSession);

  final bool Function() _hasSession;
  int calls = 0;

  @override
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    calls++;
    if (!_hasSession()) {
      // Exactly what the guest network guard produces: a typed, user-safe
      // refusal — and a plain Exception, which is what makes it retryable.
      throw const ApiException(
        code: ApiErrorCode.unauthenticated,
        message: 'This action requires an account.',
        statusCode: 401,
      );
    }
    return const [WardrobeItem(id: 'w1', imageUrl: 'https://x.test/a.jpg')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mutable identity, so one container can go guest → signed in exactly the
  /// way the real app does.
  late String? userId;

  ProviderContainer boot() {
    userId = null;
    final container = ProviderContainer(
      // The REAL policy the app installs in `bootstrap()` — not the
      // `retry: (_, _) => null` every other test uses, which would make this
      // whole file pass vacuously.
      retry: appProviderRetry,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(platform: TargetPlatform.iOS),
        ),
        authUserIdProvider.overrideWith((ref) => userId),
        isAuthenticatedProvider.overrideWith((ref) => userId != null),
        appSessionProvider.overrideWith(
          (ref) => userId != null
              ? AppSessionState.authenticated
              : AppSessionState.guest,
        ),
        // Mirrors the real chain: the repository is rebuilt by an identity
        // change, because `dioProvider` watches `authUserIdProvider` and the
        // repository watches `dioProvider`.
        wardrobeRepositoryProvider.overrideWith((ref) {
          ref.watch(authUserIdProvider);
          return _FakeWardrobeRepo(() => userId != null);
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a guest denial is NOT retried', () async {
    final container = boot();
    // Keep it alive the way the Discover screen does — it watches the closet
    // for its "complete your look" module.
    final sub = container.listen(wardrobeItemsProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(wardrobeItemsProvider.future)
        .then((_) => null, onError: (_) => null);
    expect(container.read(wardrobeItemsProvider), isA<AsyncError<dynamic>>());

    final repo =
        container.read(wardrobeRepositoryProvider) as _FakeWardrobeRepo;
    final afterFirstFailure = repo.calls;

    // Long enough for several default-retry windows (200 + 400 + 800 + 1600).
    await Future<void>.delayed(const Duration(seconds: 4));

    expect(
      repo.calls,
      afterFirstFailure,
      reason:
          'a guest denial is permanent until the session changes — '
          'retrying it burns work and leaves the graph mid-backoff at sign-in',
    );
  });

  test(
    'signing in loads the closet immediately, with no manual retry',
    () async {
      final container = boot();
      final sub = container.listen(wardrobeItemsProvider, (_, _) {});
      addTearDown(sub.close);

      // Browse as a guest: the closet is refused.
      await container
          .read(wardrobeItemsProvider.future)
          .then((_) => null, onError: (_) => null);
      expect(container.read(wardrobeItemsProvider), isA<AsyncError<dynamic>>());

      // Sign in.
      userId = 'u1';
      container.invalidate(authUserIdProvider);
      container.invalidate(isAuthenticatedProvider);
      container.invalidate(appSessionProvider);

      // ONE microtask-and-a-frame's worth of settling — not a backoff window.
      final loaded = await container
          .read(wardrobeItemsProvider.future)
          .timeout(const Duration(milliseconds: 500));

      expect(loaded, hasLength(1));
      expect(container.read(wardrobeItemsProvider), isA<AsyncData<dynamic>>());
    },
  );

  test('outfits also load themselves after signing in', () async {
    var userId2 = <String?>[null];
    final container = ProviderContainer(
      retry: appProviderRetry,
      overrides: [
        authUserIdProvider.overrideWith((ref) => userId2.first),
        outfitRepositoryProvider.overrideWith((ref) {
          ref.watch(authUserIdProvider);
          return _FakeOutfitRepo(() => userId2.first != null);
        }),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(outfitsProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(outfitsProvider.future)
        .then((_) => null, onError: (_) => null);
    expect(container.read(outfitsProvider), isA<AsyncError<dynamic>>());

    userId2[0] = 'u1';
    container.invalidate(authUserIdProvider);

    final loaded = await container
        .read(outfitsProvider.future)
        .timeout(const Duration(milliseconds: 500));
    expect(loaded, isEmpty);
    expect(container.read(outfitsProvider), isA<AsyncData<dynamic>>());
  });

  test('a genuine transient failure IS still retried', () async {
    // The fix must not disable retry wholesale. A flaky network is exactly what
    // the default policy is for, and a guest with one dropped request should
    // still recover without tapping anything.
    var attempts = 0;
    final container = ProviderContainer(
      retry: appProviderRetry,
      overrides: [
        authUserIdProvider.overrideWith((ref) => 'u1'),
        isAuthenticatedProvider.overrideWith((ref) => true),
        appSessionProvider.overrideWith((ref) => AppSessionState.authenticated),
        wardrobeRepositoryProvider.overrideWith(
          (ref) => _FlakyRepo(() => ++attempts),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(wardrobeItemsProvider, (_, _) {});
    addTearDown(sub.close);

    final items = await container
        .read(wardrobeItemsProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(attempts, greaterThan(1), reason: 'the first attempt failed');
    expect(items, hasLength(1));
  });
}

/// Fails once with a network error, then succeeds — a dropped request.
class _FlakyRepo implements WardrobeRepository {
  _FlakyRepo(this._next);

  final int Function() _next;

  @override
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    if (_next() == 1) {
      throw const ApiException(
        code: ApiErrorCode.network,
        message: 'Network error. Please try again.',
      );
    }
    return const [WardrobeItem(id: 'w1', imageUrl: 'https://x.test/a.jpg')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Refuses without a session, then returns an (empty) outfit list.
class _FakeOutfitRepo implements OutfitRepository {
  _FakeOutfitRepo(this._hasSession);

  final bool Function() _hasSession;

  @override
  Future<List<Outfit>> getOutfits() async {
    if (!_hasSession()) {
      throw const ApiException(
        code: ApiErrorCode.unauthenticated,
        message: 'This action requires an account.',
        statusCode: 401,
      );
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
