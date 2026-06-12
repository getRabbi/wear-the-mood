import 'package:freezed_annotation/freezed_annotation.dart';

part 'wardrobe_analytics.freezed.dart';
part 'wardrobe_analytics.g.dart';

/// A highlighted piece in the wardrobe analytics (CLAUDE.md §24).
@freezed
abstract class WardrobeItemStat with _$WardrobeItemStat {
  const factory WardrobeItemStat({
    required String id,
    String? title,
    @JsonKey(name: 'image_url') String? imageUrl,
    double? cost,
    @JsonKey(name: 'wear_count') @Default(0) int wearCount,
    @JsonKey(name: 'cost_per_wear') double? costPerWear,
  }) = _WardrobeItemStat;

  factory WardrobeItemStat.fromJson(Map<String, dynamic> json) =>
      _$WardrobeItemStatFromJson(json);
}

/// Cost-per-wear + wardrobe ROI insights (CLAUDE.md §24). Maps the
/// `GET /v1/wardrobe/analytics` response.
@freezed
abstract class WardrobeAnalytics with _$WardrobeAnalytics {
  const factory WardrobeAnalytics({
    @JsonKey(name: 'item_count') @Default(0) int itemCount,
    @JsonKey(name: 'total_spend') double? totalSpend,
    @JsonKey(name: 'total_wears') @Default(0) int totalWears,
    @JsonKey(name: 'never_worn_count') @Default(0) int neverWornCount,
    @JsonKey(name: 'avg_cost_per_wear') double? avgCostPerWear,
    @JsonKey(name: 'most_worn') WardrobeItemStat? mostWorn,
    @JsonKey(name: 'best_value') WardrobeItemStat? bestValue,
    @JsonKey(name: 'biggest_waste') WardrobeItemStat? biggestWaste,
  }) = _WardrobeAnalytics;

  factory WardrobeAnalytics.fromJson(Map<String, dynamic> json) =>
      _$WardrobeAnalyticsFromJson(json);
}
