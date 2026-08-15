import 'package:freezed_annotation/freezed_annotation.dart';

import 'tryon_source.dart';

part 'tryon_job.freezed.dart';
part 'tryon_job.g.dart';

/// Async try-on job lifecycle, mirrored from the backend (CLAUDE.md §7).
enum TryOnStatus {
  @JsonValue('queued')
  queued,
  @JsonValue('processing')
  processing,
  @JsonValue('done')
  done,
  @JsonValue('failed')
  failed,
}

extension TryOnStatusX on TryOnStatus {
  /// No further polling needed once a job reaches a terminal state.
  bool get isTerminal => this == TryOnStatus.done || this == TryOnStatus.failed;
  bool get isDone => this == TryOnStatus.done;
  bool get isFailed => this == TryOnStatus.failed;
}

/// A piece the server planned NOT to render, and why (spec Phase 7).
///
/// Its existence is the contract: a look never quietly loses a garment, so
/// anything left out arrives named, with a sentence the user can act on.
@freezed
abstract class TryOnSkippedGarment with _$TryOnSkippedGarment {
  const factory TryOnSkippedGarment({
    @JsonKey(name: 'item_key') required String itemKey,
    required String reason,
    required String message,
    String? canonical,
  }) = _TryOnSkippedGarment;

  factory TryOnSkippedGarment.fromJson(Map<String, dynamic> json) =>
      _$TryOnSkippedGarmentFromJson(json);
}

@freezed
abstract class TryOnJob with _$TryOnJob {
  const factory TryOnJob({
    @JsonKey(name: 'job_id') required String jobId,
    required TryOnStatus status,
    @JsonKey(name: 'result_image_url') String? resultImageUrl,
    String? error,
    // Null for a closet render, and for every job created before shopping
    // try-on existed. Both read the same way, which is what makes this
    // backward compatible (§37.4).
    TryOnSource? source,
    // Look accounting. Absent on a job created before plans existed, and on a
    // backend that predates them — both default to "nothing to say", which is
    // exactly how those jobs behaved.
    @JsonKey(name: 'total_steps') int? totalSteps,
    @JsonKey(name: 'current_step') int? currentStep,
    @JsonKey(name: 'applied_item_keys')
    @Default(<String>[])
    List<String> appliedItemKeys,
    @Default(<TryOnSkippedGarment>[]) List<TryOnSkippedGarment> skipped,
  }) = _TryOnJob;

  factory TryOnJob.fromJson(Map<String, dynamic> json) =>
      _$TryOnJobFromJson(json);
}

extension TryOnJobProgress on TryOnJob {
  /// "2 of 4" progress for the generating screen, or null when the job carries
  /// no plan (a legacy job, or a single-piece render where a count adds nothing).
  ({int done, int total})? get stepProgress {
    final total = totalSteps;
    if (total == null || total < 2) return null;
    return (done: (currentStep ?? 0).clamp(0, total), total: total);
  }
}
