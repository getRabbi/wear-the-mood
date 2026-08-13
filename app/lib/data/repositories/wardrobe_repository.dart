import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/wardrobe_analytics.dart';
import '../models/wardrobe_gap.dart';
import '../models/wardrobe_item.dart';

/// The digital almira's data layer (CLAUDE.md §5). All calls hit own-row
/// endpoints scoped server-side to the JWT user (§11). Adding an item (with
/// image upload + background removal, §8/§2.2) is a later, gated step — this
/// covers list + remove.
class WardrobeRepository {
  WardrobeRepository(this._dio);

  final Dio _dio;

  /// How many pieces one closet page carries.
  ///
  /// Comfortably more than a phone screen shows, so the first paint is complete
  /// and scrolling has headroom, while a large closet no longer pays for its
  /// whole self — every row resolved and every private URL signed — on open.
  static const pageSize = 60;

  /// The user's closet, newest first.
  ///
  /// Pass [before] (the `createdAt` of the oldest piece you already hold) for
  /// the next page. Both parameters are optional server-side, so a shipped
  /// client that sends neither still gets the whole closet.
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/wardrobe',
        queryParameters: {
          'limit': ?limit,
          'before': ?before?.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Adds a piece to the closet. The image is already uploaded to storage (§8):
  /// send its R2 [objectKey] (private, write-gate on) OR the legacy [imageUrl] —
  /// exactly one. Background removal + tagging (§2.2) fill the rest server-side.
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/wardrobe',
        data: {
          'title': ?title,
          'category': ?category,
          if (objectKey != null)
            'object_key': objectKey
          else
            'image_url': imageUrl,
        },
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Adds a piece whose cutout was produced ON DEVICE (local BG §9.2).
  ///
  /// A separate method rather than more nullable parameters on [addItem]: the two
  /// hit different endpoints with different guarantees, and conflating them is how
  /// an "is this the local or the cloud path?" bug gets written.
  ///
  /// [originalObjectKey] is the SAME key the original was uploaded under, which is
  /// also the endpoint's idempotency identity — so a retry returns the already
  /// created item instead of a duplicate. [maskPng] is the device's soft mask; the
  /// server re-composites the cutout from the stored original.
  ///
  /// Retries **once**, and only for transient failures. A validation or auth error
  /// is never retried — it would fail identically — and is surfaced so the caller
  /// can fall back to the cloud create with the same object key.
  Future<WardrobeItem> addItemWithLocalCutout({
    required String originalObjectKey,
    required Uint8List maskPng,
    required String engine,
    required String platform,
    String engineVersion = '',
    int localLatencyMs = 0,
    int subjectCount = 0,
    String? title,
    String? category,
  }) async {
    ApiException? transient;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          '/v1/wardrobe/local-cutout',
          data: FormData.fromMap({
            'original_object_key': originalObjectKey,
            // A fresh MultipartFile per attempt: a FormData stream cannot be replayed.
            'mask': MultipartFile.fromBytes(maskPng, filename: 'mask.png'),
            'engine': engine,
            'platform': platform,
            'engine_version': engineVersion,
            'local_latency_ms': localLatencyMs,
            'subject_count': subjectCount,
            'title': ?title,
            'category': ?category,
          }),
        );
        return WardrobeItem.fromJson(res.data!);
      } on DioException catch (error) {
        final api = ApiException.fromDio(error);
        if (attempt == 0 && _isTransient(error)) {
          // The commit may in fact have landed; the retry is idempotent on the
          // object key, so it returns that item rather than making a second one.
          transient = api;
          continue;
        }
        throw api;
      }
    }
    throw transient!;
  }

  /// Asks the server to re-run the automatic BiRefNet cutout for [id]
  /// (local BG §6.4) — the "Improve edges" action.
  ///
  /// FREE: spends no credits and checks no membership. Distinct from
  /// [uploadCutoutMask], which is the manual Erase/Restore editor.
  ///
  /// The returned item still carries the CURRENT cutout — the server does not clear
  /// it — so the caller keeps rendering the existing image while the new one is
  /// computed, and still has it if the worker fails. A duplicate tap while an
  /// attempt is in flight is a server-side no-op that returns the item unchanged.
  Future<WardrobeItem> requestBiRefNetImprovement(String id) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/wardrobe/$id/improve-cutout',
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Worth one idempotent retry: no response, a dropped connection, or a 5xx.
  /// Never a 4xx — those are decisions, not accidents.
  static bool _isTransient(DioException error) {
    final status = error.response?.statusCode;
    if (status != null) return status >= 500;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }

  /// Edits/categorizes an owned item — name, category, subcategory, color
  /// (real-device polish). Sends the fields the categorize flow manages; a null
  /// value clears that field server-side. Returns the updated item.
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    required String? color,
    String? subcategory,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/wardrobe/$id',
        data: {
          'title': title,
          'category': category,
          'color': color,
          'subcategory': ?subcategory,
        },
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Uploads a hand-edited cutout mask (PNG whose alpha channel is the corrected
  /// mask) for item [id] and returns the item with its freshly re-composited
  /// cutout (§ BG upgrade Phase 7). FREE — spends no credits and runs no AI. The
  /// backend 404s when the editor is disabled and 503s when private storage is
  /// unavailable; both surface as an [ApiException].
  Future<WardrobeItem> uploadCutoutMask(String id, Uint8List maskPng) async {
    try {
      final form = FormData.fromMap({
        'mask': MultipartFile.fromBytes(maskPng, filename: 'mask.png'),
      });
      final res = await _dio.put<Map<String, dynamic>>(
        '/v1/wardrobe/$id/cutout-mask',
        data: form,
      );
      return WardrobeItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Semantic search over the closet (§2.1, §24). The backend embeds [query]
  /// and ranks by similarity, falling back to keyword match server-side.
  Future<List<WardrobeItem>> search({
    required String query,
    int limit = 20,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/wardrobe/search',
        queryParameters: {'q': query, 'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Removes one owned item. The backend 404s if it isn't the caller's (§11).
  Future<void> deleteItem(String id) async {
    try {
      await _dio.delete<void>('/v1/wardrobe/$id');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Cost-per-wear + ROI insights over the closet (§24).
  Future<WardrobeAnalytics> getAnalytics() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/wardrobe/analytics',
      );
      return WardrobeAnalytics.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Logs a wear of [id] (+1 wear_count), feeding cost-per-wear (§24).
  Future<void> markWorn(String id) async {
    try {
      await _dio.post<void>('/v1/wardrobe/$id/wear');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Closet-gap analysis: essentials the user is missing (§24).
  Future<List<WardrobeGap>> getGaps() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/wardrobe/gaps');
      return (res.data ?? const [])
          .map((e) => WardrobeGap.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return WardrobeRepository(ref.watch(dioProvider));
});
