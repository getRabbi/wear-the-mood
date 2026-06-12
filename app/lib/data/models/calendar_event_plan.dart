import 'package:freezed_annotation/freezed_annotation.dart';

import 'stylist_suggestion.dart';

part 'calendar_event_plan.freezed.dart';
part 'calendar_event_plan.g.dart';

/// One calendar event paired with its suggested outfit (CLAUDE.md §24). Maps an
/// item of the `POST /v1/calendar/plan` response.
@freezed
abstract class CalendarEventPlan with _$CalendarEventPlan {
  const factory CalendarEventPlan({
    required String title,
    @JsonKey(name: 'starts_at') DateTime? startsAt,
    required StylistSuggestion suggestion,
  }) = _CalendarEventPlan;

  factory CalendarEventPlan.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventPlanFromJson(json);
}
