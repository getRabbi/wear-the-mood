import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/giveaway.dart';

/// Talks to the giveaway endpoints (FEATURES_COMMUNITY_PLUS · Giveaway). All
/// writes are owner/claimer-scoped server-side; images + text are moderated
/// before publish; contact stays in-app (§10, §19).
class GiveawayRepository {
  GiveawayRepository(this._dio);

  final Dio _dio;

  Future<List<Giveaway>> browse({String? category, String? size}) =>
      _list('/v1/giveaways', {'category': ?category, 'size': ?size});

  Future<List<Giveaway>> mine() => _list('/v1/giveaways/mine', const {});

  /// Listings the caller has REQUESTED, in any state. Browse only returns
  /// `available` listings, so the moment an owner accepts (status → `reserved`)
  /// this is the requester's only way back to their own pickup.
  Future<List<Giveaway>> requested() =>
      _list('/v1/giveaways/requested', const {});

  Future<List<Giveaway>> _list(String path, Map<String, dynamic> query) async {
    try {
      final res = await _dio.get<List<dynamic>>(path, queryParameters: query);
      return (res.data ?? const [])
          .map((e) => Giveaway.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Giveaway> get(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/giveaways/$id');
      return Giveaway.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Giveaway> create({
    required String title,
    String? description,
    List<String> images = const [],
    String? size,
    String? category,
    String? condition,
    String? areaLabel,
    String? wardrobeItemId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/giveaways',
        data: {
          'title': title,
          'description': ?description,
          'images': images,
          'size': ?size,
          'category': ?category,
          'condition': ?condition,
          'area_label': ?areaLabel,
          'wardrobe_item_id': ?wardrobeItemId,
        },
      );
      return Giveaway.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> claim(String id, {String? message}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/giveaways/$id/claim',
        data: {'message': ?message},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<GiveawayClaim>> claims(String id) async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/giveaways/$id/claims');
      return (res.data ?? const [])
          .map((e) => GiveawayClaim.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> decide(String giveawayId, String claimId, String status) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/v1/giveaways/$giveawayId/claims/$claimId',
        data: {'status': status},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> updateStatus(String id, String status) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/v1/giveaways/$id',
        data: {'status': status},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// PERMANENTLY delete the caller's own listing (owner only).
  ///
  /// Distinct from [updateStatus] with `closed`: closing keeps the post and its
  /// history, this removes the listing, its requests, its pickup chat and the
  /// public media the server owns. There is no undo, which is why the caller
  /// must confirm first.
  ///
  /// Ownership is enforced SERVER-side. A non-owner gets the same 404 as a
  /// missing listing — deliberately indistinguishable, so this endpoint cannot
  /// be used to probe whether someone else's giveaway exists.
  ///
  /// Throws [ApiException] on any failure and returns normally only on success,
  /// so a caller must never remove the post locally before this completes.
  Future<void> delete(String giveawayId) async {
    try {
      await _dio.delete<void>('/v1/giveaways/$giveawayId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  // ── secret pickup chat (owner ↔ accepted requester, 7 days) ───────────────

  /// Withdraw the caller's own request. If it was the accepted one, the pickup
  /// chat locks immediately server-side.
  Future<void> cancelClaim(String giveawayId) async {
    try {
      await _dio.delete<void>('/v1/giveaways/$giveawayId/claim');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The caller's pickup chat on a listing, or null when there isn't one (or
  /// the caller isn't a participant — the server 404s both the same way).
  Future<GiveawayPickupChat?> getChat(String giveawayId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/giveaways/$giveawayId/chat',
      );
      return GiveawayPickupChat.fromJson(res.data!);
    } on DioException catch (error) {
      final e = ApiException.fromDio(error);
      if (e.statusCode == 404) return null;
      throw e;
    }
  }

  /// The chat transcript, oldest first.
  ///
  /// Pass [after] (the `createdAt` of the newest message already held) to fetch
  /// only what has arrived since. The open-chat poll uses that so a five-second
  /// tick costs a few rows instead of re-downloading the whole conversation;
  /// omitting it returns everything, exactly as before.
  Future<List<GiveawayChatMessage>> chatMessages(
    String chatId, {
    DateTime? after,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/giveaways/chats/$chatId/messages',
        queryParameters: {
          if (after != null) 'after': after.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => GiveawayChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<GiveawayChatMessage> sendChatMessage(
    String chatId,
    String body,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/giveaways/chats/$chatId/messages',
        data: {'body': body},
      );
      return GiveawayChatMessage.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<GiveawayPickupChat> updatePickupPlan(
    String chatId, {
    String? area,
    String? landmark,
    String? timeSlot,
    bool confirmed = false,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/giveaways/chats/$chatId/plan',
        data: {
          'area': ?area,
          'landmark': ?landmark,
          'time_slot': ?timeSlot,
          'confirmed': confirmed,
        },
      );
      return GiveawayPickupChat.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Report the chat — freezes the transcript for moderation review (it is
  /// never redacted while under review).
  Future<void> reportChat(String chatId, {String? reason}) async {
    try {
      await _dio.post<void>(
        '/v1/giveaways/chats/$chatId/report',
        data: {'reason': ?reason},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final giveawayRepositoryProvider = Provider<GiveawayRepository>((ref) {
  return GiveawayRepository(ref.watch(dioProvider));
});

/// Available giveaways for the Community browse grid.
final giveawayBrowseProvider = FutureProvider.autoDispose<List<Giveaway>>((
  ref,
) {
  return ref.watch(giveawayRepositoryProvider).browse();
});

/// The current user's own listings.
final myGiveawaysProvider = FutureProvider.autoDispose<List<Giveaway>>((ref) {
  return ref.watch(giveawayRepositoryProvider).mine();
});

/// Listings the current user has requested — the requester-side counterpart of
/// [myGiveawaysProvider]. Invalidate alongside it after any claim/accept change.
final requestedGiveawaysProvider = FutureProvider.autoDispose<List<Giveaway>>((
  ref,
) {
  return ref.watch(giveawayRepositoryProvider).requested();
});

/// One giveaway's detail (refetched on invalidate, e.g. after claim/close).
final giveawayDetailProvider = FutureProvider.autoDispose
    .family<Giveaway, String>((ref, id) {
      return ref.watch(giveawayRepositoryProvider).get(id);
    });

/// The claims on a listing (owner only).
final giveawayClaimsProvider = FutureProvider.autoDispose
    .family<List<GiveawayClaim>, String>((ref, id) {
      return ref.watch(giveawayRepositoryProvider).claims(id);
    });
