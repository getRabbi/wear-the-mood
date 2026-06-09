import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/credits.dart';

/// Reads the user's credit balance + daily free quota (CLAUDE.md §12).
class CreditsRepository {
  CreditsRepository(this._dio);

  final Dio _dio;

  Future<Credits> getCredits() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/credits');
      return Credits.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final creditsRepositoryProvider = Provider<CreditsRepository>((ref) {
  return CreditsRepository(ref.watch(dioProvider));
});

/// Current credit state; auto-disposes so it refetches when a screen re-opens.
final creditsProvider = FutureProvider.autoDispose<Credits>((ref) {
  return ref.watch(creditsRepositoryProvider).getCredits();
});
