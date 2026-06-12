import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/referral.dart';

/// Referral loop (CLAUDE.md §24). The user shares their code; redeeming a code
/// grants both sides bonus credits, all verified server-side (§11).
class ReferralRepository {
  ReferralRepository(this._dio);

  final Dio _dio;

  Future<Referral> getReferral() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/referrals');
      return Referral.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Redeems a friend's code; returns the credits granted to the user.
  Future<int> redeem(String code) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/referrals/redeem',
        data: {'code': code},
      );
      return (res.data?['reward_credits'] as num?)?.toInt() ?? 0;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository(ref.watch(dioProvider));
});

/// The user's referral code + stats. Auto-disposes; invalidate after a redeem.
final referralProvider = FutureProvider.autoDispose<Referral>((ref) {
  return ref.watch(referralRepositoryProvider).getReferral();
});
