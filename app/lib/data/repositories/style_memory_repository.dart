import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/style_memory.dart';

/// Style Memory: what WTM has learned, and the user's control over it
/// (RETENTION spec §12).
///
/// The server gates every WRITE on `feature_style_memory` and answers 404 when
/// the feature is off, which is why [recordSignal] swallows that specific case:
/// a taste signal is bookkeeping, and a flag being off is not an error the user
/// should ever see. Reads and deletes are never gated — a user must always be
/// able to see and erase what we hold about them.
class StyleMemoryRepository {
  StyleMemoryRepository(this._dio);

  final Dio _dio;

  Future<StyleMemoryProfile> getProfile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/style-memory');
      return StyleMemoryProfile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Record one taste signal. Returns null when the feature is off.
  ///
  /// `dedupeKey` makes a retry a genuine no-op on the server, so a double tap
  /// or a replayed request can never count twice.
  Future<StyleMemorySignalResult?> recordSignal({
    required String signalType,
    String? entityType,
    String? entityId,
    String? value,
    String? mood,
    String? occasion,
    RejectionReason? reason,
    String? dedupeKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/style-memory/signals',
        data: {
          'signal_type': signalType,
          'entity_type': ?entityType,
          'entity_id': ?entityId,
          'value': ?value,
          'mood': ?mood,
          'occasion': ?occasion,
          if (reason != null) 'reason': reason.wire,
          'dedupe_key': ?dedupeKey,
        },
      );
      return StyleMemorySignalResult.fromJson(res.data!);
    } on DioException catch (error) {
      // 404 = the flag is off. Silent by design: nothing the user did failed.
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  /// The user's own edit: state a preference, or remove one we inferred.
  Future<StyleMemoryProfile> correct({
    required String facet,
    required String value,
    bool remove = false,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/style-memory',
        data: {'facet': facet, 'value': value, 'remove': remove},
      );
      return StyleMemoryProfile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Stop (or resume) using Style Memory WITHOUT deleting it.
  Future<StyleMemoryProfile> setPersonalization({required bool enabled}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/style-memory/personalization',
        data: {'enabled': enabled},
      );
      return StyleMemoryProfile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Erase everything WTM has learned about this user.
  Future<int> reset() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/style-memory/reset',
      );
      return (res.data?['deleted_signals'] as num?)?.toInt() ?? 0;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Keep it / Not me on a finished render. **Never touches credits** — a
  /// technical or quality failure was already refunded before the user saw a
  /// result, and subjective dislike is a taste signal, not money (§19.3).
  Future<TryOnFeedbackResult?> submitFeedback({
    required String resultId,
    required bool kept,
    RejectionReason? reason,
    String? note,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/tryon/results/$resultId/feedback',
        data: {
          'outcome': kept ? 'kept' : 'rejected',
          if (reason != null) 'reason': reason.wire,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      return TryOnFeedbackResult.fromJson(res.data!);
    } on DioException catch (error) {
      // A result that no longer exists (deleted from another device) must not
      // present as a failure of the tap the user just made.
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }
}

final styleMemoryRepositoryProvider = Provider<StyleMemoryRepository>((ref) {
  return StyleMemoryRepository(ref.watch(dioProvider));
});

/// The user's Style Memory profile. Auto-disposes so re-opening the screen
/// refetches — corrections made on another device show up on the next visit.
final styleMemoryProvider = FutureProvider.autoDispose<StyleMemoryProfile>((
  ref,
) {
  return ref.watch(styleMemoryRepositoryProvider).getProfile();
});
