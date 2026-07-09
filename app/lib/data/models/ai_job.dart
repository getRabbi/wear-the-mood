import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_job.freezed.dart';
part 'ai_job.g.dart';

/// Shared AI Studio job lifecycle, mirrored from the backend (BUILD_PROMPT_PRO_
/// PROMAX.md). Covers enhance_item + catalog_model. Try-on uses [TryOnJob].
enum AiJobStatus {
  @JsonValue('queued')
  queued,
  @JsonValue('processing')
  processing,
  @JsonValue('completed')
  completed,
  @JsonValue('failed')
  failed,
}

extension AiJobStatusX on AiJobStatus {
  bool get isTerminal =>
      this == AiJobStatus.completed || this == AiJobStatus.failed;
  bool get isDone => this == AiJobStatus.completed;
  bool get isFailed => this == AiJobStatus.failed;
}

@freezed
abstract class AiJob with _$AiJob {
  const factory AiJob({
    @JsonKey(name: 'job_id') required String jobId,
    required AiJobStatus status,
    // The submit (create) response is just {job_id, status}; only the poll
    // (GET /v1/ai/jobs) carries job_type — so it must be optional or parsing the
    // 202 submit body throws (which surfaced as a false "couldn't load" error).
    @JsonKey(name: 'job_type') @Default('') String jobType,
    @JsonKey(name: 'output_url') String? outputUrl,
    String? error,
  }) = _AiJob;

  factory AiJob.fromJson(Map<String, dynamic> json) => _$AiJobFromJson(json);
}
