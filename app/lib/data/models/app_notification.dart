import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_notification.freezed.dart';
part 'app_notification.g.dart';

/// One in-app notification (CLAUDE.md §1 pillar 4). Named `AppNotification` to
/// avoid clashing with Flutter's `Notification`. JSON matches `/v1/notifications`.
@freezed
abstract class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    @JsonKey(name: 'actor_id') String? actorId,
    required String type,
    required String title,
    String? body,
    @JsonKey(name: 'target_type') String? targetType,
    @JsonKey(name: 'target_id') String? targetId,
    @JsonKey(name: 'is_read') @Default(false) bool isRead,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _AppNotification;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);
}
