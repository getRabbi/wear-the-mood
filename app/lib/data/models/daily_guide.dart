import 'package:freezed_annotation/freezed_annotation.dart';

part 'daily_guide.freezed.dart';
part 'daily_guide.g.dart';

/// A call-to-action on a daily guide (FEATURES_COMMUNITY_PLUS · Daily Guide).
@freezed
abstract class GuideCta with _$GuideCta {
  const factory GuideCta({
    required String label,
    required String action, // tryon | closet | wardrobe_add | news | ...
    String? target,
  }) = _GuideCta;

  factory GuideCta.fromJson(Map<String, dynamic> json) =>
      _$GuideCtaFromJson(json);
}

/// The day's editorial styling guide for the Home "Today" section.
@freezed
abstract class DailyGuide with _$DailyGuide {
  const factory DailyGuide({
    required String id,
    required DateTime date,
    required String title,
    String? summary,
    String? body,
    @JsonKey(name: 'image_url') String? imageUrl,
    @Default(<String>[]) List<String> topics,
    @Default(<GuideCta>[]) List<GuideCta> cta,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _DailyGuide;

  factory DailyGuide.fromJson(Map<String, dynamic> json) =>
      _$DailyGuideFromJson(json);
}
