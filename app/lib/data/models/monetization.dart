import 'package:freezed_annotation/freezed_annotation.dart';

part 'monetization.freezed.dart';
part 'monetization.g.dart';

/// App credits per render quality, as the SERVER will charge them.
@freezed
abstract class RenderCosts with _$RenderCosts {
  const factory RenderCosts({
    @Default(1) int standard,
    @Default(4) int hd,
    @Default(4) int enhance,
  }) = _RenderCosts;

  factory RenderCosts.fromJson(Map<String, dynamic> json) =>
      _$RenderCostsFromJson(json);
}

/// One purchasable plan as the server describes it.
///
/// `priceUsd` is for reconciliation ONLY. The paywall must render the STORE's
/// localized price string (RETENTION spec §7.2) — the store is the authority on
/// what the user actually pays, and this number is not localized, not taxed and
/// not currency-converted.
@freezed
abstract class PlanPresentation with _$PlanPresentation {
  const factory PlanPresentation({
    required String tier,
    @Default('subscription') String kind,
    @JsonKey(name: 'price_usd') @Default(0.0) double priceUsd,
    @JsonKey(name: 'monthly_credits') @Default(0) int monthlyCredits,
    @JsonKey(name: 'hd_allowed') @Default(false) bool hdAllowed,
    @Default(false) bool priority,
    @JsonKey(name: 'play_product_id') String? playProductId,
    @JsonKey(name: 'app_product_id') String? appProductId,
  }) = _PlanPresentation;

  factory PlanPresentation.fromJson(Map<String, dynamic> json) =>
      _$PlanPresentationFromJson(json);
}

/// When WTM is allowed to interrupt the user with a monetization surface.
@freezed
abstract class PaywallPolicy with _$PaywallPolicy {
  const factory PaywallPolicy({
    @JsonKey(name: 'cooldown_hours') @Default(24) int cooldownHours,
    @JsonKey(name: 'post_purchase_cooldown_hours')
    @Default(72)
    int postPurchaseCooldownHours,
    @JsonKey(name: 'timing_variant') @Default('control') String timingVariant,

    /// False when a cooldown is in force. Consulted ONLY by surfaces WTM
    /// raises on its own — a paywall the user opened never checks this.
    @JsonKey(name: 'may_interrupt') @Default(true) bool mayInterrupt,
    @JsonKey(name: 'block_reason') String? blockReason,
    @JsonKey(name: 'retry_after_hours') int? retryAfterHours,
  }) = _PaywallPolicy;

  factory PaywallPolicy.fromJson(Map<String, dynamic> json) =>
      _$PaywallPolicyFromJson(json);
}

/// The server-authoritative monetization snapshot for this user.
///
/// The app REFLECTS this; it never enforces from it. Every cost, gate and
/// entitlement is applied server-side, so a client that ignored this response
/// entirely would face the same charges and the same refusals.
@freezed
abstract class MonetizationConfig with _$MonetizationConfig {
  const factory MonetizationConfig({
    @Default(1) int version,
    @JsonKey(name: 'render_costs')
    @Default(RenderCosts())
    RenderCosts renderCosts,
    @JsonKey(name: 'free_render_limit') @Default(0) int freeRenderLimit,
    @JsonKey(name: 'free_render_remaining') @Default(0) int freeRenderRemaining,
    @Default('free') String tier,
    @JsonKey(name: 'hd_allowed') @Default(false) bool hdAllowed,
    @Default(<PlanPresentation>[]) List<PlanPresentation> plans,
    @Default(PaywallPolicy()) PaywallPolicy paywall,
    @JsonKey(name: 'trial_enabled') @Default(false) bool trialEnabled,
    @JsonKey(name: 'trial_credit_cap') int? trialCreditCap,
    @JsonKey(name: 'rollover_enabled') @Default(false) bool rolloverEnabled,
    @Default(<String, String>{}) Map<String, String> experiments,
    @JsonKey(name: 'paywall_v2') @Default(false) bool paywallV2,
    @JsonKey(name: 'render_gate_v2') @Default(false) bool renderGateV2,
  }) = _MonetizationConfig;

  const MonetizationConfig._();

  factory MonetizationConfig.fromJson(Map<String, dynamic> json) =>
      _$MonetizationConfigFromJson(json);

  bool get isSubscriber => tier != 'free';

  /// True when a free user has spent their lifetime renders. Deliberately NOT
  /// a reason to lock the app: saved looks, planning and Style Memory all stay
  /// open (§9) — only a NEW paid render is gated.
  bool get freeRendersExhausted => !isSubscriber && freeRenderRemaining <= 0;
}

/// A monetization surface was shown, dismissed, acted on, or converted.
enum MonetizationSurface {
  paywall('paywall'),
  topupSheet('topup_sheet'),
  renderGate('render_gate'),
  upgradePrompt('upgrade_prompt');

  const MonetizationSurface(this.wire);

  final String wire;
}

enum MonetizationAction {
  viewed('viewed'),
  dismissed('dismissed'),
  ctaTapped('cta_tapped'),
  purchased('purchased');

  const MonetizationAction(this.wire);

  final String wire;
}
