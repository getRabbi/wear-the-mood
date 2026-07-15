/// Per-category push preferences from `/v1/notifications/preferences` (§20).
/// These gate PUSH delivery only — the in-app notification center always shows
/// every durable notification. Promotions are opt-in (default off).
class NotificationPreferences {
  const NotificationPreferences({
    this.social = true,
    this.referral = true,
    this.account = true,
    this.community = true,
    this.style = true,
    this.promotions = false,
  });

  final bool social;
  final bool referral;
  final bool account;
  final bool community;
  final bool style;
  final bool promotions;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        social: json['social'] as bool? ?? true,
        referral: json['referral'] as bool? ?? true,
        account: json['account'] as bool? ?? true,
        community: json['community'] as bool? ?? true,
        style: json['style'] as bool? ?? true,
        promotions: json['promotions'] as bool? ?? false,
      );

  NotificationPreferences copyWith({
    bool? social,
    bool? referral,
    bool? account,
    bool? community,
    bool? style,
    bool? promotions,
  }) => NotificationPreferences(
    social: social ?? this.social,
    referral: referral ?? this.referral,
    account: account ?? this.account,
    community: community ?? this.community,
    style: style ?? this.style,
    promotions: promotions ?? this.promotions,
  );
}
