import 'package:freezed_annotation/freezed_annotation.dart';

part 'credits.freezed.dart';
part 'credits.g.dart';

/// User credit state + plan costs from `GET /v1/credits` (CLAUDE.md §12, §18).
/// Server-authoritative — the UI only ever reflects this, never a local counter.
@freezed
abstract class Credits with _$Credits {
  const factory Credits({
    required int balance, // plan credits (reset monthly, no rollover)
    @JsonKey(name: 'daily_free_used') required int dailyFreeUsed,
    @JsonKey(name: 'daily_free_limit') required int dailyFreeLimit,
    @JsonKey(name: 'daily_free_remaining') required int dailyFreeRemaining,
    @JsonKey(name: 'topup_balance') @Default(0) int topupBalance,
    @JsonKey(name: 'total_available') @Default(0) int totalAvailable,
    @Default('free') String tier, // free | pro | pro_max
    @JsonKey(name: 'monthly_credits') @Default(0) int monthlyCredits,
    @JsonKey(name: 'hd_allowed') @Default(false) bool hdAllowed,
    @JsonKey(name: 'std_cost') @Default(1) int stdCost,
    // One app credit, like every other render. HD is an entitlement (Pro Max)
    // rather than a price, so this default is no longer a different number —
    // the server still overrides it from `/v1/credits`.
    @JsonKey(name: 'hd_cost') @Default(1) int hdCost,
    // AI Enhance Item — server-authoritative price (the backend charges exactly
    // this), so the UI shows the same 4 and can never drift from the deduction.
    // Also one app credit. AI Enhance costs us two FASHN credits per result;
    // that is our production cost to carry, not a second thing to bill for.
    @JsonKey(name: 'enhance_cost') @Default(1) int enhanceCost,
  }) = _Credits;

  const Credits._();

  factory Credits.fromJson(Map<String, dynamic> json) =>
      _$CreditsFromJson(json);

  /// Spendable credits across all buckets (free trial + plan + top-up).
  int get spendable => totalAvailable;

  /// Whether the user can start a standard AI try-on right now.
  bool get canSpend => totalAvailable >= stdCost;

  /// Whether the user can afford an HD / Try-On Max render right now.
  bool get canAffordHd => hdAllowed && totalAvailable >= hdCost;

  /// Whether the user can afford an AI Enhance right now (4 credits).
  bool get canAffordEnhance => totalAvailable >= enhanceCost;

  bool get isSubscriber => tier != 'free';
}
