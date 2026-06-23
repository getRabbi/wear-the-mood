import 'package:dio/dio.dart';

/// Stable error codes mirrored from the backend's uniform error contract
/// (CLAUDE.md §13). The UI switches on these to show localized, friendly copy.
abstract final class ApiErrorCode {
  static const unauthenticated = 'UNAUTHENTICATED';
  static const forbidden = 'FORBIDDEN';
  static const insufficientCredits = 'INSUFFICIENT_CREDITS';
  static const paywall = 'PAYWALL'; // out of credits / no plan — show upsell + top-up
  static const hdLocked = 'HD_LOCKED'; // HD / Try-On Max needs Pro Max
  static const rateLimited = 'RATE_LIMITED';
  static const providerError = 'PROVIDER_ERROR';
  static const validationError = 'VALIDATION_ERROR';
  static const moderationBlocked = 'MODERATION_BLOCKED';
  static const notFound = 'NOT_FOUND';

  /// Client-side: request never reached / parsed a server envelope.
  static const network = 'NETWORK_ERROR';
}

/// Typed application error parsed from the backend envelope
/// `{ "error": { code, message, request_id } }` (CLAUDE.md §13). Feature code
/// catches this instead of raw [DioException]s.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.requestId,
    this.statusCode,
  });

  final String code;
  final String message;
  final String? requestId;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final body = data['error'] as Map;
      return ApiException(
        code: body['code']?.toString() ?? ApiErrorCode.network,
        message: body['message']?.toString() ?? 'Request failed.',
        requestId: body['request_id']?.toString(),
        statusCode: error.response?.statusCode,
      );
    }
    return ApiException(
      code: ApiErrorCode.network,
      message: error.message ?? 'Network error. Please try again.',
      statusCode: error.response?.statusCode,
    );
  }

  bool get isInsufficientCredits => code == ApiErrorCode.insufficientCredits;

  /// Out of credits / no plan — the UI should open the paywall (+ top-up).
  bool get isPaywall =>
      code == ApiErrorCode.paywall || code == ApiErrorCode.insufficientCredits;

  /// HD / Try-On Max requested without a Pro Max plan — show the Pro Max upsell.
  bool get isHdLocked => code == ApiErrorCode.hdLocked;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
