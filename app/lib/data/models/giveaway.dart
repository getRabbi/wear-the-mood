import 'package:freezed_annotation/freezed_annotation.dart';

part 'giveaway.freezed.dart';
part 'giveaway.g.dart';

/// A claim on a giveaway (FEATURES_COMMUNITY_PLUS · Giveaway). The [message] is
/// private to the giveaway owner (in-app contact only).
@freezed
abstract class GiveawayClaim with _$GiveawayClaim {
  const factory GiveawayClaim({
    required String id,
    @JsonKey(name: 'giveaway_id') required String giveawayId,
    @JsonKey(name: 'claimer_id') required String claimerId,
    @JsonKey(name: 'claimer_name') String? claimerName,
    String? message,
    required String status, // requested | accepted | declined
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GiveawayClaim;

  factory GiveawayClaim.fromJson(Map<String, dynamic> json) =>
      _$GiveawayClaimFromJson(json);
}

/// A peer-to-peer free-clothes listing. Public listing fields only — contact is
/// arranged in-app via a claim, never personal address/phone in the listing.
@freezed
abstract class Giveaway with _$Giveaway {
  const factory Giveaway({
    required String id,
    @JsonKey(name: 'owner_id') required String ownerId,
    @JsonKey(name: 'owner_name') String? ownerName,
    @JsonKey(name: 'wardrobe_item_id') String? wardrobeItemId,
    required String title,
    String? description,
    @Default(<String>[]) List<String> images,
    // Smaller images parallel to [images] (grid cover), where available.
    @Default(<String>[]) List<String> thumbnails,
    String? size,
    String? category,
    String? condition,
    @JsonKey(name: 'area_label') String? areaLabel,
    required String status, // available | reserved | claimed | closed
    @JsonKey(name: 'is_mine') @Default(false) bool isMine,
    @JsonKey(name: 'my_claim_status') String? myClaimStatus,
    @JsonKey(name: 'claim_count') @Default(0) int claimCount,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Giveaway;

  const Giveaway._();

  factory Giveaway.fromJson(Map<String, dynamic> json) =>
      _$GiveawayFromJson(json);

  bool get isAvailable => status == 'available';
  bool get hasClaimed => myClaimStatus != null;

  /// The grid cover image: the first thumbnail where available, else the first
  /// full image, else null.
  String? get coverImageUrl => thumbnails.isNotEmpty
      ? thumbnails.first
      : (images.isNotEmpty ? images.first : null);
}
