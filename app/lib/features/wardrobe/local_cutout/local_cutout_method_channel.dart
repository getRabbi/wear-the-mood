/// The real [LocalCutoutPlatform] over `wtm/background_removal` (local BG §4, §8.4).
///
/// Thin and defensive. Two rules drive the whole file:
///
///  * **Nothing throws except a typed [LocalCutoutPlatformException].** A missing
///    plugin (`MissingPluginException` — an engine-less build, or iOS before
///    Phase 4), a malformed reply, or an unknown native code all resolve to a
///    typed reason so Add Garment quietly uses the cloud path.
///  * **Cleanup sends an operation ID, never a path** (blocker R10b). Native
///    re-validates the id and resolves it inside its own cache root.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'local_cutout_models.dart';
import 'local_cutout_platform.dart';

class MethodChannelLocalCutoutPlatform implements LocalCutoutPlatform {
  MethodChannelLocalCutoutPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kLocalCutoutChannel);

  final MethodChannel _channel;

  /// A little headroom over the native bound, so a native timeout (which carries
  /// a precise reason) wins the race against this generic one.
  static const Duration _channelGrace = Duration(seconds: 5);

  @override
  Future<LocalCutoutCapability> capability() async {
    final reply = await _invokeMap(
      LocalCutoutMethod.capability,
      <String, Object?>{'timeoutMs': 4000},
      timeout: const Duration(seconds: 9),
    );
    return LocalCutoutCapability.fromMap(reply);
  }

  @override
  Future<LocalCutoutCapability> prepare({required Duration timeout}) async {
    final reply = await _invokeMap(
      LocalCutoutMethod.prepare,
      <String, Object?>{
        'timeoutMs': timeout.inMilliseconds,
        // Deferred by default: Google Play services fetches the model in the
        // background rather than making the caller wait on a download.
        'urgent': false,
      },
      timeout: timeout + _channelGrace,
    );
    return LocalCutoutCapability.fromMap(reply);
  }

  @override
  Future<LocalCutoutResult> removeBackground({
    required Uint8List imageBytes,
    required Duration timeout,
    bool captureDiagnostics = false,
  }) async {
    final reply = await _invokeMap(
      LocalCutoutMethod.removeBackground,
      <String, Object?>{
        'imageBytes': imageBytes,
        'timeoutMs': timeout.inMilliseconds,
        'captureDiagnostics': captureDiagnostics,
      },
      timeout: timeout + _channelGrace,
      // A capability probe may legitimately fail soft; a removal may not.
      throwOnMissingReply: true,
    );
    final result = LocalCutoutResult.fromMap(reply);
    if (result == null) {
      // A reply we cannot decode is never treated as a success (§4).
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.invalidOutput,
        code: LocalCutoutErrorCode.invalidOutput,
      );
    }
    return result;
  }

  @override
  Future<void> cancel(String operationId) async {
    await _invokeVoid(
      LocalCutoutMethod.cancel,
      <String, Object?>{'operationId': operationId},
    );
  }

  @override
  Future<void> cleanup(String operationId) async {
    // An ID, not a path — see local_cutout_cache.dart.
    await _invokeVoid(
      LocalCutoutMethod.cleanup,
      <String, Object?>{'operationId': operationId},
    );
  }

  @override
  Future<int> sweepCache({required Duration maxAge}) async {
    try {
      final swept = await _channel
          .invokeMethod<int>(
            LocalCutoutMethod.sweepCache,
            <String, Object?>{'maxAgeMs': maxAge.inMilliseconds},
          )
          .timeout(const Duration(seconds: 15));
      return swept ?? 0;
    } on Object {
      // Housekeeping: a failure is retried next session, never surfaced.
      return 0;
    }
  }

  @override
  Future<LocalCutoutExportOutcome> exportDiagnostics(String operationId) async {
    // INTERNAL BUILDS ONLY. On every production binary the native side has this
    // compiled out and replies with a typed failure, which lands in the catch below
    // as `unavailable` — a normal outcome, never an error surfaced to anyone.
    try {
      final reply = await _channel
          .invokeMethod<Map<Object?, Object?>>(
            LocalCutoutMethod.exportDiagnostics,
            <String, Object?>{'operationId': operationId},
          )
          // A human is choosing a share destination, so this is generous.
          .timeout(const Duration(minutes: 5));
      return switch (reply?['status']) {
        'shared' => LocalCutoutExportOutcome.shared,
        'cancelled' => LocalCutoutExportOutcome.cancelled,
        _ => LocalCutoutExportOutcome.unavailable,
      };
    } on Object {
      return LocalCutoutExportOutcome.unavailable;
    }
  }

  Future<Map<Object?, Object?>?> _invokeMap(
    String method,
    Map<String, Object?> args, {
    required Duration timeout,
    bool throwOnMissingReply = false,
  }) async {
    try {
      final reply = await _channel
          .invokeMethod<Map<Object?, Object?>>(method, args)
          .timeout(timeout);
      if (reply == null && throwOnMissingReply) {
        throw const LocalCutoutPlatformException(
          LocalCutoutFallbackReason.invalidOutput,
          code: LocalCutoutErrorCode.invalidOutput,
        );
      }
      return reply;
    } on LocalCutoutPlatformException {
      rethrow;
    } on MissingPluginException {
      // No native engine in this build/platform. Expected, not exceptional.
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.channelUnavailable,
      );
    } on PlatformException catch (error) {
      throw LocalCutoutPlatformException(
        LocalCutoutErrorCode.toFallbackReason(error.code),
        code: error.code,
        // Present only on a diagnostic build; native sends nil otherwise.
        diagnosticOperationId: error.details is String
            ? error.details as String
            : null,
      );
    } on TimeoutException {
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.timeout,
        code: LocalCutoutErrorCode.timeout,
      );
    } on Object {
      // Channel codec errors and anything else: typed, and never a crash.
      throw const LocalCutoutPlatformException(
        LocalCutoutFallbackReason.nativeError,
      );
    }
  }

  /// Best-effort fire-and-forget. Never throws: these run on teardown paths.
  Future<void> _invokeVoid(String method, Map<String, Object?> args) async {
    try {
      await _channel
          .invokeMethod<void>(method, args)
          .timeout(const Duration(seconds: 10));
    } on Object {
      // Ignored by design.
    }
  }
}
