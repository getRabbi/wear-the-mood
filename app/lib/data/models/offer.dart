import 'package:freezed_annotation/freezed_annotation.dart';

part 'offer.freezed.dart';
part 'offer.g.dart';

/// A curated/affiliate deal for the Newsroom "Offers" strip
/// (FEATURES_COMMUNITY_PLUS · Daily Offer). [affiliateUrl] is already
/// attribution-tagged by the backend.
@freezed
abstract class Offer with _$Offer {
  const factory Offer({
    required String id,
    required String title,
    String? brand,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'discount_label') String? discountLabel,
    @JsonKey(name: 'affiliate_url') required String affiliateUrl,
    @Default(<String>[]) List<String> topics,
  }) = _Offer;

  factory Offer.fromJson(Map<String, dynamic> json) => _$OfferFromJson(json);
}
