import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/referral_summary.dart';

/// Outcome of `POST /v1/referrals/claim` — the server-authoritative result. The
/// app never grants or computes referral credits itself (§11/§25).
class ReferralClaimResult {
  const ReferralClaimResult({
    required this.status,
    this.bonusCreditsAdded = 0,
    this.totalAvailable = 0,
  });

  /// awarded | already_claimed | not_eligible_existing_user | self_referral |
  /// invalid | expired | reused | disabled
  final String status;
  final int bonusCreditsAdded;
  final int totalAvailable;

  bool get awarded => status == 'awarded';

  /// A definitive outcome — the pending token should be cleared (never retried).
  /// Transient network/timeout failures throw instead and keep the token.
  bool get isTerminal => status != 'pending';

  factory ReferralClaimResult.fromJson(Map<String, dynamic> json) =>
      ReferralClaimResult(
        status: json['status'] as String? ?? 'invalid',
        bonusCreditsAdded: (json['bonus_credits_added'] as num?)?.toInt() ?? 0,
        totalAvailable: (json['total_available'] as num?)?.toInt() ?? 0,
      );
}

/// The install-attribution referral REWARDS API (§24): the user's standing
/// ([me]), minting an attribution token for an installed-app App Link ([click]),
/// and the authenticated [claim]. Separate from the legacy manual-code
/// [ReferralRepository] so the two never entangle.
class ReferralRewardsRepository {
  ReferralRewardsRepository(this._dio);

  final Dio _dio;

  Future<ReferralSummary> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/referrals/me');
      return ReferralSummary.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Mint an opaque attribution token for [code] (installed-app App Link path).
  Future<String> click(String code) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/referrals/click',
        data: {'code': code, 'platform': 'android'},
      );
      return res.data!['token'] as String;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ReferralClaimResult> claim({
    required String token,
    required String installId,
    String platform = 'android',
    String? appVersion,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/referrals/claim',
        data: {
          'token': token,
          'install_id': installId,
          'platform': platform,
          'app_version': appVersion, // optional; backend ignores when null
        },
      );
      return ReferralClaimResult.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final referralRewardsRepositoryProvider = Provider<ReferralRewardsRepository>(
  (ref) => ReferralRewardsRepository(ref.watch(dioProvider)),
);

/// The signed-in user's referral standing; auto-disposes so it refetches when
/// the referral screen re-opens. Invalidate after a reward is detected.
final referralSummaryProvider = FutureProvider.autoDispose<ReferralSummary>(
  (ref) => ref.watch(referralRewardsRepositoryProvider).me(),
);
