import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import '../network/dio_client.dart';

/// The consent version this build's disclosure copy corresponds to.
///
/// Sent when recording a grant so the server stores agreement to the terms that
/// were actually on screen, never to newer ones this build has never shown. The
/// server holds the version it currently REQUIRES and returns it, so this
/// constant is the client's half of the contract, not a second source of truth.
///
/// **This must move in lockstep with the server's
/// `CURRENT_AI_CONSENT_VERSION`.** A build that sends a lower version has its
/// grant refused with a typed error, because it displayed older terms — the
/// user is told to update rather than being walked into a consent loop.
const int aiConsentVersion = 2;

/// The user's AI data-sharing consent, as the server sees it.
class AiConsentState {
  const AiConsentState({
    required this.granted,
    required this.isCurrent,
    this.version,
    this.requiredVersion = aiConsentVersion,
  });

  /// Nothing known yet — distinct from "known to be denied". The gate treats it
  /// as "must ask", never as "may proceed".
  const AiConsentState.unknown()
    : granted = false,
      isCurrent = false,
      version = null,
      requiredVersion = aiConsentVersion;

  final bool granted;

  /// Granted AND at the version the SERVER currently requires. The only field
  /// the gate reads: a grant at an outdated version is not a usable permission.
  final bool isCurrent;

  final int? version;
  final int requiredVersion;

  factory AiConsentState.fromJson(Map<String, dynamic> json) => AiConsentState(
    granted: json['granted'] as bool? ?? false,
    isCurrent: json['is_current'] as bool? ?? false,
    version: (json['version'] as num?)?.toInt(),
    requiredVersion:
        (json['required_version'] as num?)?.toInt() ?? aiConsentVersion,
  );
}

/// Reads and writes the server-side AI data-sharing consent (§10).
///
/// The server is the durable source of truth on purpose: consent has to survive
/// reinstall and follow the ACCOUNT, not the device, or a user who allowed once
/// is re-prompted on every new phone and a user who withdrew has their
/// withdrawal quietly undone by a fresh install.
class AiConsentRepository {
  AiConsentRepository(this._dio);

  final Dio _dio;

  static const _path = '/v1/privacy/ai-consent';

  Future<AiConsentState> read() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_path);
      return AiConsentState.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AiConsentState> grant() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _path,
        data: {'consent_version': aiConsentVersion},
      );
      return AiConsentState.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AiConsentState> revoke() async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(_path);
      return AiConsentState.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final aiConsentRepositoryProvider = Provider<AiConsentRepository>((ref) {
  return AiConsentRepository(ref.watch(dioProvider));
});
