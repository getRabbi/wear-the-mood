import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/tryon_job.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';

class _FakeTryOnRepository extends TryOnRepository {
  _FakeTryOnRepository({
    this.createThrows,
    TryOnJob? created,
    this.polls = const [],
  }) : created =
           created ?? const TryOnJob(jobId: 'j', status: TryOnStatus.queued),
       super(Dio());

  final ApiException? createThrows;
  final TryOnJob created;
  final List<TryOnJob> polls;
  int _i = 0;

  @override
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    List<String>? garmentImageUrls,
    String? wardrobeItemId,
    String? idempotencyKey,
  }) async {
    if (createThrows != null) throw createThrows!;
    return created;
  }

  @override
  Future<TryOnJob> getJob(String jobId) async => polls[_i++];
}

ProviderContainer _container(TryOnRepository repo) {
  final container = ProviderContainer(
    overrides: [
      tryOnRepositoryProvider.overrideWithValue(repo),
      tryOnPollIntervalProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starts idle', () {
    final c = _container(_FakeTryOnRepository(polls: const []));
    expect(c.read(tryOnControllerProvider), isA<TryOnIdle>());
  });

  test('polls through to success and exposes the result', () async {
    final repo = _FakeTryOnRepository(
      polls: const [
        TryOnJob(jobId: 'j', status: TryOnStatus.processing),
        TryOnJob(jobId: 'j', status: TryOnStatus.done, resultImageUrl: 'r.jpg'),
      ],
    );
    final c = _container(repo);

    await c
        .read(tryOnControllerProvider.notifier)
        .start(personImageUrl: 'p', garmentImageUrls: const ['g']);

    final state = c.read(tryOnControllerProvider);
    expect(state, isA<TryOnSuccess>());
    expect((state as TryOnSuccess).job.resultImageUrl, 'r.jpg');
  });

  test('a failed job becomes a failure state with its error', () async {
    final repo = _FakeTryOnRepository(
      polls: const [
        TryOnJob(
          jobId: 'j',
          status: TryOnStatus.failed,
          error: 'provider_error',
        ),
      ],
    );
    final c = _container(repo);

    await c
        .read(tryOnControllerProvider.notifier)
        .start(personImageUrl: 'p', garmentImageUrls: const ['g']);

    final state = c.read(tryOnControllerProvider);
    expect(state, isA<TryOnFailure>());
    expect((state as TryOnFailure).message, 'provider_error');
  });

  test(
    'an ApiException surfaces its code (e.g. insufficient credits)',
    () async {
      final repo = _FakeTryOnRepository(
        createThrows: const ApiException(
          code: ApiErrorCode.insufficientCredits,
          message: 'Not enough credits.',
          statusCode: 402,
        ),
      );
      final c = _container(repo);

      await c
          .read(tryOnControllerProvider.notifier)
          .start(personImageUrl: 'p', garmentImageUrls: const ['g']);

      final state = c.read(tryOnControllerProvider);
      expect(state, isA<TryOnFailure>());
      expect((state as TryOnFailure).code, ApiErrorCode.insufficientCredits);
    },
  );

  test('reset returns to idle', () async {
    final repo = _FakeTryOnRepository(
      polls: const [TryOnJob(jobId: 'j', status: TryOnStatus.done)],
    );
    final c = _container(repo);
    final controller = c.read(tryOnControllerProvider.notifier);

    await controller.start(personImageUrl: 'p', garmentImageUrls: const ['g']);
    expect(c.read(tryOnControllerProvider), isA<TryOnSuccess>());

    controller.reset();
    expect(c.read(tryOnControllerProvider), isA<TryOnIdle>());
  });
}
