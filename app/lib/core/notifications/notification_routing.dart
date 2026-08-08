/// The single place notification TYPES are interpreted (CLAUDE.md §15, §20).
///
/// This used to be `type.contains('giveaway')`-style string matching duplicated
/// across the inbox rows, the icon picker and the tap handler. Three copies of a
/// fragile rule is three chances for a new event type to render with the wrong
/// icon, land in the wrong tab, or open nothing at all. Everything that needs to
/// reason about a notification type goes through here instead, and the mapping
/// mirrors the server's `app/services/notifications.py` table.
///
/// Nothing here throws on an unknown type: legacy rows written before a type
/// existed, and rows written by a newer backend than this build, must still
/// render and must still be tappable. Unknown resolves to a bell, the System
/// section, and no navigation.
library;

import '../../data/models/app_notification.dart';
import '../../ui/widgets/wtm_icons.dart';
import '../router/routes.dart';

/// Which inbox section a notification belongs to.
enum NotificationSection { activity, drops, system }

/// The canonical event types the backend emits. Kept as strings rather than an
/// enum at the model boundary so an unrecognised value from a newer server is
/// data, not a parse failure.
abstract final class NotificationTypes {
  static const like = 'like';
  static const comment = 'comment';
  static const follow = 'follow';
  static const mention = 'mention';
  static const reply = 'reply';

  static const giveawayRequest = 'giveaway_request';
  static const giveawayAccepted = 'giveaway_accepted';
  static const giveawayDeclined = 'giveaway_declined';
  static const giveawayMessage = 'giveaway_message';

  /// Legacy umbrella type. Rows created before the giveaway events were split
  /// still carry it, so it must keep resolving.
  static const giveaway = 'giveaway';

  static const offer = 'offer';
  static const promotion = 'promotion';
  static const referralReward = 'referral_reward';
  static const creditUpdate = 'credit_update';
  static const tryOnReady = 'try_on_ready';
  static const enhanceItem = 'enhance_item';
  static const catalogModel = 'catalog_model';
}

/// Target kinds the server sets on `target_type`.
abstract final class NotificationTargets {
  static const giveaway = 'giveaway';
  static const giveawayChat = 'giveaway_chat';
  static const post = 'post';
  static const user = 'user';
  static const offer = 'offer';
  static const news = 'news';
  static const wardrobeItem = 'wardrobe_item';
  static const generatedImage = 'generated_image';
  static const tryonResult = 'tryon_result';
  static const credit = 'credit';
  static const subscription = 'subscription';
}

extension NotificationRouting on AppNotification {
  /// Which inbox tab this belongs in. Driven by the TYPE first (authoritative)
  /// and only then by the target, so a new social event never lands in Drops
  /// because its target happened to contain a matching substring.
  NotificationSection get section {
    switch (type) {
      case NotificationTypes.like:
      case NotificationTypes.comment:
      case NotificationTypes.follow:
      case NotificationTypes.mention:
      case NotificationTypes.reply:
        return NotificationSection.activity;
      case NotificationTypes.giveaway:
      case NotificationTypes.giveawayRequest:
      case NotificationTypes.giveawayAccepted:
      case NotificationTypes.giveawayDeclined:
      case NotificationTypes.giveawayMessage:
      case NotificationTypes.offer:
      case NotificationTypes.promotion:
        return NotificationSection.drops;
    }
    return switch (targetType) {
      NotificationTargets.post ||
      NotificationTargets.user => NotificationSection.activity,
      NotificationTargets.giveaway ||
      NotificationTargets.giveawayChat ||
      NotificationTargets.offer ||
      NotificationTargets.news => NotificationSection.drops,
      _ => NotificationSection.system,
    };
  }

  /// The row icon.
  WtmGlyph get glyph {
    switch (type) {
      case NotificationTypes.like:
        return WtmGlyph.heart;
      case NotificationTypes.follow:
        return WtmGlyph.users;
      case NotificationTypes.comment:
      case NotificationTypes.reply:
      case NotificationTypes.mention:
      case NotificationTypes.giveawayMessage:
        return WtmGlyph.comment;
      case NotificationTypes.giveaway:
      case NotificationTypes.giveawayRequest:
      case NotificationTypes.giveawayAccepted:
      case NotificationTypes.giveawayDeclined:
        return WtmGlyph.gift;
      case NotificationTypes.offer:
      case NotificationTypes.promotion:
        return WtmGlyph.store;
      case NotificationTypes.creditUpdate:
      case NotificationTypes.referralReward:
        return WtmGlyph.coin;
      case NotificationTypes.tryOnReady:
      case NotificationTypes.enhanceItem:
      case NotificationTypes.catalogModel:
        return WtmGlyph.sparkle;
    }
    return switch (targetType) {
      NotificationTargets.news => WtmGlyph.image,
      NotificationTargets.user => WtmGlyph.users,
      NotificationTargets.subscription => WtmGlyph.sparkle,
      NotificationTargets.credit => WtmGlyph.coin,
      _ => WtmGlyph.bell,
    };
  }

  /// The in-app route this notification opens, or null when there is nothing
  /// specific to open (the caller then simply marks it read and stays put).
  ///
  /// Mirrors `route_for` on the server, which builds the same destinations for
  /// pushes that arrive while the app is terminated.
  String? get route {
    // A chat notification opens the CONVERSATION. The chat screen is addressed
    // by its giveaway id, which is what the server sends as the target.
    if (type == NotificationTypes.giveawayMessage ||
        targetType == NotificationTargets.giveawayChat) {
      final id = targetId ?? data['giveaway_id'] as String?;
      return id == null ? null : '${AppRoute.wtmGiveawayChat}?id=$id';
    }
    if (type == NotificationTypes.referralReward) return AppRoute.wtmReferral;

    final id = targetId;
    if (id == null || id.isEmpty) {
      return switch (targetType) {
        NotificationTargets.subscription => AppRoute.wtmPaywall,
        _ => null,
      };
    }
    return switch (targetType) {
      NotificationTargets.giveaway => '${AppRoute.wtmGiveawayDetail}?id=$id',
      NotificationTargets.offer => '${AppRoute.wtmOfferDetail}?id=$id',
      NotificationTargets.news => '${AppRoute.wtmArticle}?id=$id',
      NotificationTargets.post => '${AppRoute.wtmPost}?id=$id',
      NotificationTargets.user => '${AppRoute.wtmUser}?u=$id',
      NotificationTargets.wardrobeItem => '${AppRoute.wtmClosetItem}?id=$id',
      // AI Looks lists generated outputs newest-first, so the result this
      // notification is about is the first thing on screen. There is no
      // per-image route to address more precisely.
      NotificationTargets.generatedImage => AppRoute.wtmLooks,
      NotificationTargets.tryonResult => AppRoute.tryonHistory,
      NotificationTargets.subscription => AppRoute.wtmPaywall,
      _ => null,
    };
  }
}
