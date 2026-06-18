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
}

final giveawayRepositoryProvider = Provider<GiveawayRepository>((ref) {
  return GiveawayRepository(ref.watch(dioProvider));
});

/// Available giveaways for the Community browse grid.
final giveawayBrowseProvider =
    FutureProvider.autoDispose<List<Giveaway>>((ref) {
  return ref.watch(giveawayRepositoryProvider).browse();
});

/// The current user's own listings.
final myGiveawaysProvider = FutureProvider.autoDispose<List<Giveaway>>((ref) {
  return ref.watch(giveawayRepositoryProvider).mine();
});

/// One giveaway's detail (refetched on invalidate, e.g. after claim/close).
final giveawayDetailProvider =
    FutureProvider.autoDispose.family<Giveaway, String>((ref, id) {
  return ref.watch(giveawayRepositoryProvider).get(id);
});

/// The claims on a listing (owner only).
final giveawayClaimsProvider =
    FutureProvider.autoDispose.family<List<GiveawayClaim>, String>((ref, id) {
  return ref.watch(giveawayRepositoryProvider).claims(id);
});
