import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'age_gate_repository.dart';
import 'onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(const FlutterSecureStorage());
});

/// Whether onboarding is done — decides the first screen (RootGate). Invalidated
/// when onboarding completes so the gate re-resolves to the app.
final onboardingSeenProvider = FutureProvider<bool>((ref) {
  return ref.watch(onboardingRepositoryProvider).isComplete();
});

final ageGateRepositoryProvider = Provider<AgeGateRepository>((ref) {
  return AgeGateRepository(const FlutterSecureStorage());
});

/// Whether the mandatory 16+ age gate has been accepted (current version).
/// Checked first in RootGate; invalidated on acceptance so the gate re-resolves.
final ageGateAcceptedProvider = FutureProvider<bool>((ref) {
  return ref.watch(ageGateRepositoryProvider).isAccepted();
});
