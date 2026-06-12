import 'package:freezed_annotation/freezed_annotation.dart';

part 'referral.freezed.dart';
part 'referral.g.dart';

/// The user's referral code + stats (CLAUDE.md §24). Maps `GET /v1/referrals`.
@freezed
abstract class Referral with _$Referral {
  const factory Referral({
    required String code,
    @JsonKey(name: 'referral_count') @Default(0) int referralCount,
    @JsonKey(name: 'reward_credits') @Default(0) int rewardCredits,
  }) = _Referral;

  factory Referral.fromJson(Map<String, dynamic> json) =>
      _$ReferralFromJson(json);
}
