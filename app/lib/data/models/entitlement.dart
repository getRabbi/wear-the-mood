import 'package:freezed_annotation/freezed_annotation.dart';

part 'entitlement.freezed.dart';
part 'entitlement.g.dart';

/// The user's current premium entitlement (CLAUDE.md §18). Reflected from the
/// server (`GET /v1/billing/entitlement`); the server stays the source of truth
/// for premium actions — the app never gates on its own claim.
@freezed
abstract class Entitlement with _$Entitlement {
  const factory Entitlement({
    @Default(false) bool active,
    @JsonKey(name: 'product_id') String? productId,
    String? store,
    @JsonKey(name: 'expires_at') DateTime? expiresAt,
  }) = _Entitlement;

  factory Entitlement.fromJson(Map<String, dynamic> json) =>
      _$EntitlementFromJson(json);
}
