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
// Must comfortably exceed the backend/FASHN ceiling (180s) so the app waits for
// the REAL terminal status. Otherwise the app gives up while the worker finishes
// and charges — the user sees "failed" but a credit was spent (CLAUDE.md §7).
final tryOnPollTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 220),
);

/// Orchestrates a single try-on: create the job, poll until terminal, refresh
/// credits on success, and surface friendly errors. All AI runs server-side.
class TryOnController extends Notifier<TryOnState> {
  @override
  TryOnState build() => const TryOnState.idle();

  Future<void> start({
    required String personImageUrl,
    required List<String> garmentImageUrls,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
  }) async {
    // Guard double-taps while a run is in flight.
    if (state is TryOnSubmitting || state is TryOnPolling) return;
    if (garmentImageUrls.isEmpty) return;

    final repo = ref.read(tryOnRepositoryProvider);
    final analytics = ref.read(analyticsProvider);
    state = const TryOnState.submitting();

    try {
      await analytics.track(AnalyticsEvents.tryonStarted);
      // Send the full outfit stack (render order); the worker chains the renders.
      var job = await repo.createTryOn(
        personImageUrl: personImageUrl,
        garmentImageUrls: garmentImageUrls,
        hd: hd,
        modelSource: modelSource,
        presetModelId: presetModelId,
      );
      // Credits are RESERVED (debited) at submit now (§7/§12) — refresh the
      // balance so the chip reflects the hold immediately.
      ref.invalidate(creditsProvider);
      state = TryOnState.polling(job);

      final interval = ref.read(tryOnPollIntervalProvider);
      final deadline = DateTime.now().add(ref.read(tryOnPollTimeoutProvider));

      while (!job.status.isTerminal) {
        if (DateTime.now().isAfter(deadline)) {
          // Rare safety net (the deadline exceeds the backend ceiling). The job
          // is still processing; credits were reserved at submit and are refunded
          // automatically if it ultimately fails — be honest rather than implying
          // a wasted attempt.
          state = const TryOnState.failure(
            message:
                "Still rendering — this one's taking a while. If it doesn't "
                'finish, your credits are refunded automatically; please check '
                'back shortly.',
          );
          return;
        }
        await Future<void>.delayed(interval);
        job = await repo.getJob(job.jobId);
        if (!job.status.isTerminal) state = TryOnState.polling(job);
      }

      if (job.status.isDone) {
        ref.invalidate(creditsProvider); // reflect the final balance
        ref.invalidate(tryOnResultsProvider); // show it in history
        await analytics.track(AnalyticsEvents.tryonSucceeded);
        state = TryOnState.success(job);
      } else {
        // A failed job is refunded server-side — refresh so the restored balance
        // shows.
        ref.invalidate(creditsProvider);
        state = TryOnState.failure(
          message: job.error ?? 'Try-on failed. Please try again.',
        );
      }
    } on ApiException catch (error) {
      // A rejected submit never debited, but keep the balance fresh regardless.
      ref.invalidate(creditsProvider);
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
