import 'package:freezed_annotation/freezed_annotation.dart';

part 'wardrobe_gap.freezed.dart';
part 'wardrobe_gap.g.dart';

/// A missing wardrobe essential (CLAUDE.md §24). [suggestion] is the query used
/// to turn the gap into a shop-the-look affiliate link.
@freezed
abstract class WardrobeGap with _$WardrobeGap {
  const factory WardrobeGap({
    required String category,
    required String title,
    required String suggestion,
    @JsonKey(name: 'owned_count') @Default(0) int ownedCount,
  }) = _WardrobeGap;

  factory WardrobeGap.fromJson(Map<String, dynamic> json) =>
      _$WardrobeGapFromJson(json);
}
