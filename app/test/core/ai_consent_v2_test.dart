import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/privacy/ai_consent_controller.dart';
import 'package:app/core/privacy/ai_consent_repository.dart';

import '../helpers/fake_dio.dart';

/// The client half of the v2 forced re-consent.
///
/// The server is the authority and refuses anything stale, so nothing here can
/// create a security hole on its own. What the client CAN get wrong is the user
/// experience of the bump, and there are exactly two ways:
///
///   * asking again after the user already accepted — the "consent every render"
///     failure the requirement calls out by name;
///   * NOT asking, because a cached answer from a different account said yes.
///
/// Both are cache behaviour, so both are tested here.
class _FakeConsentRepo implements AiConsentRepository {
  _FakeConsentRepo(this._byUser, this._user);

  final Map<String?, AiConsentState> _byUser;
  final String? Function() _user;

  int reads = 0;
  int grants = 0;

  @override
  Future<AiConsentState> read() async {
    reads++;
    return _byUser[_user()] ??
        const AiConsentState(granted: false, isCurrent: false);
  }

  @override
  Future<AiConsentState> grant() async {
    grants++;
    const granted = AiConsentState(
      granted: true,
      isCurrent: true,
      version: aiConsentVersion,
    );
    _byUser[_user()] = granted;
    return granted;
  }

  @override
  Future<AiConsentState> revoke() async {
    const revoked = AiConsentState(
      granted: false,
      isCurrent: false,
      version: aiConsentVersion,
    );
    _byUser[_user()] = revoked;
    return revoked;
  }
}

