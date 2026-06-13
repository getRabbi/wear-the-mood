import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';

/// Registers this device's FCM token for the daily stylist push (CLAUDE.md §20).
/// The backend scopes it to the JWT user; the app never holds FCM server creds (§11).
class PushRepository {
  PushRepository(this._dio);

  final Dio _dio;

  Future<void> registerToken(String token, {String platform = 'android'}) async {
    try {
      await _dio.put<void>(
        '/v1/profile/push-token',
        data: {'token': token, 'platform': platform},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteToken(String token) async {
    try {
      await _dio.delete<void>(
        '/v1/profile/push-token',
        queryParameters: {'token': token},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return PushRepository(ref.watch(dioProvider));
});
