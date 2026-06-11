import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/stylist_repository.dart';
import 'stylist_state.dart';

/// Drives one stylist query: ask the backend, fire analytics, surface friendly
/// errors. The LLM runs server-side and falls back to a deterministic pick on
/// failure (§2.1), so a success here can still be the stub's outfit.
class StylistController extends Notifier<StylistState> {
  @override
  StylistState build() => const StylistState.idle();

  Future<void> styleMe({String? occasion, String? note}) async {
    if (state is StylistLoading) return; // guard double-taps
    final repo = ref.read(stylistRepositoryProvider);
    final analytics = ref.read(analyticsProvider);
    state = const StylistState.loading();

    try {
      await analytics.track(AnalyticsEvents.stylistQueried);
      final suggestion = await repo.suggest(occasion: occasion, note: note);
      state = StylistState.success(suggestion);
    } on ApiException catch (error) {
      state = StylistState.failure(message: error.message, code: error.code);
    } catch (_) {
      state = const StylistState.failure(
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  void reset() => state = const StylistState.idle();
}

final stylistControllerProvider =
    NotifierProvider<StylistController, StylistState>(StylistController.new);
