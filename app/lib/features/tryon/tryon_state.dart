import 'package:freezed_annotation/freezed_annotation.dart';

import '../../data/models/tryon_job.dart';

part 'tryon_state.freezed.dart';

/// UI state machine for one try-on attempt (CLAUDE.md §7). Drives the four
/// screen states (§4.3): idle/empty, loading (submitting + polling), content
/// (success), error (failure).
@freezed
sealed class TryOnState with _$TryOnState {
  /// Nothing started yet — show the picker.
  const factory TryOnState.idle() = TryOnIdle;

  /// Request sent, job not created yet.
  const factory TryOnState.submitting() = TryOnSubmitting;

  /// Job created, waiting for the worker (queued/processing).
  const factory TryOnState.polling(TryOnJob job) = TryOnPolling;

  /// Result is ready.
  const factory TryOnState.success(TryOnJob job) = TryOnSuccess;

  /// Failed — friendly message (+ backend code when available).
  const factory TryOnState.failure({required String message, String? code}) =
      TryOnFailure;
}
