import 'package:freezed_annotation/freezed_annotation.dart';

part 'planner.freezed.dart';
part 'planner.g.dart';

/// The four mood zones the board already uses (`ui/home/wtm_mood.dart`).
///
/// The planner speaks the SAME vocabulary as the existing mood slider rather
/// than inventing a second one, so a mood set on Home and a mood picked in the
/// planner are the same fact.
enum PlannerMood {
  calm('calm'),
  confident('confident'),
  bold('bold'),
  rebel('rebel');

  const PlannerMood(this.wire);

  final String wire;

  /// The zone for a 0..1 slider value — the same four-way split as
  /// [WtmMoodZone], so the two can never disagree about where `bold` starts.
  static PlannerMood ofValue(double value) => switch (value) {
    < 0.25 => calm,
    < 0.5 => confident,
    < 0.75 => bold,
    _ => rebel,
  };
}

/// Optional context for a plan. Null is a valid answer: the user may simply
/// have picked a feeling.
enum PlannerOccasion {
  everyday('everyday'),
  work('work'),
  date('date'),
  brunch('brunch'),
  wedding('wedding'),
  nightOut('night_out');

  const PlannerOccasion(this.wire);

  final String wire;
}

/// Styling direction for a mood. **Costs nothing and renders nothing** —
/// turning a plan into an image is a separate, explicit, paid action.
@freezed
abstract class MoodPlan with _$MoodPlan {
  const factory MoodPlan({
    required String id,
    required String mood,
    String? occasion,
    @Default('') String headline,
    @Default(<String>[]) List<String> lines,

    /// Wardrobe item ids the direction referenced, in build order.
    @JsonKey(name: 'item_ids') @Default(<String>[]) List<String> itemIds,

    /// True when no real pieces could be named. The UI must NOT claim the
    /// direction was picked from the user's closet in that case.
    @Default(false) bool generic,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _MoodPlan;

  factory MoodPlan.fromJson(Map<String, dynamic> json) =>
      _$MoodPlanFromJson(json);
}

/// A user-entered event. No calendar is read or written (spec §15).
@freezed
abstract class StyleEvent with _$StyleEvent {
  const factory StyleEvent({
    required String id,
    required String name,
    @JsonKey(name: 'event_at') required DateTime eventAt,
    String? occasion,

    /// The saved look this event is dressed for. Saved looks live on the
    /// device, so this is the look's stable id plus its durable image URL.
    @JsonKey(name: 'look_ref') String? lookRef,
    @JsonKey(name: 'look_image_url') String? lookImageUrl,
    String? note,

    /// Opt-in per event. Creating an event never signs the user up for push.
    @JsonKey(name: 'reminder_opt_in') @Default(false) bool reminderOptIn,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _StyleEvent;

  const StyleEvent._();

  factory StyleEvent.fromJson(Map<String, dynamic> json) =>
      _$StyleEventFromJson(json);

  /// Whole days until the event, floor-clamped at zero. Used for the "in 3
  /// days" line — computed from the device clock on purpose, because that is
  /// the clock the user is reading the screen on.
  int get daysAway {
    final diff = eventAt.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays;
  }

  bool get isPast => eventAt.isBefore(DateTime.now());
}

@freezed
abstract class StyleEventList with _$StyleEventList {
  const factory StyleEventList({
    @Default(<StyleEvent>[]) List<StyleEvent> events,
    @JsonKey(name: 'next_event') StyleEvent? nextEvent,
  }) = _StyleEventList;

  factory StyleEventList.fromJson(Map<String, dynamic> json) =>
      _$StyleEventListFromJson(json);
}
