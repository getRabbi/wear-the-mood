import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/monetization.dart';

/// The server-authoritative monetization snapshot (RETENTION spec §39).
///
/// This exists so an experiment number can change without a binary release. It
/// is **descriptive**: every cost, gate and entitlement is still enforced
/// server-side, so a client that never called this would face exactly the same
/// charges — it would just show worse copy.
class MonetizationRepository {
  MonetizationRepository(this._dio);

  final Dio _dio;

  Future<MonetizationConfig> getConfig() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/monetization/config',
      );
      return MonetizationConfig.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Record that a monetization surface was shown, dismissed or acted on.
  ///
  /// Fire-and-forget: a paywall must never fail to open, or fail to close,
  /// because its bookkeeping call did. `interruptive` is true ONLY when WTM
  /// raised the surface itself — a paywall the user opened by tapping Upgrade
  /// must send false, or it would start a cooldown against itself.
  Future<void> recordEvent({
    required MonetizationSurface surface,
    required MonetizationAction action,
    bool interruptive = false,
    Map<String, String>? context,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/monetization/events',
        data: {
          'surface': surface.wire,
          'action': action.wire,
          'interruptive': interruptive,
          'context': ?context,
        },
      );
    } on DioException {
      // Deliberately swallowed. The ledger is for us, not for the user.
    }
  }
}

final monetizationRepositoryProvider = Provider<MonetizationRepository>((ref) {
  return MonetizationRepository(ref.watch(dioProvider));
});

/// The monetization policy in force for this user right now.
///
/// Auto-disposes so it refetches when a paywall or gate re-opens: a config
/// cached across a purchase would show a user their old allowance.
final monetizationConfigProvider =
    FutureProvider.autoDispose<MonetizationConfig>((ref) {
      return ref.watch(monetizationRepositoryProvider).getConfig();
    });
