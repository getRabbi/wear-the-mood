import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/profile.dart';

/// Profile + consent (CLAUDE.md §1, §10). Own-row, server-scoped to the JWT (§11).
class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<Profile> getProfile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/profile');
      return Profile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Partial update — only the supplied fields change.
  Future<Profile> updateProfile({
    String? displayName,
    String? phone,
    String? avatarUrl,
    String? profilePictureUrl,
    BodyData? bodyData,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/profile',
        data: {
          'display_name': ?displayName,
          'phone': ?phone,
          'avatar_url': ?avatarUrl,
          'profile_picture_url': ?profilePictureUrl,
          'body_data': ?bodyData?.toJson(),
        },
      );
      return Profile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Records explicit consent (e.g. biometric face/body, §10).
  Future<void> recordConsent({
    required String type,
    required String version,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/consents',
        data: {'consent_type': type, 'version': version},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioProvider));
});

final profileProvider = FutureProvider.autoDispose<Profile>((ref) {
  return ref.watch(profileRepositoryProvider).getProfile();
});
