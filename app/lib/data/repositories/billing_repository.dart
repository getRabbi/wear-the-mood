import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/entitlement.dart';

/// Reads the user's premium entitlement (CLAUDE.md §18). The actual purchase
/// runs through the RevenueCat SDK (gated on the founder's account); this just
/// reflects the server-verified state.
class BillingRepository {
  BillingRepository(this._dio);

  final Dio _dio;

  Future<Entitlement> getEntitlement() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/billing/entitlement');
      return Entitlement.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(dioProvider));
});
