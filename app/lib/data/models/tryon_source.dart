import 'package:freezed_annotation/freezed_annotation.dart';

part 'tryon_source.freezed.dart';
part 'tryon_source.g.dart';

/// Where a render came from, when it came from the catalog (DISCOVER §13).
///
/// Persisted on the try-on job, so it survives the app being killed and comes
/// back with the result days later — which is the moment it matters, because
/// that is when someone returns to buy.
///
/// IDENTIFIERS ONLY. There is no price, no destination and no affiliate tag
/// here, and there must never be: a price carried on a job is a purchase claim
/// nobody re-verified, and §35 forbids presenting one as current. Everything a
/// purchase decision needs is re-read live through the Discover endpoints at
/// the moment the user acts.
///
/// Absent on every closet render and on every job created before this existed,
/// which is the same thing to a client — so an older result simply reads as an
/// ordinary look (§37.4).
@freezed
abstract class TryOnSource with _$TryOnSource {
  const factory TryOnSource({
    @JsonKey(name: 'product_id') required String productId,
    @Default('affiliate_product') String kind,
    @JsonKey(name: 'merchant_id') String? merchantId,
    String? placement,
    @JsonKey(name: 'campaign_id') String? campaignId,
  }) = _TryOnSource;

  factory TryOnSource.fromJson(Map<String, dynamic> json) =>
      _$TryOnSourceFromJson(json);
}