void main() {
  group('the version this build displays', () {
    test('matches the server requirement of 2', () {
      // If these drift, every grant is refused and AI try-on is dead. The
      // server-side twin of this assertion is test_the_required_version_is_two.
      expect(aiConsentVersion, 2);
    });

    test('a grant posts the displayed version, not a hardcoded 1', () async {
      final (dio, adapter) = fakeDio(
        (_) => jsonResponse({
          'granted': true,
          'is_current': true,
          'version': 2,
          'required_version': 2,
        }),
      );
      await AiConsentRepository(dio).grant();
      final body =
          jsonDecode(jsonEncode(adapter.lastRequest!.data))
              as Map<String, dynamic>;
      expect(body['consent_version'], 2);
    });
  });

  group('parsing what the server says', () {
    test('a v1 grant is granted but NOT current', () {
      // The exact state every existing account is in on release day.
      final state = AiConsentState.fromJson(const {
        'granted': true,
        'is_current': false,
        'version': 1,
        'required_version': 2,
      });
      expect(state.granted, isTrue);
      expect(state.isCurrent, isFalse);
      expect(state.version, 1);
      expect(state.requiredVersion, 2);
    });

    test('a v2 grant is current', () {
      final state = AiConsentState.fromJson(const {
        'granted': true,
        'is_current': true,
        'version': 2,
        'required_version': 2,
      });
      expect(state.isCurrent, isTrue);
    });

    test('an unknown state is never treated as permission', () {
      const state = AiConsentState.unknown();
      expect(state.granted, isFalse);
      expect(state.isCurrent, isFalse);
    });

    test('a malformed response is never treated as permission', () {
      final state = AiConsentState.fromJson(const {});
      expect(state.isCurrent, isFalse);
    });
  });

  group('the session cache', () {
    /// A container whose signed-in account can be changed between reads.
    ({ProviderContainer container, _FakeConsentRepo repo}) boot({
      required String? user,
      Map<String?, AiConsentState>? seeded,
    }) {
      var current = user;
      final repo = _FakeConsentRepo(seeded ?? {}, () => current);
      final container = ProviderContainer(
        overrides: [
          authUserIdProvider.overrideWith((ref) => current),
          aiConsentRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return (container: container, repo: repo);
    }

    test('an existing v1 account is reported as needing consent', () async {
      final b = boot(
        user: 'a',
        seeded: {
          'a': const AiConsentState(
            granted: true,
            isCurrent: false,
            version: 1,
          ),
        },
      );
      final state = await b.container
          .read(aiConsentProvider.notifier)
          .current();
      expect(state.isCurrent, isFalse);
    });

    test('after accepting, the next render does not re-read or re-ask', () async {
      final b = boot(user: 'a');
      final notifier = b.container.read(aiConsentProvider.notifier);

      expect((await notifier.current()).isCurrent, isFalse);
      expect((await notifier.grant()).isCurrent, isTrue);

      final readsAfterGrant = b.repo.reads;
      // Second, third, fourth render in the same session.
      for (var i = 0; i < 3; i++) {
        expect((await notifier.current()).isCurrent, isTrue);
      }
      // Served from cache: no extra round trips, and above all no second sheet.
      expect(b.repo.reads, readsAfterGrant);
      expect(b.repo.grants, 1);
    });

    test(
      'a fresh session re-reads the server and still does not ask',
      () async {
        // App restart: a new container, so no in-memory cache — but the ACCOUNT
        // still holds the grant, which is the whole point of storing it server
        // side rather than on the device.
        final store = <String?, AiConsentState>{
          'a': const AiConsentState(granted: true, isCurrent: true, version: 2),
        };
        final b = boot(user: 'a', seeded: store);
        final state = await b.container
            .read(aiConsentProvider.notifier)
            .current();
        expect(state.isCurrent, isTrue);
        expect(b.repo.grants, 0); // never re-prompted
      },
    );
  });

  group('account switching', () {
    /// Signing in as somebody else is an EXTERNAL change, so it is modelled the
    /// way Riverpod models one: the override is replaced. Mutating a captured
    /// local would not work — a `Provider` caches its first value, so the
    /// container would never see the identity change at all, and the test would
    /// pass or fail for reasons that have nothing to do with the cache.
    ({ProviderContainer container, _FakeConsentRepo repo}) boot(
      Map<String?, AiConsentState> store,
      String? Function() user,
    ) {
      final repo = _FakeConsentRepo(store, user);
      final container = ProviderContainer(
        overrides: [
          authUserIdProvider.overrideWithValue(user()),
          aiConsentRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return (container: container, repo: repo);
    }

    void switchTo(
      ProviderContainer container,
      _FakeConsentRepo repo,
      String? user,
    ) {
      container.updateOverrides([
        authUserIdProvider.overrideWithValue(user),
        aiConsentRepositoryProvider.overrideWithValue(repo),
      ]);
    }

    test("B never inherits A's consent, and A keeps it", () async {
      // The requirement, exactly: A accepted v2, B has not.
      final store = <String?, AiConsentState>{
        'a': const AiConsentState(granted: true, isCurrent: true, version: 2),
        'b': const AiConsentState(granted: true, isCurrent: false, version: 1),
      };
      String? current = 'a';
      final b = boot(store, () => current);

      // A: allowed, and cached.
      expect(
        (await b.container.read(aiConsentProvider.notifier).current())
            .isCurrent,
        isTrue,
      );

      // Switch to B WITHOUT invalidating the consent provider — the
      // belt-and-braces case. The identity is part of the cache-hit condition,
      // so the stale "yes" must not be handed to B.
      current = 'b';
      switchTo(b.container, b.repo, current);
      final forB = await b.container.read(aiConsentProvider.notifier).current();
      expect(
        forB.isCurrent,
        isFalse,
        reason: "B must be asked; A's consent is not B's",
      );

      // Switch back: A is still allowed, and was never re-prompted.
      current = 'a';
      switchTo(b.container, b.repo, current);
      expect(
        (await b.container.read(aiConsentProvider.notifier).current())
            .isCurrent,
        isTrue,
      );
      expect(b.repo.grants, 0);
    });

    test('signing out drops the cached answer', () async {
      final store = <String?, AiConsentState>{
        'a': const AiConsentState(granted: true, isCurrent: true, version: 2),
      };
      String? current = 'a';
      final b = boot(store, () => current);

      expect(
        (await b.container.read(aiConsentProvider.notifier).current())
            .isCurrent,
        isTrue,
      );

      current = null; // signed out
      switchTo(b.container, b.repo, current);
      final signedOut = await b.container
          .read(aiConsentProvider.notifier)
          .current();
      expect(signedOut.isCurrent, isFalse);
    });
  });

  group('failure modes', () {
    test('an unreachable consent API is never an implied permission', () async {
      final (dio, _) = fakeDio((_) => jsonResponse({}, status: 500));
      await expectLater(
        AiConsentRepository(dio).read(),
        throwsA(isA<Object>()),
      );
      // The gate catches this and falls through to ASK, which is the safe
      // direction — asserted in ai_consent_gate's own coverage.
    });

    test('an out-of-date build is told to update, not looped', () async {
      // The server refuses a below-required grant with 422 rather than storing
      // an unsatisfiable row. The client surfaces it as an error instead of
      // silently re-showing the sheet forever.
      final (dio, _) = fakeDio(
        (_) => jsonResponse({
          'error': {
            'code': 'VALIDATION_ERROR',
            'message':
                'Please update Wear The Mood to continue with AI try-on.',
          },
        }, status: 422),
      );
      await expectLater(
        AiConsentRepository(dio).grant(),
        throwsA(isA<Object>()),
      );
    });
  });
}
