import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../shared/utils/uuid.dart';
import '../models/tryon_job.dart';
import '../models/tryon_result.dart';

/// Talks to the async try-on endpoints (CLAUDE.md §7). All AI runs server-side;
/// the app only creates jobs and polls — it never touches a provider key (§11).
class TryOnRepository {
  TryOnRepository(this._dio);

  final Dio _dio;

  /// Creates a try-on job. Supply exactly one garment source. Sends a unique
  /// `Idempotency-Key` so a retry never double-charges (§9). Returns the queued
  /// job ({job_id, status: queued}).
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    List<String>? garmentImageUrls,
    String? wardrobeItemId,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    String? idempotencyKey,
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/tryon',
        data: {
          'person_image_url': personImageUrl,
          'garment_image_url': ?garmentImageUrl,
          'garment_image_urls': ?garmentImageUrls,
          'wardrobe_item_id': ?wardrobeItemId,
          'hd': hd, // HD / Try-On Max — 4 credits, Pro Max only (server-gated)
          // Try-On Body System: own_photo (default) | studio_model (Pro/Pro Max).
          'model_source': modelSource,
          'preset_model_id': ?presetModelId,
          // Shopping origin (§13). The PRODUCT only — the merchant is derived
          // server-side, because attribution decides who gets paid and a
          // client that can name the merchant can name the wrong one (§38).
          // Absent entirely for a closet render.
          'source_product_id': ?sourceProductId,
          'source_placement': ?sourcePlacement,
          'source_campaign_id': ?sourceCampaignId,
        },
        options: Options(
          headers: {'Idempotency-Key': idempotencyKey ?? uuidV4()},
        ),
      );
      return TryOnJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Fetches the current status (and result URL once done) of a job.
  Future<TryOnJob> getJob(String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/tryon/$jobId');
      return TryOnJob.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The user's saved try-on results, newest first (history view).
  Future<List<TryonResult>> listResults() async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/tryon/results');
      return (res.data ?? [])
          .map((e) => TryonResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Permanently removes one result from the user's history and erases its
  /// stored image.
  ///
  /// Server-side this deletes only the RESULT — never the body photo or the
  /// garment it was rendered from, which belong to other rows and other
  /// renders. A 404 means it is already gone, which is the outcome the caller
  /// wanted; every other failure throws so the UI can put the tile back rather
  /// than claim a deletion that did not happen.
  Future<void> deleteResult(String resultId) async {
    try {
      await _dio.delete<void>('/v1/tryon/results/$resultId');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return;
      throw ApiException.fromDio(error);
    }
  }
}

final tryOnRepositoryProvider = Provider<TryOnRepository>((ref) {
  return TryOnRepository(ref.watch(dioProvider));
});

/// The user's try-on generation history, newest first.
///
/// Auto-disposes so it refreshes on reopen; invalidate after a new try-on
/// succeeds to show it. A notifier rather than a plain future because history
/// is now editable: [TryOnResults.delete] needs to take a tile off screen
/// immediately and put it back if the server refuses.
final tryOnResultsProvider =
    AsyncNotifierProvider.autoDispose<TryOnResults, List<TryonResult>>(
      TryOnResults.new,
    );

class TryOnResults extends AsyncNotifier<List<TryonResult>> {
  @override
  Future<List<TryonResult>> build() =>
      ref.watch(tryOnRepositoryProvider).listResults();

  /// Deletes one result: optimistic on screen, authoritative on the server.
  ///
  /// The tile disappears on the same frame — a grid that sits there while a
  /// request flies is how "did that work?" happens — and comes BACK, in its
  /// original position, if the request fails. Rethrows so the caller can say so
  /// rather than leaving a silently restored tile looking like a bug.
  ///
  /// Nothing here is local-only: the row and its stored image are gone
  /// server-side, so a refresh, a relaunch or a sign-in on another device all
  /// agree. That is the difference between this and a Saved Look, which is a
  /// device record.
  Future<void> delete(String resultId) async {
    final current = state.asData?.value;
    if (current == null) return;
    final index = current.indexWhere((r) => r.id == resultId);
    if (index < 0) return; // already gone — the caller got what it wanted

    final removed = current[index];
    state = AsyncData([
      for (final result in current)
        if (result.id != resultId) result,
    ]);
    try {
      await ref.read(tryOnRepositoryProvider).deleteResult(resultId);
    } catch (_) {
      final latest = state.asData?.value;
      if (latest != null && !latest.any((r) => r.id == resultId)) {
        final restored = [...latest];
        restored.insert(index.clamp(0, restored.length), removed);
        state = AsyncData(restored);
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
