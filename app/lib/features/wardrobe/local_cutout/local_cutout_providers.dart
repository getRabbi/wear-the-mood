/// Riverpod wiring for local-first background removal (local BG §9).
///
/// Deliberately thin. The platform resolves to the real method channel on Android
/// and iOS and to a safe no-op elsewhere, so nothing here can throw at
/// construction time on an unsupported platform — and a build with the gates off
/// never calls any of it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_cutout_cache.dart';
import 'local_cutout_method_channel.dart';
import 'local_cutout_orchestrator.dart';
import 'local_cutout_platform.dart';

/// The native bridge. Only Android and iOS have an engine; everywhere else the
/// unsupported implementation keeps every call a typed no-op.
final localCutoutPlatformProvider = Provider<LocalCutoutPlatform>((ref) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS =>
      MethodChannelLocalCutoutPlatform(),
    _ => const UnsupportedLocalCutoutPlatform(),
  };
});

final localCutoutCacheProvider = Provider<LocalCutoutCache>((ref) {
  return LocalCutoutCache(ref.watch(localCutoutPlatformProvider));
});

/// THE decision-maker for local vs cloud. Not autoDispose: it holds no state worth
/// discarding, and the Add Garment screen would otherwise rebuild it per open.
final localCutoutOrchestratorProvider = Provider<LocalCutoutOrchestrator>((ref) {
  return LocalCutoutOrchestrator(
    platform: ref.watch(localCutoutPlatformProvider),
    cache: ref.watch(localCutoutCacheProvider),
  );
});
