import 'package:freezed_annotation/freezed_annotation.dart';

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

@freezed
abstract class TryOnJob with _$TryOnJob {
  const factory TryOnJob({
    @JsonKey(name: 'job_id') required String jobId,
    required TryOnStatus status,
    @JsonKey(name: 'result_image_url') String? resultImageUrl,
    String? error,
  }) = _TryOnJob;

  factory TryOnJob.fromJson(Map<String, dynamic> json) =>
      _$TryOnJobFromJson(json);
}
