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
    @JsonKey(name: 'job_type') required String jobType,
    required AiJobStatus status,
    @JsonKey(name: 'output_url') String? outputUrl,
    String? error,
  }) = _AiJob;

  factory AiJob.fromJson(Map<String, dynamic> json) => _$AiJobFromJson(json);
}
