import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/tryon_job.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/tryon_repository.dart';
import 'tryon_state.dart';

/// Poll cadence + ceiling. Separate providers so widget/unit tests can override
/// them to run instantly.
final tryOnPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 2),
);
final tryOnPollTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 90),
);

/// Orchestrates a single try-on: create the job, poll until terminal, refresh
/// credits on success, and surface friendly errors. All AI runs server-side.
class TryOnController extends Notifier<TryOnState> {
  @override
  TryOnState build() => const TryOnState.idle();

  Future<void> start({
    required String personImageUrl,
    required String garmentImageUrl,
  }) async {
    // Guard double-taps while a run is in flight.
    if (state is TryOnSubmitting || state is TryOnPolling) return;

    final repo = ref.read(tryOnRepositoryProvider);
    final analytics = ref.read(analyticsProvider);
    state = const TryOnState.submitting();

    try {
      await analytics.track(AnalyticsEvents.tryonStarted);
      var job = await repo.createTryOn(
        personImageUrl: personImageUrl,
        garmentImageUrl: garmentImageUrl,
      );
      state = TryOnState.polling(job);

      final interval = ref.read(tryOnPollIntervalProvider);
      final deadline = DateTime.now().add(ref.read(tryOnPollTimeoutProvider));

      while (!job.status.isTerminal) {
        if (DateTime.now().isAfter(deadline)) {
          state = const TryOnState.failure(
            message: 'This is taking longer than usual. Please try again.',
          );
          return;
        }
        await Future<void>.delayed(interval);
        job = await repo.getJob(job.jobId);
        if (!job.status.isTerminal) state = TryOnState.polling(job);
      }

      if (job.status.isDone) {
        ref.invalidate(creditsProvider); // a credit was spent on success
        await analytics.track(AnalyticsEvents.tryonSucceeded);
        state = TryOnState.success(job);
      } else {
        state = TryOnState.failure(
          message: job.error ?? 'Try-on failed. Please try again.',
        );
      }
    } on ApiException catch (error) {
      state = TryOnState.failure(message: error.message, code: error.code);
    } catch (_) {
      state = const TryOnState.failure(
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Back to the picker for another attempt.
  void reset() => state = const TryOnState.idle();
}

final tryOnControllerProvider = NotifierProvider<TryOnController, TryOnState>(
  TryOnController.new,
);
