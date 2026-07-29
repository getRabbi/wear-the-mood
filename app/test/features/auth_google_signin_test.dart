import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/repositories/auth_repository.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google sign-in outcome propagation.
///
/// The bug these pin: `AuthController.signInWithGoogle` went through a `_run`
/// helper typed `Future<void> Function()`, so the repository's boolean was
/// silently coerced away and **every** non-throwing outcome reported success.
///
/// That matters because the repository's boolean means "a Supabase session exists
/// NOW", and it is legitimately `false` in two ordinary cases:
///
///   * the user dismissed the Google account picker;
///   * the browser OAuth fallback was launched, so the session only lands later
///     when the `com.fashionos.app://login-callback/` deep link returns.
///
/// Reporting `true` for either made the caller navigate with no session, which
/// bounced the user straight back to the sign-in screen. The router's own
/// `isAuthenticatedProvider` listener is what must carry those cases instead.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._googleResult);

  final Future<bool> Function() _googleResult;
  int calls = 0;

  @override
  Future<bool> signInWithGoogle() {
    calls++;
    return _googleResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeAuthRepository repo;

  ProviderContainer containerWith(Future<bool> Function() googleResult) {
    repo = _FakeAuthRepository(googleResult);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<bool> signIn(ProviderContainer c) =>
      c.read(authControllerProvider.notifier).signInWithGoogle();

  test('a completed native sign-in reports true with a clean state', () async {
    final container = containerWith(() async => true);
    expect(await signIn(container), isTrue);
    expect(container.read(authControllerProvider).hasError, isFalse);
    expect(repo.calls, 1);
  });

  test('a dismissed account picker reports FALSE, not success', () async {
    // The regression: this used to come back true, and the caller navigated.
    final container = containerWith(() async => false);
    expect(await signIn(container), isFalse);
    // Cancelling is not an error — no error state, nothing for the UI to show.
    expect(container.read(authControllerProvider).hasError, isFalse);
  });

  test('a launched browser OAuth fallback reports FALSE until the session lands', () async {
    // signInWithOAuth only opens the browser. Reporting true here is what sent
    // the user to the splash with no session, which then fell to the auth gate.
    final container = containerWith(() async => false);
    expect(await signIn(container), isFalse);
    expect(container.read(authControllerProvider).hasError, isFalse);
  });

  test('an AuthException reports false AND surfaces an error state', () async {
    final container = containerWith(
      () async => throw const AuthException('Google sign-in failed.'),
    );
    expect(await signIn(container), isFalse);
    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    // The structured exception is kept so the UI can localize it (§13).
    expect(state.error, isA<AuthException>());
  });

  test('an unexpected error reports false and is still surfaced', () async {
    final container = containerWith(() async => throw StateError('boom'));
    expect(await signIn(container), isFalse);
    expect(container.read(authControllerProvider).hasError, isTrue);
  });

  test('the repository is consulted exactly once per attempt', () async {
    final container = containerWith(() async => true);
    await signIn(container);
    await signIn(container);
    expect(repo.calls, 2);
  });
}
