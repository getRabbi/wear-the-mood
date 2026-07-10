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
    // requested | accepted | declined | not_selected | cancelled | expired
    required String status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GiveawayClaim;

  factory GiveawayClaim.fromJson(Map<String, dynamic> json) =>
      _$GiveawayClaimFromJson(json);
}

/// The secret pickup chat between the giveaway owner and the ONE accepted
/// requester — active for exactly 7 days from the accept, then locked and
/// redacted server-side. Never visible to anyone else (§10).
@freezed
abstract class GiveawayPickupChat with _$GiveawayPickupChat {
  const factory GiveawayPickupChat({
    required String id,
    @JsonKey(name: 'giveaway_id') required String giveawayId,
    @JsonKey(name: 'giveaway_title') String? giveawayTitle,
    @JsonKey(name: 'owner_id') required String ownerId,
    @JsonKey(name: 'requester_id') required String requesterId,
    /// Display name of the OTHER participant (server picks per caller).
    @JsonKey(name: 'other_name') String? otherName,
    @JsonKey(name: 'is_owner') @Default(false) bool isOwner,
    // active | locked | completed | cancelled | expired
    required String status,
    @JsonKey(name: 'report_flag') @Default(false) bool reportFlag,
    @JsonKey(name: 'pickup_plan')
    @Default(<String, dynamic>{})
    Map<String, dynamic> pickupPlan,
    @JsonKey(name: 'approved_at') required DateTime approvedAt,
    @JsonKey(name: 'expires_at') required DateTime expiresAt,
    @JsonKey(name: 'locked_at') DateTime? lockedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GiveawayPickupChat;

  const GiveawayPickupChat._();

  factory GiveawayPickupChat.fromJson(Map<String, dynamic> json) =>
      _$GiveawayPickupChatFromJson(json);

  /// Open for messages: still `active` AND inside the 7-day window (the app
  /// double-checks the clock so a stale fetch can't look sendable).
  bool get isActive =>
      status == 'active' && DateTime.now().toUtc().isBefore(expiresAt.toUtc());

  Duration get timeLeft {
    final left = expiresAt.toUtc().difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  String? get planArea => pickupPlan['area'] as String?;
  String? get planLandmark => pickupPlan['landmark'] as String?;
  String? get planTimeSlot => pickupPlan['time_slot'] as String?;
  bool get planConfirmed => pickupPlan['confirmed'] == true;
  bool get hasPlan =>
      (planArea ?? planLandmark ?? planTimeSlot) != null || planConfirmed;
}

/// One text message in a pickup chat. [body] is null once the retention job
/// has redacted it ([bodyDeleted]).
@freezed
abstract class GiveawayChatMessage with _$GiveawayChatMessage {
  const factory GiveawayChatMessage({
    required String id,
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'sender_id') required String senderId,
    @JsonKey(name: 'is_mine') @Default(false) bool isMine,
    String? body,
    @JsonKey(name: 'body_deleted') @Default(false) bool bodyDeleted,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _GiveawayChatMessage;

  factory GiveawayChatMessage.fromJson(Map<String, dynamic> json) =>
      _$GiveawayChatMessageFromJson(json);
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
