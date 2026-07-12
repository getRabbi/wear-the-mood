import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/repositories/auth_repository.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Apple sign-in has three user-visible outcomes the WTM auth screen relies
/// on: signed in (route on), sheet dismissed (stay put, no error), and failure
/// (error state for the localized message). Repository is faked — no SDKs.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._appleResult);

  final Future<bool> Function() _appleResult;

  @override
  Future<bool> signInWithApple() => _appleResult();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  ProviderContainer containerWith(Future<bool> Function() appleResult) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(appleResult),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('success → returns true with a clean (data) state', () async {
    final container = containerWith(() async => true);
    final ok = await container
        .read(authControllerProvider.notifier)
        .signInWithApple();
    expect(ok, isTrue);
    expect(container.read(authControllerProvider).hasError, isFalse);
  });

  test('user cancelled the Apple sheet → false, and NOT an error', () async {
    final container = containerWith(() async => false);
    final ok = await container
        .read(authControllerProvider.notifier)
        .signInWithApple();
    expect(ok, isFalse);
    expect(
      container.read(authControllerProvider).hasError,
      isFalse,
      reason: 'dismissing the sheet must not flash an error message',
    );
  });

  test('failure → false with the AuthException on the state', () async {
    final container = containerWith(
      () async => throw const AuthException('Apple sign-in failed: unknown'),
    );
    final ok = await container
        .read(authControllerProvider.notifier)
        .signInWithApple();
    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AuthException>());
  });
}
