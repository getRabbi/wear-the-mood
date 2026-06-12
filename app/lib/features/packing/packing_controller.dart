import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/packing_plan.dart';
import '../../data/repositories/packing_repository.dart';

/// Drives one packing query. Idle is AsyncData(null); a plan replaces it. The
/// planner runs server-side and falls back to a deterministic heuristic on LLM
/// failure (§24), so a success here can still be the stub's list.
class PackingController extends Notifier<AsyncValue<PackingPlan?>> {
  @override
  AsyncValue<PackingPlan?> build() => const AsyncData(null);

  Future<void> plan({required int days, String? occasion}) async {
    if (state.isLoading) return; // guard double-taps
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(packingRepositoryProvider).plan(
        days: days,
        occasion: (occasion != null && occasion.trim().isNotEmpty)
            ? occasion.trim()
            : null,
      ),
    );
  }

  void reset() => state = const AsyncData(null);
}

final packingControllerProvider =
    NotifierProvider<PackingController, AsyncValue<PackingPlan?>>(
      PackingController.new,
    );
