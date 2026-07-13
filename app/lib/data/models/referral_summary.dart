/// The signed-in user's referral standing from `GET /v1/referrals/me` (§24).
/// A plain immutable DTO (no private friend data ever crosses this boundary).
class ReferralRewardItem {
  const ReferralRewardItem({required this.rewardCredits, this.creditedAt});

  final int rewardCredits;
  final DateTime? creditedAt;

  factory ReferralRewardItem.fromJson(Map<String, dynamic> json) =>
      ReferralRewardItem(
        rewardCredits: (json['reward_credits'] as num?)?.toInt() ?? 0,
        creditedAt: json['credited_at'] is String
            ? DateTime.tryParse(json['credited_at'] as String)
            : null,
      );
}

class ReferralSummary {
  const ReferralSummary({
    required this.code,
    required this.url,
    required this.bonus,
    this.successfulCount = 0,
    this.totalEarned = 0,
    this.enabled = true,
    this.recent = const [],
  });

  final String code;
  final String url;
  final int bonus; // bonus_per_successful_referral (server-controlled)
  final int successfulCount;
  final int totalEarned;
  final bool enabled;
  final List<ReferralRewardItem> recent;

  factory ReferralSummary.fromJson(Map<String, dynamic> json) => ReferralSummary(
    code: json['referral_code'] as String? ?? '',
    url: json['referral_url'] as String? ?? '',
    bonus: (json['bonus_per_successful_referral'] as num?)?.toInt() ?? 0,
    successfulCount: (json['successful_referral_count'] as num?)?.toInt() ?? 0,
    totalEarned: (json['total_bonus_credits_earned'] as num?)?.toInt() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    recent: [
      for (final e in (json['recent'] as List<dynamic>? ?? const []))
        ReferralRewardItem.fromJson(e as Map<String, dynamic>),
    ],
  );
}
