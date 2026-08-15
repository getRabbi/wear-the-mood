import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/tryon_job.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/tryon_repository.dart';
import '../../shared/utils/uuid.dart';
import 'tryon_state.dart';
import 'tryon_trace.dart';

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
  /// The last submitted inputs, kept so a failed run's Retry re-submits the
  /// SAME person + garment stack + mode instead of dead-ending (mobile QA).
  ({
    String personImageUrl,
    List<TryOnGarmentRef> garments,
    bool hd,
    String modelSource,
    String? presetModelId,
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,
  })?
  _lastRequest;

  @override
  TryOnState build() => const TryOnState.idle();

  /// Whether a failed run can be re-submitted with the same inputs.
  bool get canRetry => _lastRequest != null;

  /// Re-submit the last inputs (a fresh job + fresh idempotency downstream).
  Future<void> retry() async {
    final last = _lastRequest;
    if (last == null) return;
    state = const TryOnState.idle(); // let start() through its in-flight guard
    await start(
      personImageUrl: last.personImageUrl,
      garments: last.garments,
      hd: last.hd,
      modelSource: last.modelSource,
      presetModelId: last.presetModelId,
      sourceProductId: last.sourceProductId,
      sourcePlacement: last.sourcePlacement,
      sourceCampaignId: last.sourceCampaignId,
    );
  }

  /// The trace for the run currently in flight, so the screens either side of
  /// the controller (Generate, and the result's first frame) can contribute
  /// their own stages to the same line. Null when nothing is running.
  TryOnTrace? _trace;

  /// The in-flight run's timing trace (§14). Measurement only — reading it
  /// changes nothing.
  TryOnTrace? get trace => _trace;

  Future<void> start({
    required String personImageUrl,
    /// The look, one entry per selected piece, each carrying its identity so the
    /// server can resolve the real garment role (spec Phase 2). Order is the
    /// user's; the SERVER decides render order from the roles it resolves.
    required List<TryOnGarmentRef> garments,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    // Shopping origin (§13). Null for every closet render; carried through a
    // Retry too, so a re-submitted shopping render is still a shopping render.
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,

    /// The trace started when the user tapped Generate, so the client stages
    /// before this point (body resolution, first paint) are on the same line.
    /// A fresh one is created when absent, e.g. for a Retry.
    TryOnTrace? trace,
  }) async {
    // Guard double-taps while a run is in flight.
    if (state is TryOnSubmitting || state is TryOnPolling) return;
    if (garments.isEmpty) return;
    _lastRequest = (
      personImageUrl: personImageUrl,
      garments: garments,
      hd: hd,
      modelSource: modelSource,
      presetModelId: presetModelId,
      sourceProductId: sourceProductId,
      sourcePlacement: sourcePlacement,
      sourceCampaignId: sourceCampaignId,
    );

    final repo = ref.read(tryOnRepositoryProvider);
    final analytics = ref.read(analyticsProvider);
    state = const TryOnState.submitting();

    // ONE idempotency key per logical request, minted here rather than inside
    // the repository, so the trace token can be derived from the same value the
    // server sees. The key itself is unchanged — same uniqueness, same
    // no-double-charge guarantee (§9).
    final idempotencyKey = uuidV4();
    final run = trace ?? TryOnTrace(idempotencyKey);
    _trace = run;

    try {
      await analytics.track(AnalyticsEvents.tryonStarted);
      if (modelSource == 'studio_model') {
        await analytics.track(AnalyticsEvents.studioModelTryonStarted);
      }
      run.mark(TryOnStages.submitSent);
      // Send the full outfit stack. The SERVER plans it — resolving each piece's
      // garment role, ordering the steps and choosing the model per piece — and
      // the worker chains the renders in that order.
      var job = await repo.createTryOn(
        personImageUrl: personImageUrl,
        garments: garments,
        hd: hd,
        modelSource: modelSource,
        presetModelId: presetModelId,
        idempotencyKey: idempotencyKey,
        sourceProductId: sourceProductId,
        sourcePlacement: sourcePlacement,
        sourceCampaignId: sourceCampaignId,
      );
      run.mark(TryOnStages.submitAccepted);
      // Credits are RESERVED (debited) at submit now (§7/§12) — refresh the
      // balance so the chip reflects the hold immediately.
      ref.invalidate(creditsProvider);
      state = TryOnState.polling(job);

      final interval = ref.read(tryOnPollIntervalProvider);
      final deadline = DateTime.now().add(ref.read(tryOnPollTimeoutProvider));

      var polls = 0;
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
        polls++;
        // The FIRST status check specifically: the loop sleeps before it, so a
        // job that finished immediately still waits out one interval. Timing it
        // separately is what will show whether that costs anything real.
        run.mark(TryOnStages.firstPoll);
        if (!job.status.isTerminal) state = TryOnState.polling(job);
      }
      run.mark(TryOnStages.terminal, polls);

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
    } finally {
      // Emitted on EVERY exit path, including a failure — a run that failed
      // slowly is exactly as interesting as one that succeeded slowly.
      ref.read(tryOnTraceSinkProvider)(run);
    }
  }

  /// Back to the picker for another attempt.
  void reset() => state = const TryOnState.idle();
}

final tryOnControllerProvider = NotifierProvider<TryOnController, TryOnState>(
  TryOnController.new,
);
