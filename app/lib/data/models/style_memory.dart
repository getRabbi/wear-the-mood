import 'package:freezed_annotation/freezed_annotation.dart';

part 'style_memory.freezed.dart';
part 'style_memory.g.dart';

/// A structured reason a user gives for "Not me" (RETENTION spec §12.1).
///
/// Only three of these are TASTE. `identityIssue`, `garmentIssue` and
/// `bodyProportionIssue` are complaints about the render itself — the server
/// records them but deliberately does not learn a preference from them, so a
/// pipeline failure never becomes "you dislike navy".
enum RejectionReason {
  identityIssue('identity_issue'),
  garmentIssue('garment_issue'),
  notMyStyle('not_my_style'),
  bodyProportionIssue('body_proportion_issue'),
  colorIssue('color_issue'),
  occasionMismatch('occasion_mismatch'),
  other('other');

  const RejectionReason(this.wire);

  /// The value the API expects. Never send `name`.
  final String wire;
}

/// One thing WTM believes about the user, with the evidence behind it.
@freezed
abstract class PreferenceItem with _$PreferenceItem {
  const factory PreferenceItem({
    required String value,
    @Default(0) double weight,

    /// 0..1. Below [PreferenceItem.stateThreshold] the UI must phrase this as
    /// a hunch, never a fact (§12.3).
    @Default(0) double confidence,

    /// `stated` = the user told us. `inferred` = we noticed it.
    @Default('inferred') String source,
    @JsonKey(name: 'updated_at') String? updatedAt,
  }) = _PreferenceItem;

  const PreferenceItem._();

  factory PreferenceItem.fromJson(Map<String, dynamic> json) =>
      _$PreferenceItemFromJson(json);

  /// Mirrors the server's `_STATE_THRESHOLD`. Kept in sync deliberately: the
  /// server decides whether to WRITE a summary, the app decides whether to
  /// show a single preference as settled.
  static const stateThreshold = 0.35;

  /// True when the user said this outright, so it may be stated as fact.
  bool get isStated => source == 'stated';

  /// True when this is confident enough to show without hedging.
  bool get isConfident => isStated || confidence >= stateThreshold;
}

/// Everything WTM has learned about one user's taste.
@freezed
abstract class StyleMemoryProfile with _$StyleMemoryProfile {
  const factory StyleMemoryProfile({
    @Default(1) int version,
    @Default(0) double confidence,
    @JsonKey(name: 'signal_count') @Default(0) int signalCount,
    @JsonKey(name: 'personalization_enabled')
    @Default(true)
    bool personalizationEnabled,

    /// One hedged sentence, or null when we do not know enough to say anything.
    @JsonKey(name: 'preference_summary') String? preferenceSummary,
    @JsonKey(name: 'preferred_colors')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> preferredColors,
    @JsonKey(name: 'avoided_colors')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> avoidedColors,
    @JsonKey(name: 'preferred_silhouettes')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> preferredSilhouettes,
    @JsonKey(name: 'avoided_silhouettes')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> avoidedSilhouettes,
    @JsonKey(name: 'preferred_aesthetics')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> preferredAesthetics,
    @JsonKey(name: 'preferred_occasions')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> preferredOccasions,
    @JsonKey(name: 'preferred_moods')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> preferredMoods,
    @JsonKey(name: 'fit_visual_preferences')
    @Default(<PreferenceItem>[])
    List<PreferenceItem> fitVisualPreferences,
  }) = _StyleMemoryProfile;

  const StyleMemoryProfile._();

  factory StyleMemoryProfile.fromJson(Map<String, dynamic> json) =>
      _$StyleMemoryProfileFromJson(json);

  /// True when nothing has been learned yet — the honest empty state, and NOT
  /// an error.
  bool get isEmpty => signalCount == 0 && preferenceSummary == null;

  /// The facet keys shown on the "what WTM knows" screen, in reading order,
  /// paired with their entries.
  ///
  /// Deliberately returns the KEY, not a label: the key is what the correction
  /// endpoint expects, and the label is user-facing text that has to come from
  /// l10n (CLAUDE.md §4.3). A display string in a data model would be a string
  /// no translator ever sees.
  List<({String facet, List<PreferenceItem> items})> get facets => [
    (facet: 'preferred_colors', items: preferredColors),
    (facet: 'preferred_silhouettes', items: preferredSilhouettes),
    (facet: 'preferred_aesthetics', items: preferredAesthetics),
    (facet: 'preferred_occasions', items: preferredOccasions),
    (facet: 'preferred_moods', items: preferredMoods),
    (facet: 'avoided_colors', items: avoidedColors),
    (facet: 'avoided_silhouettes', items: avoidedSilhouettes),
  ];
}

/// The response to recording a signal — including the restrained "WTM
/// learned…" line, which is null whenever nothing actually changed.
@freezed
abstract class StyleMemorySignalResult with _$StyleMemorySignalResult {
  const factory StyleMemorySignalResult({
    @Default(false) bool recorded,
    String? learned,
    StyleMemoryProfile? profile,
  }) = _StyleMemorySignalResult;

  factory StyleMemorySignalResult.fromJson(Map<String, dynamic> json) =>
      _$StyleMemorySignalResultFromJson(json);
}

/// The result of submitting Keep it / Not me on a render.
@freezed
abstract class TryOnFeedbackResult with _$TryOnFeedbackResult {
  const factory TryOnFeedbackResult({
    @JsonKey(name: 'result_id') required String resultId,
    required String outcome,
    @Default(false) bool recorded,
    String? learned,
    StyleMemoryProfile? profile,
  }) = _TryOnFeedbackResult;

  factory TryOnFeedbackResult.fromJson(Map<String, dynamic> json) =>
      _$TryOnFeedbackResultFromJson(json);
}
