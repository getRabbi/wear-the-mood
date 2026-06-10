import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';

/// Account lifecycle — the MANDATORY data export + deletion (CLAUDE.md §10).
/// Both hit own-account endpoints scoped server-side to the JWT user (§11).
class AccountRepository {
  AccountRepository(this._dio);

  final Dio _dio;

  /// Fetches all of the user's data as JSON (GDPR export, §10).
  Future<Map<String, dynamic>> exportData() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/account/export');
      return res.data ?? const {};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Permanently deletes the account and all its data (§10). Irreversible; the
  /// caller should sign out + clear local state afterward.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete<void>('/v1/account');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(ref.watch(dioProvider));
});
