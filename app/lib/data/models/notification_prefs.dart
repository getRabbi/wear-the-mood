/// Per-category push preferences from `/v1/notifications/preferences` (§20).
/// These gate PUSH delivery only — the in-app notification center always shows
/// every durable notification. Everything defaults on except [promotional],
/// which is strictly opt-in (default off).
///
/// The seven categories mirror the backend exactly (CLAUDE.md §3); JSON keys are
/// the canonical snake_case names.
class NotificationPreferences {
  const NotificationPreferences({
    this.accountUpdates = true,
    this.referralRewards = true,
    this.socialActivity = true,
    this.community = true,
    this.dailyStyle = true,
    this.productUpdates = true,
    this.promotional = false,
  });

  final bool accountUpdates;
  final bool referralRewards;
  final bool socialActivity;
  final bool community;
  final bool dailyStyle;
  final bool productUpdates;
  final bool promotional;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        accountUpdates: json['account_updates'] as bool? ?? true,
        referralRewards: json['referral_rewards'] as bool? ?? true,
        socialActivity: json['social_activity'] as bool? ?? true,
        community: json['community'] as bool? ?? true,
        dailyStyle: json['daily_style'] as bool? ?? true,
        productUpdates: json['product_updates'] as bool? ?? true,
        promotional: json['promotional'] as bool? ?? false,
      );

  NotificationPreferences copyWith({
    bool? accountUpdates,
    bool? referralRewards,
    bool? socialActivity,
    bool? community,
    bool? dailyStyle,
    bool? productUpdates,
    bool? promotional,
  }) => NotificationPreferences(
    accountUpdates: accountUpdates ?? this.accountUpdates,
    referralRewards: referralRewards ?? this.referralRewards,
    socialActivity: socialActivity ?? this.socialActivity,
    community: community ?? this.community,
    dailyStyle: dailyStyle ?? this.dailyStyle,
    productUpdates: productUpdates ?? this.productUpdates,
    promotional: promotional ?? this.promotional,
  );
}
